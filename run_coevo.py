"""
Usage:
    python -m coevo.run_coevo --config coevo/config/default.yaml --dataset rtllm
    python -m coevo.run_coevo --config ... --runs 10
    python -m coevo.run_coevo --config ... --experiment_name "my_exp"
    python -m coevo.run_coevo --config ... --override llm.mutation_model=gpt-5
"""
import argparse
import os
import csv
import json
import logging
from math import comb
from datetime import datetime
from typing import List

from coevo.utils.file_io import load_yaml, save_yaml, expand_path, ensure_dir
from coevo.core.evolution import CoevoEvolution
from coevo.datasets import get_adapter, DesignInfo  # re-exported for back-compat


K_CANDIDATES = [1, 3, 5, 10, 20]


def pass_at_k(n: int, c: int, k: int) -> float:
    """Unbiased pass@k estimator (Chen et al., 2021).
    n = total runs, c = number of passing runs, k = sample size."""
    if n - c < k:
        return 1.0
    return 1.0 - comb(n - c, k) / comb(n, k)


def main():
    parser = argparse.ArgumentParser(description="COEVO: Co-evolutionary RTL Design")
    parser.add_argument('--config', required=True, help="Path to config YAML")
    parser.add_argument('--dataset', default='rtllm', choices=['rtllm', 'verilogeval'])
    parser.add_argument('--experiment_name', default='')
    parser.add_argument('--runs', type=int, default=None,
                        help="Number of independent runs (overrides config)")
    parser.add_argument('--override', action='append', default=[],
                        help="Override config values: key.subkey=value")
    args = parser.parse_args()

    # Load config
    config = load_yaml(args.config)
    models_path = os.path.join(os.path.dirname(args.config), 'models.yaml')
    models_config = load_yaml(models_path)
    config['models'] = models_config['models']

    # Apply overrides
    for override in args.override:
        apply_override(config, override)

    # Record dataset selection in config so downstream scripts (rerun_failed,
    # evaluate_experiment) can recover which adapter to use from the snapshot.
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

    # Generate experiment name: CLI > config > auto-generate
    exp_name = (args.experiment_name
                or config.get('experiment', {}).get('name', '')
                or generate_experiment_name(config, n_runs))
    exp_dir = os.path.join(expand_path(config['paths']['results_dir']), exp_name)
    ensure_dir(exp_dir)
    save_yaml(config, os.path.join(exp_dir, 'config_snapshot.yaml'))

    # Discover designs
    adapter = get_adapter(args.dataset)
    dataset_root = expand_path(
        config['paths'].get(f'{args.dataset}_root')
        or config['paths'].get('rtllm_root'))
    designs = adapter.discover_designs(dataset_root)

    print(f"[COEVO] Experiment: {exp_name}")
    print(f"[COEVO] Dataset: {args.dataset} ({dataset_root})")
    print(f"[COEVO] Found {len(designs)} designs, {n_runs} independent run(s)")

    # === Multi-run loop ===
    # all_run_results[run_id][design_idx] = result dict
    all_run_results = []

    for run_id in range(n_runs):
        if n_runs > 1:
            run_dir = os.path.join(exp_dir, f"run_{run_id}")
            print(f"\n[COEVO] ========== Run {run_id}/{n_runs} ==========")
        else:
            run_dir = exp_dir
        ensure_dir(run_dir)

        run_results = []
        for design_info in designs:
            print(f"\n[COEVO] === Processing: {design_info.name} ===")
            try:
                evo = CoevoEvolution(design_info, config, run_dir, adapter)
                result = evo.run()
                run_results.append(result)
                print(f"[COEVO] {design_info.name}: pass={result['pass']}, "
                      f"enhanced={result['enhanced_score']:.3f}, "
                      f"orig_pass={result['original_tb_pass']}")
            except Exception as e:
                print(f"[COEVO] {design_info.name}: FAILED - {e}")
                run_results.append({
                    'design': design_info.name, 'pass': False,
                    'enhanced_score': 0, 'original_tb_pass': False,
                    'best_ppa': None, 'ref_ppa': None, 'cost': {}
                })

        write_summary_csv(run_results, os.path.join(run_dir, 'summary.csv'))
        all_run_results.append(run_results)

        passed = sum(1 for r in run_results if r.get('pass'))
        print(f"\n[COEVO] Run {run_id}: {passed}/{len(run_results)} designs passed.")

    # === Aggregate pass@k ===
    ks = [k for k in K_CANDIDATES if k <= n_runs]
    write_pass_at_k_report(all_run_results, designs, ks, n_runs, exp_dir)

    # === Generate text report ===
    generate_experiment_report(all_run_results, designs, n_runs, exp_dir, config)

    print(f"\n[COEVO] Done. Results in: {exp_dir}")


