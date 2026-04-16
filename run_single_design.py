"""
Usage:
    python -m coevo.run_single_design --design accu --config coevo/config/default.yaml
    python -m coevo.run_single_design --design accu --config ... --runs 10
"""
import argparse
import os
import json
import logging

from coevo.utils.file_io import load_yaml, save_yaml, expand_path, ensure_dir
from coevo.core.evolution import CoevoEvolution
from coevo.datasets import get_adapter
from coevo.run_coevo import (
    apply_override, pass_at_k, K_CANDIDATES, generate_experiment_report
)


def main():
    parser = argparse.ArgumentParser(description="COEVO: Run single design")
    parser.add_argument('--design', required=True, help="Design name (e.g., accu)")
    parser.add_argument('--config', required=True, help="Path to config YAML")
    parser.add_argument('--dataset', default='rtllm', choices=['rtllm', 'verilogeval'])
    parser.add_argument('--experiment_name', default='debug')
    parser.add_argument('--runs', type=int, default=None,
                        help="Number of independent runs (overrides config)")
    parser.add_argument('--override', action='append', default=[])
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

    # Setup logging
    logging.basicConfig(
        level=getattr(logging, config.get('logging', {}).get('level', 'INFO')),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s"
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)

    # Find design directory
    adapter = get_adapter(args.dataset)
    dataset_root = expand_path(
        config['paths'].get(f'{args.dataset}_root')
        or config['paths'].get('rtllm_root'))
    designs = adapter.discover_designs(dataset_root)
    design_info = None
    for d in designs:
        if d.name == args.design:
            design_info = d
            break

    if design_info is None:
        print(f"[ERROR] Design '{args.design}' not found in {dataset_root}")
        print(f"Available: {[d.name for d in designs]}")
        return

    # Setup experiment dir
    exp_dir = os.path.join(expand_path(config['paths']['results_dir']), args.experiment_name)
    ensure_dir(exp_dir)
    save_yaml(config, os.path.join(exp_dir, 'config_snapshot.yaml'))

    print(f"[COEVO] Design: {design_info.name}")
    print(f"[COEVO] Design dir: {design_info.dir}")
    print(f"[COEVO] Results dir: {exp_dir}")
    print(f"[COEVO] Independent runs: {n_runs}")

    # === Multi-run loop ===
    results = []
    for run_id in range(n_runs):
        if n_runs > 1:
            run_dir = os.path.join(exp_dir, f"run_{run_id}")
            print(f"\n[COEVO] ========== Run {run_id}/{n_runs} ==========")
        else:
            run_dir = exp_dir
        ensure_dir(run_dir)

        evo = CoevoEvolution(design_info, config, run_dir, adapter)
        result = evo.run()
        results.append(result)

        print(f"\n[COEVO] Run {run_id} result:")
        print(json.dumps(result, indent=2))

    # === Aggregate pass@k ===
    n = len(results)
    c = sum(1 for r in results if r['pass'])
    ks = [k for k in K_CANDIDATES if k <= n]

    avg_cost = sum(r.get('cost', {}).get('total_cost', 0) for r in results) / n
    avg_calls = sum(r.get('cost', {}).get('total_calls', 0) for r in results) / n

    print(f"\n[COEVO] === {design_info.name}: {c}/{n} runs passed ===")
    pass_k_results = {}
    for k in ks:
        val = pass_at_k(n, c, k)
        pass_k_results[f'pass@{k}'] = round(val, 4)
        print(f"  pass@{k} = {val:.4f}")
    print(f"  avg_cost = ${avg_cost:.4f}, avg_llm_calls = {avg_calls:.0f}")

    # Save aggregated report (only when n_runs > 1)
    if n_runs > 1:
        report = {
            'design': design_info.name,
            'n_runs': n,
            'n_pass': c,
            'pass_at_k': pass_k_results,
            'avg_cost': round(avg_cost, 4),
            'avg_llm_calls': round(avg_calls, 1),
            'per_run': [
                {
                    'run_id': i,
                    'pass': r['pass'],
                    'enhanced_score': r.get('enhanced_score', 0),
                    'original_tb_pass': r.get('original_tb_pass', False),
                    'total_cost': r.get('cost', {}).get('total_cost', 0),
                    'total_calls': r.get('cost', {}).get('total_calls', 0),
                }
                for i, r in enumerate(results)
            ],
        }
        report_path = os.path.join(exp_dir, 'pass_at_k.json')
        with open(report_path, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"\n[COEVO] Report saved to: {report_path}")

    # Generate text report
    all_run_results = [[r] for r in results]  # Wrap: each run has one design
    generate_experiment_report(all_run_results, [design_info], n_runs, exp_dir, config)


if __name__ == '__main__':
    main()
