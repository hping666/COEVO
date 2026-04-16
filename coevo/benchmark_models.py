"""
Baseline testing tool: N independent LLM generations per design (no evolution).
Evaluates pass@k, selects best candidate, runs PPA on it.

Usage:
    python -m coevo.benchmark_models --config coevo/config/default.yaml --dataset verilogeval
    python -m coevo.benchmark_models --config ... --runs 10
    python -m coevo.benchmark_models --config ... --model gpt-4.1-mini --model gpt-5-mini
    python -m coevo.benchmark_models --config ... --design accu
    python -m coevo.benchmark_models --config ... --override llm.mutation_model=gpt-5
"""
import argparse
import os
import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

from coevo.utils.file_io import load_yaml, save_yaml, expand_path, ensure_dir
from coevo.llm.api_client import LLMClient
from coevo.llm.response_parser import parse_llm_response
from coevo.evaluation.correctness import CorrectnessEvaluator
from coevo.evaluation.ppa import PPAEvaluator
from coevo.core.individual import PPAMetrics
from coevo.datasets import get_adapter, DesignInfo
from coevo.datasets.base import DatasetAdapter
from coevo.run_coevo import (
    apply_override, pass_at_k, K_CANDIDATES, generate_experiment_report,
)

logger = logging.getLogger("coevo.baseline")


def build_baseline_prompt(spec: str, module_header: str, system_message: str) -> list:
    """Build a single-shot generation prompt (no evolution context)."""
    user_msg = f"""Implement the following hardware design.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

Additionally, optimize the design for better PPA (Power, Performance, Area) while maintaining functional correctness.

The module header above must be used exactly."""
    return [
        {"role": "system", "content": system_message},
        {"role": "user", "content": user_msg},
    ]


