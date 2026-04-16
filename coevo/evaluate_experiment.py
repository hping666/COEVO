"""
Evaluate all designs in a completed experiment: test original/enhanced TBs, measure PPA.

Usage:
    python -m coevo.evaluate_experiment --experiment gpt5m_N10_G10_R1_prop_sk_0408_0519
    python -m coevo.evaluate_experiment --experiment gpt4om_N10_G10_R1_prop_0404_0506 --skip-ppa
"""
import argparse
import json
import os
import sys
from datetime import datetime
from math import comb

from coevo.utils.file_io import load_yaml, expand_path
from coevo.evaluation.correctness import CorrectnessEvaluator
from coevo.evaluation.ppa import PPAEvaluator
from coevo.datasets import get_adapter
from coevo.run_coevo import (
    K_CANDIDATES, write_summary_csv, write_pass_at_k_report
)


def pass_at_k(n: int, c: int, k: int) -> float:
    """Unbiased pass@k estimator (Chen et al., 2021)."""
    if n - c < k:
        return 1.0
    return 1.0 - comb(n - c, k) / comb(n, k)


def evaluate_design(design, code: str, module_name: str,
                    corr_eval: CorrectnessEvaluator, ppa_eval: PPAEvaluator,
                    skip_ppa: bool) -> dict:
    """Evaluate a single design against both TBs and PPA. ``design`` is a DesignInfo."""
    result = {'design': design.name}

    # Enhanced testbench (continuous score)
    enh = corr_eval.evaluate(code, design, module_name)
    result['enh_score'] = enh['score']
    result['enh_passed'] = enh['passed']
    result['enh_total'] = enh['total']

    # Original testbench (binary)
    result['orig_pass'] = corr_eval.evaluate_original_tb(code, design, module_name)

    # PPA
    if skip_ppa:
        result['area'] = None
        result['delay'] = None
        result['power'] = None
    else:
        ppa, _ = ppa_eval.evaluate(code, module_name, design.name)
        if ppa:
            result['area'] = ppa.area
            result['delay'] = ppa.delay
            result['power'] = ppa.power
        else:
            result['area'] = None
            result['delay'] = None
            result['power'] = None

    return result


def update_summary_json(design_result_dir: str, eval_result: dict, skip_ppa: bool):
    """Update a design's summary.json with fresh evaluation results.
    Preserves cost, ref_ppa, pareto_count from the original."""
    summary_path = os.path.join(design_result_dir, "summary.json")
    # Read existing summary to preserve cost/ref_ppa
    old = {}
    if os.path.isfile(summary_path):
        with open(summary_path) as f:
            old = json.load(f)

    # Update with fresh results
    old['enhanced_score'] = eval_result['enh_score']
    old['original_tb_pass'] = eval_result['orig_pass']
    old['pass'] = eval_result['orig_pass']

    if not skip_ppa:
        if eval_result['area'] is not None:
            old['best_ppa'] = {
                'area': eval_result['area'],
                'delay': eval_result['delay'],
                'power': eval_result['power'],
            }
        else:
            old['best_ppa'] = None

    with open(summary_path, 'w') as f:
        json.dump(old, f, indent=2)


def regenerate_aggregate_files(eval_run_dir: str, exp_dir: str, config: dict,
                               is_multi_run: bool, n_runs: int):
    """Regenerate summary.csv, pass_at_k.csv, pass_at_k.json from summary.json files."""
    all_results = []
    for name in sorted(os.listdir(eval_run_dir)):
        summary_path = os.path.join(eval_run_dir, name, "summary.json")
        if os.path.isfile(summary_path):
            with open(summary_path) as f:
                all_results.append(json.load(f))

    if not all_results:
        return

    # summary.csv
    csv_path = os.path.join(eval_run_dir, "summary.csv")
    write_summary_csv(all_results, csv_path)

    # pass_at_k — write to experiment root
    ks = [k for k in K_CANDIDATES if k <= n_runs]
    designs = [type('D', (), {'name': r['design']})() for r in all_results]
    write_pass_at_k_report([all_results], designs, ks, n_runs, exp_dir)

    total = len(all_results)
    passed = sum(1 for r in all_results if r.get("pass"))
    print(f"[EVAL] Regenerated summary.csv, pass_at_k.csv, pass_at_k.json")
    print(f"[EVAL] Overall: {passed}/{total} designs passed.")