def generate_experiment_name(config: dict, n_runs: int) -> str:
    abbrevs = {
        "gpt-4o-mini": "gpt4om", "gpt-4o": "gpt4o", "gpt-4.1-mini": "gpt41m",
        "gpt-5-mini": "gpt5m", "gpt-5.4-mini": "gpt54m",
        "gpt-5.1-codex-mini": "gpt51cm", "gpt-5": "gpt5", "gpt-5.1": "gpt51",
        "gpt-5.4": "gpt54", "gpt-5-codex": "gpt5c", "gpt-5.1-codex": "gpt51c",
    }
    model = abbrevs.get(config['llm']['mutation_model'], config['llm']['mutation_model'])
    dataset_abbrevs = {"rtllm": "rt", "verilogeval": "ve"}
    dataset = dataset_abbrevs.get(
        config.get('experiment', {}).get('dataset', 'rtllm'), 'unk')
    N = config['evolution']['population_size']
    G = config['evolution']['max_generations']
    R = n_runs
    sel = config['evolution']['selection']['strategy'][:4]
    sfm = config['evolution'].get('synth_failure_mode', 'keep')
    sfm_tag = "sk" if sfm == "keep" else "sz"
    ts = datetime.now().strftime("%m%d_%H%M")
    return f"{dataset}_{model}_N{N}_G{G}_R{R}_{sel}_{sfm_tag}_{ts}"


def discover_designs(dataset_root: str, dataset: str = "rtllm") -> List[DesignInfo]:
    """Find all designs in ``dataset_root``.

    Thin wrapper over the adapter's discovery for backward compatibility with
    older call sites that imported ``discover_designs`` directly from
    ``run_coevo``. New code should obtain an adapter via
    ``coevo.datasets.get_adapter`` and call ``adapter.discover_designs`` directly.
    """
    return get_adapter(dataset).discover_designs(dataset_root)


def apply_override(config: dict, override: str):
    """Apply a dotted key=value override to config dict."""
    if '=' not in override:
        return
    key_path, value = override.split('=', 1)
    keys = key_path.split('.')
    d = config
    for k in keys[:-1]:
        if k not in d:
            d[k] = {}
        d = d[k]

    # Type inference
    if value.lower() in ('true', 'false'):
        d[keys[-1]] = value.lower() == 'true'
    elif value.replace('.', '', 1).lstrip('-').isdigit():
        d[keys[-1]] = float(value) if '.' in value else int(value)
    else:
        d[keys[-1]] = value