class BaselineRunner:
    """Run N independent LLM generations for one design with one model."""

    def __init__(self, design_info: DesignInfo, model_name: str,
                 config: dict, exp_dir: str, adapter: DatasetAdapter):
        self.design_info = design_info
        self.model_name = model_name
        self.config = config
        self.exp_dir = exp_dir
        self.adapter = adapter

        self.llm = LLMClient(config['models'], config.get('llm', {}))
        self.correctness_eval = CorrectnessEvaluator(config, adapter)
        self.ppa_eval = PPAEvaluator(config, adapter)

        self.spec = adapter.load_spec(design_info)
        self.module_header = adapter.load_module_header(design_info)
        self.module_name = adapter.extract_module_name(design_info)

    def run(self, n_trials: int) -> dict:
        """Run N independent generations. Return result dict compatible with coevo."""
        prompt = build_baseline_prompt(self.spec, self.module_header,
                                        self.adapter.get_system_message())
        workers = self.config['evolution'].get('parallel_workers', 1)

        design_dir = os.path.join(self.exp_dir, self.design_info.name)
        ensure_dir(design_dir)

        # Generate and evaluate N trials
        if workers <= 1:
            trials = self._run_sequential(prompt, n_trials, design_dir)
        else:
            trials = self._run_parallel(prompt, n_trials, workers, design_dir)

        # Select best candidate
        best_trial = self._select_best(trials)

        # PPA evaluation on best candidate
        best_ppa = None
        ref_ppa = None
        if best_trial and best_trial.get('code'):
            # Original TB final check (fresh evaluation, RTLLM standard)
            orig_pass = self.correctness_eval.evaluate_original_tb(
                best_trial['code'], self.design_info, self.module_name)

            # PPA
            if best_trial['enhanced_score'] > 0:
                try:
                    ppa_result, _ = self.ppa_eval.evaluate(
                        best_trial['code'], self.module_name, self.design_info.name)
                    if ppa_result:
                        best_ppa = ppa_result.__dict__
                except Exception as e:
                    logger.warning(f"PPA evaluation failed for {self.design_info.name}: {e}")

            # Reference PPA (via adapter — handles any module-name rewriting)
            ref_code = self.adapter.load_reference_code(self.design_info)
            if ref_code:
                try:
                    ref_result, _ = self.ppa_eval.evaluate(
                        ref_code, self.module_name, self.design_info.name)
                    if ref_result:
                        ref_ppa = ref_result.__dict__
                except Exception:
                    pass

            # Save best code
            with open(os.path.join(design_dir, "best_correct.v"), 'w') as f:
                f.write(best_trial['code'])
        else:
            orig_pass = False

        # Compute pass@k info
        n = len(trials)
        c = sum(1 for t in trials if t.get('original_pass'))

        # Build result dict (same schema as coevo's _compile_results)
        usage = self.llm.get_usage_summary()
        result = {
            'design': self.design_info.name,
            'pass': orig_pass,
            'enhanced_score': best_trial['enhanced_score'] if best_trial else 0,
            'original_tb_pass': orig_pass,
            'passed_checks': best_trial.get('passed', 0) if best_trial else 0,
            'total_checks': best_trial.get('total', 0) if best_trial else 0,
            'best_ppa': best_ppa,
            'ref_ppa': ref_ppa,
            'cost': usage,
            'n_trials': n,
            'n_pass': c,
        }

        # Save trial details
        trials_summary = {
            'design': self.design_info.name,
            'model': self.model_name,
            'n_trials': n,
            'n_pass': c,
            'best_trial_id': best_trial.get('trial_id', -1) if best_trial else -1,
            'trials': [
                {
                    'trial_id': t['trial_id'],
                    'enhanced_score': t['enhanced_score'],
                    'passed': t.get('passed', 0),
                    'total': t.get('total', 0),
                    'original_pass': t.get('original_pass', False),
                    'error': t.get('error', ''),
                }
                for t in trials
            ],
            'cost': usage,
        }
        with open(os.path.join(design_dir, "summary.json"), 'w') as f:
            json.dump(trials_summary, f, indent=2)

        return result

    def _run_sequential(self, prompt: list, n: int, design_dir: str) -> list:
        """Run N trials sequentially."""
        trials = []
        for i in range(n):
            trial = self._run_one_trial(prompt, i, design_dir)
            trials.append(trial)
            score_str = f"{trial['enhanced_score']:.2f}"
            orig_str = "PASS" if trial.get('original_pass') else "FAIL"
            logger.info(f"  [{self.design_info.name}] Trial {i}: enh={score_str} orig={orig_str}")
        return trials

    def _run_parallel(self, prompt: list, n: int, workers: int, design_dir: str) -> list:
        """Run N trials in parallel."""
        trials = [None] * n
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(self._run_one_trial, prompt, i, design_dir): i
                for i in range(n)
            }
            for future in as_completed(futures):
                i = futures[future]
                try:
                    trial = future.result()
                    trials[i] = trial
                    score_str = f"{trial['enhanced_score']:.2f}"
                    orig_str = "PASS" if trial.get('original_pass') else "FAIL"
                    logger.info(f"  [{self.design_info.name}] Trial {i}: enh={score_str} orig={orig_str}")
                except Exception as e:
                    logger.warning(f"  [{self.design_info.name}] Trial {i} failed: {e}")
                    trials[i] = {
                        'trial_id': i, 'enhanced_score': 0.0, 'passed': 0,
                        'total': 0, 'original_pass': False, 'code': '',
                        'error': str(e),
                    }
        return trials

    def _run_one_trial(self, prompt: list, trial_id: int, design_dir: str) -> dict:
        """Single LLM call + correctness eval. Thread-safe."""
        try:
            response = self.llm.call(
                self.model_name, prompt,
                temperature=self.config['llm']['temperature'].get('generation', 1.0))
            thought, code = parse_llm_response(response['content'])

            if not code:
                return {
                    'trial_id': trial_id, 'enhanced_score': 0.0, 'passed': 0,
                    'total': 0, 'original_pass': False, 'code': '',
                    'error': 'parse_fail',
                }

            # Save generated code
            code_path = os.path.join(design_dir, f"trial_{trial_id}.v")
            with open(code_path, 'w') as f:
                f.write(code)

            # Correctness: enhanced TB (continuous score)
            corr = self.correctness_eval.evaluate(code, self.design_info, self.module_name)

            # Also run original TB for pass@k computation
            orig_pass = self.correctness_eval.evaluate_original_tb(
                code, self.design_info, self.module_name)

            return {
                'trial_id': trial_id,
                'enhanced_score': corr['score'],
                'passed': corr['passed'],
                'total': corr['total'],
                'original_pass': orig_pass,
                'code': code,
                'error': corr.get('error_feedback', ''),
            }

        except Exception as e:
            return {
                'trial_id': trial_id, 'enhanced_score': 0.0, 'passed': 0,
                'total': 0, 'original_pass': False, 'code': '',
                'error': str(e),
            }

    def _select_best(self, trials: list) -> dict:
        """Select best candidate: prefer orig_pass with min ADP potential,
        else max enhanced_score."""
        if not trials:
            return None

        # First: candidates that pass original TB
        passing = [t for t in trials if t.get('original_pass') and t.get('code')]
        if passing:
            # Among passing, prefer highest enhanced score (proxy for quality)
            return max(passing, key=lambda t: t['enhanced_score'])

        # Fallback: max enhanced score
        with_code = [t for t in trials if t.get('code')]
        if with_code:
            return max(with_code, key=lambda t: t['enhanced_score'])

        return trials[0] if trials else None