def format_table(results: list, pass_k_info: dict) -> str:
    """Format results as a text table."""
    lines = []

    # Header
    lines.append("=" * 110)
    lines.append("COEVO Experiment Evaluation Report")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("=" * 110)
    lines.append("")

    # Per-design table
    hdr = f"{'Design':<28} {'Enh Score':>10} {'Enh Detail':>12} {'Orig TB':>8} {'Area':>10} {'Delay':>8} {'Power':>8}"
    lines.append(hdr)
    lines.append("-" * 110)

    for r in results:
        enh_detail = f"{r['enh_passed']}/{r['enh_total']}" if r['enh_total'] else "N/A"
        orig_tag = "PASS" if r['orig_pass'] else "FAIL"
        area = f"{r['area']:.2f}" if r['area'] is not None else "N/A"
        delay = f"{r['delay']:.2f}" if r['delay'] is not None else "N/A"
        power = f"{r['power']:.2f}" if r['power'] is not None else "N/A"
        lines.append(
            f"{r['design']:<28} {r['enh_score']:>10.4f} {enh_detail:>12} {orig_tag:>8} {area:>10} {delay:>8} {power:>8}"
        )

    lines.append("-" * 110)

    # Aggregates
    total = len(results)
    enh_avg = sum(r['enh_score'] for r in results) / total if total else 0
    enh_full = sum(1 for r in results if r['enh_score'] >= 1.0)
    orig_pass = sum(1 for r in results if r['orig_pass'])
    ppa_results = [r for r in results if r['area'] is not None]
    avg_area = sum(r['area'] for r in ppa_results) / len(ppa_results) if ppa_results else 0
    avg_delay = sum(r['delay'] for r in ppa_results) / len(ppa_results) if ppa_results else 0
    avg_power = sum(r['power'] for r in ppa_results) / len(ppa_results) if ppa_results else 0

    lines.append(
        f"{'AVERAGE':<28} {enh_avg:>10.4f} {'':<12} {'':<8} "
        f"{avg_area:>10.2f} {avg_delay:>8.2f} {avg_power:>8.2f}"
    )
    lines.append(
        f"{'PASS COUNT':<28} {'':<10} {f'{enh_full}/{total}':>12} {f'{orig_pass}/{total}':>8}"
    )
    lines.append("")

    # Pass@k section
    lines.append("=" * 110)
    lines.append("Pass@k Results (Original Testbench)")
    lines.append("=" * 110)
    lines.append("")

    n_runs = pass_k_info['n_runs']
    ks = pass_k_info['ks']

    if n_runs == 1:
        lines.append(f"Single-run experiment (n_runs=1). Pass@1 = original TB pass rate.")
        lines.append("")
        hdr = f"{'Design':<28} {'n_pass':>7} {'pass@1':>8}"
        lines.append(hdr)
        lines.append("-" * 50)
        for r in results:
            c = 1 if r['orig_pass'] else 0
            p1 = pass_at_k(1, c, 1)
            lines.append(f"{r['design']:<28} {c:>7} {p1:>8.4f}")
        lines.append("-" * 50)
        global_p1 = orig_pass / total if total else 0
        lines.append(f"{'GLOBAL AVERAGE':<28} {'':<7} {global_p1:>8.4f}")
    else:
        # Multi-run: use per-design pass counts from pass_k_info
        k_cols = " ".join(f"{'pass@'+str(k):>8}" for k in ks)
        hdr = f"{'Design':<28} {'n_pass':>7} {k_cols}"
        lines.append(hdr)
        lines.append("-" * (40 + 9 * len(ks)))
        for entry in pass_k_info['per_design']:
            k_vals = " ".join(f"{entry[f'pass@{k}']:>8.4f}" for k in ks)
            lines.append(f"{entry['design']:<28} {entry['n_pass']:>7} {k_vals}")
        lines.append("-" * (40 + 9 * len(ks)))
        avg_vals = " ".join(f"{pass_k_info['global_avg'][f'pass@{k}']:>8.4f}" for k in ks)
        lines.append(f"{'GLOBAL AVERAGE':<28} {'':<7} {avg_vals}")

    lines.append("")
    return "\n".join(lines)


def collect_multi_run_pass_k(exp_dir: str, design_map: dict, n_runs: int) -> dict:
    """Collect pass@k data across multiple run directories."""
    ks = [k for k in K_CANDIDATES if k <= n_runs]
    per_design = []
    for name in sorted(design_map):
        c = 0
        for run_id in range(n_runs):
            run_dir = os.path.join(exp_dir, f"run_{run_id}")
            summary_path = os.path.join(run_dir, name, "summary.json")
            if os.path.isfile(summary_path):
                with open(summary_path) as f:
                    s = json.load(f)
                if s.get("original_tb_pass", False):
                    c += 1
        entry = {'design': name, 'n_pass': c}
        for k in ks:
            entry[f'pass@{k}'] = round(pass_at_k(n_runs, c, k), 4)
        per_design.append(entry)

    n_designs = len(per_design)
    global_avg = {}
    for k in ks:
        col = f'pass@{k}'
        global_avg[col] = round(sum(e[col] for e in per_design) / n_designs, 4) if n_designs else 0

    return {'n_runs': n_runs, 'ks': ks, 'per_design': per_design, 'global_avg': global_avg}