def write_summary_csv(results: list, path: str):
    """Write per-run summary.csv."""
    if not results:
        return

    fieldnames = ['design', 'pass', 'enhanced_score', 'original_tb_pass',
                  'area', 'delay', 'power',
                  'ref_area', 'ref_delay', 'ref_power',
                  'total_calls', 'total_cost']

    with open(path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            ppa = r.get('best_ppa') or {}
            ref = r.get('ref_ppa') or {}
            cost = r.get('cost') or {}
            writer.writerow({
                'design': r['design'],
                'pass': r['pass'],
                'enhanced_score': r.get('enhanced_score', 0),
                'original_tb_pass': r.get('original_tb_pass', False),
                'area': ppa.get('area', ''),
                'delay': ppa.get('delay', ''),
                'power': ppa.get('power', ''),
                'ref_area': ref.get('area', ''),
                'ref_delay': ref.get('delay', ''),
                'ref_power': ref.get('power', ''),
                'total_calls': cost.get('total_calls', ''),
                'total_cost': cost.get('total_cost', ''),
            })


def write_pass_at_k_report(all_run_results: list, designs: list,
                           ks: list, n_runs: int, exp_dir: str):
    """Compute pass@k across independent runs and write report files."""
    rows = []
    for i, design_info in enumerate(designs):
        c = sum(1 for run in all_run_results if run[i]['pass'])
        row = {
            'design': design_info.name,
            'n_runs': n_runs,
            'n_pass': c,
        }
        for k in ks:
            row[f'pass@{k}'] = round(pass_at_k(n_runs, c, k), 4)

        # Aggregate cost/calls across runs
        costs = [run[i].get('cost', {}).get('total_cost', 0) for run in all_run_results]
        calls = [run[i].get('cost', {}).get('total_calls', 0) for run in all_run_results]
        row['avg_cost'] = round(sum(costs) / n_runs, 4) if costs else 0
        row['avg_llm_calls'] = round(sum(calls) / n_runs, 1) if calls else 0
        rows.append(row)

    # Write pass_at_k.csv
    pass_k_fields = [f'pass@{k}' for k in ks]
    fieldnames = ['design', 'n_runs', 'n_pass'] + pass_k_fields + ['avg_cost', 'avg_llm_calls']
    csv_path = os.path.join(exp_dir, 'pass_at_k.csv')
    with open(csv_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    # Compute global averages
    total_designs = len(rows)
    global_avg = {}
    for k in ks:
        col = f'pass@{k}'
        avg = sum(r[col] for r in rows) / total_designs if total_designs else 0
        global_avg[col] = round(avg, 4)

    avg_cost = sum(r['avg_cost'] for r in rows) / total_designs if total_designs else 0
    avg_calls = sum(r['avg_llm_calls'] for r in rows) / total_designs if total_designs else 0

    # Write pass_at_k.json
    report = {
        'n_runs': n_runs,
        'n_designs': total_designs,
        'ks': ks,
        'global_average': global_avg,
        'avg_cost_per_run': round(avg_cost, 4),
        'avg_llm_calls_per_run': round(avg_calls, 1),
        'per_design': rows,
    }
    json_path = os.path.join(exp_dir, 'pass_at_k.json')
    with open(json_path, 'w') as f:
        json.dump(report, f, indent=2)

    # Print summary
    print(f"\n[COEVO] === pass@k Summary ({n_runs} runs, {total_designs} designs) ===")
    for k in ks:
        print(f"  pass@{k} = {global_avg[f'pass@{k}']:.4f}")
    print(f"  avg_cost_per_run = ${avg_cost:.4f}, avg_llm_calls_per_run = {avg_calls:.0f}")


def generate_experiment_report(all_run_results: list, designs: list,
                               n_runs: int, exp_dir: str, config: dict):
    """Generate human-readable evaluation_report.txt summarizing the experiment."""
    n_designs = len(designs)
    lines = []

    # Header
    lines.append("=" * 110)
    lines.append("COEVO Experiment Evaluation Report")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"Model: {config['llm']['mutation_model']}  "
                 f"Pop: {config['evolution']['population_size']}  "
                 f"Gen: {config['evolution']['max_generations']}  "
                 f"Runs: {n_runs}")
    lines.append("=" * 110)
    lines.append("")

    # Per-design table — use best result across runs
    best_per_design = []
    for i in range(n_designs):
        candidates = [run[i] for run in all_run_results if i < len(run)]
        best = max(candidates, key=lambda r: (r.get('enhanced_score', 0), r.get('pass', False)))
        best_per_design.append(best)

    hdr = (f"{'Design':<25} {'Enh Score':>9} {'Detail':>10} {'Orig TB':>8} "
           f"{'Area':>10} {'Delay':>8} {'Power':>8} {'Cost':>8}")
    lines.append(hdr)
    lines.append("-" * 110)

    for r in best_per_design:
        p, t = r.get('passed_checks', 0), r.get('total_checks', 0)
        detail = f"{p}/{t}" if t > 0 else ""
        orig = "PASS" if r.get('original_tb_pass') else "FAIL"
        ppa = r.get('best_ppa') or {}
        area = f"{ppa['area']:.2f}" if ppa.get('area') is not None else "N/A"
        delay = f"{ppa['delay']:.2f}" if ppa.get('delay') is not None else "N/A"
        power = f"{ppa['power']:.2f}" if ppa.get('power') is not None else "N/A"
        cost = f"${r.get('cost', {}).get('total_cost', 0):.2f}"
        lines.append(
            f"{r['design']:<25} {r.get('enhanced_score', 0):>9.4f} {detail:>10} "
            f"{orig:>8} {area:>10} {delay:>8} {power:>8} {cost:>8}")

    lines.append("-" * 110)

    # Aggregates
    total = len(best_per_design)
    enh_avg = sum(r.get('enhanced_score', 0) for r in best_per_design) / total if total else 0
    enh_full = sum(1 for r in best_per_design if r.get('enhanced_score', 0) >= 1.0)
    orig_pass = sum(1 for r in best_per_design if r.get('original_tb_pass'))
    ppa_results = [r for r in best_per_design if r.get('best_ppa')]
    avg_area = sum(r['best_ppa']['area'] for r in ppa_results) / len(ppa_results) if ppa_results else 0
    avg_delay = sum(r['best_ppa']['delay'] for r in ppa_results) / len(ppa_results) if ppa_results else 0
    avg_power = sum(r['best_ppa']['power'] for r in ppa_results) / len(ppa_results) if ppa_results else 0
    total_cost = sum(r.get('cost', {}).get('total_cost', 0) for r in best_per_design)

    lines.append(f"{'AVERAGE':<25} {enh_avg:>9.4f} {'':>10} {'':>8} "
                 f"{avg_area:>10.2f} {avg_delay:>8.2f} {avg_power:>8.2f} {'':>8}")
    lines.append(f"{'PASS COUNT':<25} {'':>9} {f'{enh_full}/{total}':>10} "
                 f"{f'{orig_pass}/{total}':>8} {'':>10} {'':>8} {'':>8} "
                 f"{f'${total_cost:.2f}':>8}")
    lines.append("")

    # Pass@k section
    ks = [k for k in K_CANDIDATES if k <= n_runs]
    lines.append("=" * 110)
    lines.append("Pass@k Results (Original Testbench)")
    lines.append("=" * 110)
    lines.append("")

    if n_runs == 1:
        lines.append("Single run (n_runs=1). pass@1 = original TB pass rate.")
        lines.append("")
        lines.append(f"{'Design':<25} {'pass@1':>8}")
        lines.append("-" * 35)
        for r in best_per_design:
            p1 = 1.0 if r.get('original_tb_pass') else 0.0
            lines.append(f"{r['design']:<25} {p1:>8.4f}")
        lines.append("-" * 35)
        global_p1 = orig_pass / total if total else 0
        lines.append(f"{'GLOBAL AVERAGE':<25} {global_p1:>8.4f}")
    else:
        k_cols = " ".join(f"{'pass@'+str(k):>8}" for k in ks)
        lines.append(f"{'Design':<25} {'n_pass':>7} {k_cols}")
        lines.append("-" * (35 + 9 * len(ks)))
        global_sums = {f'pass@{k}': 0.0 for k in ks}
        for i in range(n_designs):
            name = designs[i].name
            c = sum(1 for run in all_run_results if run[i].get('pass'))
            k_vals = []
            for k in ks:
                val = pass_at_k(n_runs, c, k)
                global_sums[f'pass@{k}'] += val
                k_vals.append(f"{val:>8.4f}")
            lines.append(f"{name:<25} {c:>7} {' '.join(k_vals)}")
        lines.append("-" * (35 + 9 * len(ks)))
        avg_vals = " ".join(f"{global_sums[f'pass@{k}'] / n_designs:>8.4f}" for k in ks)
        lines.append(f"{'GLOBAL AVERAGE':<25} {'':>7} {avg_vals}")

    lines.append("")
    report_text = "\n".join(lines)

    output_path = os.path.join(exp_dir, "evaluation_report.txt")
    with open(output_path, 'w') as f:
        f.write(report_text)
    print(f"\n{report_text}")
    print(f"[COEVO] Report saved to: {output_path}")


if __name__ == '__main__':
    main()