def generate_baseline_experiment_name(config: dict, n_runs: int, model_names: list) -> str:
    """Generate experiment name for baseline."""
    if len(model_names) == 1:
        abbrevs = {
            "gpt-4o-mini": "gpt4om", "gpt-4o": "gpt4o", "gpt-4.1-mini": "gpt41m",
            "gpt-5-mini": "gpt5m", "gpt-5.4-mini": "gpt54m",
            "gpt-5.1-codex-mini": "gpt51cm", "gpt-5": "gpt5", "gpt-5.1": "gpt51",
            "gpt-5.4": "gpt54", "gpt-5-codex": "gpt5c", "gpt-5.1-codex": "gpt51c",
        }
        model_tag = abbrevs.get(model_names[0], model_names[0])
    else:
        model_tag = f"{len(model_names)}models"
    ts = datetime.now().strftime("%m%d_%H%M")
    return f"baseline_{model_tag}_N{n_runs}_{ts}"


def main():
    parser = argparse.ArgumentParser(description="Baseline: N independent LLM generations")
    parser.add_argument('--config', required=True, help="Path to config YAML")
    parser.add_argument('--dataset', default='rtllm', choices=['rtllm', 'verilogeval'])
    parser.add_argument('--experiment_name', default='')
    parser.add_argument('--runs', type=int, default=None,
                        help="Number of independent generations per design (overrides config)")
    parser.add_argument('--override', action='append', default=[],
                        help="Override config values: key.subkey=value")
    parser.add_argument('--model', action='append', default=[],
                        help="Model(s) to test. Can specify multiple. Default: all in models.yaml")
    parser.add_argument('--design', default=None,
                        help="Test a single design (e.g., accu). Default: all designs")
    args = parser.parse_args()

    # Load config
    config = load_yaml(args.config)
    models_path = os.path.join(os.path.dirname(args.config), 'models.yaml')
    models_config = load_yaml(models_path)
    config['models'] = models_config['models']

    # Apply overrides
    for override in args.override:
        apply_override(config, override)

    # Record dataset selection in snapshot
    config.setdefault('experiment', {})['dataset'] = args.dataset

    # Determine number of runs
    n_runs = args.runs or config.get('experiment', {}).get('runs', 1)
    n_runs = max(1, n_runs)

    # Determine models to test
    model_names = args.model if args.model else list(config['models'].keys())

    # Validate models
    for m in model_names:
        if m not in config['models']:
            print(f"[ERROR] Model '{m}' not found in models.yaml")
            print(f"Available: {list(config['models'].keys())}")
            return

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, config.get('logging', {}).get('level', 'INFO')),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)

    # Discover designs
    adapter = get_adapter(args.dataset)
    dataset_root = expand_path(
        config['paths'].get(f'{args.dataset}_root')
        or config['paths'].get('rtllm_root'))
    all_designs = adapter.discover_designs(dataset_root)

    if args.design:
        designs = [d for d in all_designs if d.name == args.design]
        if not designs:
            print(f"[ERROR] Design '{args.design}' not found in {dataset_root}")
            print(f"Available: {[d.name for d in all_designs]}")
            return
    else:
        designs = all_designs

    # Generate experiment name and directory
    exp_name = args.experiment_name or generate_baseline_experiment_name(
        config, n_runs, model_names)
    exp_dir = os.path.join(expand_path(config['paths']['results_dir']), exp_name)
    ensure_dir(exp_dir)
    save_yaml(config, os.path.join(exp_dir, 'config_snapshot.yaml'))

    workers = config['evolution'].get('parallel_workers', 1)
    print(f"[BASELINE] Experiment: {exp_name}")
    print(f"[BASELINE] Models: {', '.join(model_names)}")
    print(f"[BASELINE] Designs: {len(designs)}, Trials/design: {n_runs}")
    print(f"[BASELINE] Parallel workers: {workers}")
    print(f"[BASELINE] Results dir: {exp_dir}")

    # === Per-model loop ===
    for model_name in model_names:
        model_dir = os.path.join(exp_dir, model_name)
        ensure_dir(model_dir)

        print(f"\n[BASELINE] ===== Model: {model_name} =====")

        # all_run_results[run_id][design_idx] = result dict
        # For baseline: each "run" is one trial across all designs
        # But we run N trials per design in one pass and treat each trial as a "run"
        # To compute pass@k, we need: for each design, n=N trials, c=pass count

        # Run all designs for this model
        model_results = []  # per-design results (best candidate info)
        per_design_trials = []  # per-design trial details for pass@k

        for design_info in designs:
            print(f"\n[BASELINE] --- {design_info.name} ({n_runs} trials) ---")
            runner = BaselineRunner(design_info, model_name, config, model_dir, adapter)
            result = runner.run(n_runs)
            model_results.append(result)

            enh_str = f"{result['enhanced_score']:.3f}"
            orig_str = "PASS" if result['original_tb_pass'] else "FAIL"
            n_pass = result.get('n_pass', 0)
            print(f"[BASELINE] {design_info.name}: best_enh={enh_str}, "
                  f"orig={orig_str}, pass={n_pass}/{n_runs}")

        # === pass@k computation ===
        ks = [k for k in K_CANDIDATES if k <= n_runs]
        pass_k_rows = []
        for r in model_results:
            n = r.get('n_trials', n_runs)
            c = r.get('n_pass', 0)
            row = {
                'design': r['design'],
                'n_runs': n,
                'n_pass': c,
            }
            for k in ks:
                row[f'pass@{k}'] = round(pass_at_k(n, c, k), 4)
            row['avg_cost'] = round(r.get('cost', {}).get('total_cost', 0), 4)
            row['avg_llm_calls'] = r.get('cost', {}).get('total_calls', 0)
            pass_k_rows.append(row)

        # Global averages
        n_designs = len(pass_k_rows)
        global_avg = {}
        for k in ks:
            col = f'pass@{k}'
            avg = sum(r[col] for r in pass_k_rows) / n_designs if n_designs else 0
            global_avg[col] = round(avg, 4)

        avg_cost = sum(r['avg_cost'] for r in pass_k_rows) / n_designs if n_designs else 0
        avg_calls = sum(r['avg_llm_calls'] for r in pass_k_rows) / n_designs if n_designs else 0

        # Save pass@k JSON
        pass_k_report = {
            'model': model_name,
            'n_runs': n_runs,
            'n_designs': n_designs,
            'ks': ks,
            'global_average': global_avg,
            'avg_cost': round(avg_cost, 4),
            'avg_llm_calls': round(avg_calls, 1),
            'per_design': pass_k_rows,
        }
        with open(os.path.join(model_dir, 'pass_at_k.json'), 'w') as f:
            json.dump(pass_k_report, f, indent=2)

        # Print pass@k
        print(f"\n[BASELINE] === {model_name}: pass@k ({n_runs} trials, {n_designs} designs) ===")
        for k in ks:
            print(f"  pass@{k} = {global_avg[f'pass@{k}']:.4f}")
        print(f"  avg_cost = ${avg_cost:.4f}, avg_llm_calls = {avg_calls:.0f}")

        # Generate evaluation_report.txt for this model
        # Wrap model_results as all_run_results format: [[r1, r2, ...]] (1 "run")
        all_run_results = [model_results]
        generate_experiment_report(all_run_results, designs, 1, model_dir, config)

    # === Cross-model summary (when multiple models) ===
    if len(model_names) > 1:
        _write_cross_model_summary(exp_dir, model_names, designs, n_runs)

    print(f"\n[BASELINE] Done. Results in: {exp_dir}")