def main():
    parser = argparse.ArgumentParser(description="Evaluate a completed COEVO experiment")
    parser.add_argument("--experiment", required=True, help="Experiment directory name")
    parser.add_argument("--skip-ppa", action="store_true", help="Skip PPA evaluation")
    args = parser.parse_args()

    results_root = expand_path("~/MAS4RTL/coevo/results")
    exp_dir = os.path.join(results_root, args.experiment)
    config_path = os.path.join(exp_dir, "config_snapshot.yaml")
    if not os.path.exists(config_path):
        print(f"[EVAL] Config not found: {config_path}")
        sys.exit(1)

    config = load_yaml(config_path)
    n_runs = max(1, config.get("experiment", {}).get("runs", 1))

    # Recover dataset selection from snapshot (default rtllm for old experiments)
    dataset_name = config.get("experiment", {}).get("dataset", "rtllm")
    adapter = get_adapter(dataset_name)
    dataset_root = expand_path(
        config["paths"].get(f"{dataset_name}_root")
        or config["paths"].get("rtllm_root"))
    all_designs = {d.name: d for d in adapter.discover_designs(dataset_root)}

    # Determine which designs are in this experiment
    is_multi_run = n_runs > 1 and os.path.isdir(os.path.join(exp_dir, "run_0"))

    if is_multi_run:
        # Use run_0 as the representative run for evaluation
        eval_run_dir = os.path.join(exp_dir, "run_0")
    else:
        eval_run_dir = exp_dir

    # Collect design subdirs that have summary.json
    design_names = []
    incomplete = []
    for name in sorted(os.listdir(eval_run_dir)):
        subdir = os.path.join(eval_run_dir, name)
        if not os.path.isdir(subdir):
            continue
        if os.path.isfile(os.path.join(subdir, "summary.json")):
            design_names.append(name)
        else:
            incomplete.append(name)

    if incomplete:
        print(f"[EVAL] WARNING: {len(incomplete)} designs incomplete: {', '.join(incomplete)}")
    if not design_names:
        print("[EVAL] No completed designs found.")
        sys.exit(1)

    print(f"[EVAL] Experiment: {args.experiment}")
    print(f"[EVAL] Designs: {len(design_names)}, Runs: {n_runs}")
    print(f"[EVAL] Evaluating (skip_ppa={args.skip_ppa})...\n")

    # Initialize evaluators with experiment config
    corr_eval = CorrectnessEvaluator(config, adapter)
    # Force enhanced TB on for evaluation
    corr_eval.use_enhanced = True
    ppa_eval = PPAEvaluator(config, adapter)

    results = []
    for i, name in enumerate(design_names):
        design_info = all_designs.get(name)
        if design_info is None:
            print(f"  [{i+1}/{len(design_names)}] {name}: design not found in {dataset_name}, skipping")
            continue

        best_code_path = os.path.join(eval_run_dir, name, "best_correct.v")
        if not os.path.isfile(best_code_path):
            print(f"  [{i+1}/{len(design_names)}] {name}: no best_correct.v, skipping")
            results.append({
                'design': name, 'enh_score': 0, 'enh_passed': 0, 'enh_total': 0,
                'orig_pass': False, 'area': None, 'delay': None, 'power': None,
            })
            continue

        with open(best_code_path) as f:
            code = f.read()

        module_name = adapter.extract_module_name(design_info)
        print(f"  [{i+1}/{len(design_names)}] {name} ... ", end="", flush=True)

        r = evaluate_design(design_info, code, module_name,
                            corr_eval, ppa_eval, args.skip_ppa)
        results.append(r)

        # Update this design's summary.json with fresh results
        update_summary_json(os.path.join(eval_run_dir, name), r, args.skip_ppa)

        enh_tag = f"{r['enh_score']:.2f}"
        orig_tag = "PASS" if r['orig_pass'] else "FAIL"
        ppa_tag = f"area={r['area']:.1f}" if r['area'] is not None else "N/A"
        print(f"enh={enh_tag}  orig={orig_tag}  {ppa_tag}")

    # Pass@k
    if is_multi_run:
        pass_k_info = collect_multi_run_pass_k(exp_dir, {n: all_designs[n] for n in design_names if n in all_designs}, n_runs)
    else:
        # Single-run: pass@k is just the per-design original TB result
        per_design = []
        for r in results:
            c = 1 if r['orig_pass'] else 0
            entry = {'design': r['design'], 'n_pass': c}
            entry['pass@1'] = round(pass_at_k(1, c, 1), 4)
            per_design.append(entry)
        n_designs = len(per_design)
        global_avg = {
            'pass@1': round(sum(e['pass@1'] for e in per_design) / n_designs, 4) if n_designs else 0
        }
        pass_k_info = {'n_runs': 1, 'ks': [1], 'per_design': per_design, 'global_avg': global_avg}

    # Format and write report
    report = format_table(results, pass_k_info)

    output_path = os.path.join(exp_dir, "evaluation_report.txt")
    with open(output_path, 'w') as f:
        f.write(report)

    print(f"\n{report}")
    print(f"\n[EVAL] Report saved to: {output_path}")

    # Regenerate experiment-level aggregate files from updated summary.json
    if not incomplete:
        regenerate_aggregate_files(eval_run_dir, exp_dir, config, is_multi_run, n_runs)
    else:
        print(f"[EVAL] Skipping aggregate file generation ({len(incomplete)} designs incomplete)")


if __name__ == "__main__":
    main()