def _write_cross_model_summary(exp_dir: str, model_names: list,
                                designs: list, n_runs: int):
    """Write a cross-model comparison summary."""
    lines = []
    lines.append("=" * 100)
    lines.append("Baseline Cross-Model Comparison")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"Trials per design: {n_runs}, Designs: {len(designs)}")
    lines.append("=" * 100)
    lines.append("")

    ks = [k for k in K_CANDIDATES if k <= n_runs]
    k_cols = " ".join(f"{'pass@'+str(k):>8}" for k in ks)
    lines.append(f"{'Model':<22} {k_cols} {'Avg Cost':>10}")
    lines.append("-" * 100)

    for model_name in model_names:
        pk_path = os.path.join(exp_dir, model_name, 'pass_at_k.json')
        if not os.path.exists(pk_path):
            continue
        with open(pk_path) as f:
            pk = json.load(f)
        k_vals = " ".join(f"{pk['global_average'].get(f'pass@{k}', 0):>8.4f}" for k in ks)
        cost = pk.get('avg_cost', 0)
        lines.append(f"{model_name:<22} {k_vals} ${cost:>9.4f}")

    lines.append("-" * 100)
    lines.append("")

    summary_text = "\n".join(lines)
    output_path = os.path.join(exp_dir, "cross_model_summary.txt")
    with open(output_path, 'w') as f:
        f.write(summary_text)
    print(f"\n{summary_text}")
    print(f"[BASELINE] Cross-model summary saved to: {output_path}")


if __name__ == '__main__':
    main()
