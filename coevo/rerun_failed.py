"""
Rerun only failed designs from an existing experiment, overwriting their results.

Usage:
    python -m coevo.rerun_failed
    python -m coevo.rerun_failed --experiment gpt4om_N10_G10_R1_prop_0404_0506

    # Rerun only specific designs (bypasses auto-detection of failures)
    python -m coevo.rerun_failed --experiment <name> \
        --only Prob068_countbcd,Prob141_count_clock

    # Override config values in memory for the rerun (does NOT modify the
    # on-disk config_snapshot.yaml in the experiment directory)
    python -m coevo.rerun_failed --experiment <name> \
        --only Prob155_lemmings4,Prob156_review2015_fancytimer \
        --override evolution.max_generations=20
"""
import argparse
import json
import logging
import os
import shutil

from coevo.utils.file_io import load_yaml, expand_path, ensure_dir
from coevo.core.evolution import CoevoEvolution
from coevo.datasets import get_adapter
from coevo.run_coevo import (
    apply_override,
    write_summary_csv,
    write_pass_at_k_report,
    generate_experiment_report,
    K_CANDIDATES,
)


DEFAULT_EXPERIMENT = "ve_gpt4om_N10_G10_R1_prop_sk_0410_0908"


def find_failed_designs(exp_dir: str, fail_mode: str = "any") -> list:
    """Scan experiment dir, return list of design names that failed.
    fail_mode:
        "any"      - failed if enhanced_score < 1.0 OR original_tb_pass is False
        "original" - failed only if original_tb_pass is False
    """
    failed = []
    for name in sorted(os.listdir(exp_dir)):
        summary_path = os.path.join(exp_dir, name, "summary.json")
        if not os.path.isfile(summary_path):
            continue
        with open(summary_path) as f:
            s = json.load(f)
        if fail_mode == "original":
            is_failed = not s.get("original_tb_pass", False)
        else:
            is_failed = s.get("enhanced_score", 0) < 1.0 or not s.get("original_tb_pass", False)
        if is_failed:
            failed.append(name)
    return failed


def regenerate_full_output(exp_dir: str, design_map: dict, config: dict):
    """If all designs in exp_dir have summary.json, regenerate summary.csv and pass@k
    to match normal coevo output, overwriting old results."""
    all_results = []
    missing = []
    # Iterate actual experiment subdirectories, not the full RTLLM design_map
    for name in sorted(os.listdir(exp_dir)):
        subdir = os.path.join(exp_dir, name)
        if not os.path.isdir(subdir):
            continue
        summary_path = os.path.join(subdir, "summary.json")
        if not os.path.isfile(summary_path):
            missing.append(name)
            continue
        with open(summary_path) as f:
            all_results.append(json.load(f))

    if missing:
        print(f"\n[RERUN] {len(missing)} designs still incomplete, skipping full regeneration.")
        return

    if not all_results:
        print(f"\n[RERUN] No design results found in experiment directory.")
        return

    # All designs complete — overwrite summary.csv
    write_summary_csv(all_results, os.path.join(exp_dir, "summary.csv"))

    # Regenerate pass@k report
    n_runs = max(1, config.get("experiment", {}).get("runs", 1))
    ks = [k for k in K_CANDIDATES if k <= n_runs]
    designs = [type('D', (), {'name': r['design']})() for r in all_results]
    write_pass_at_k_report([all_results], designs, ks, n_runs, exp_dir)

    # Regenerate human-readable evaluation_report.txt so it reflects the
    # post-rerun state. `config` here is the in-memory dict that may have
    # been mutated by apply_override, so the header Gen/Pop line will show
    # the effective overridden config used for this rerun.
    generate_experiment_report([all_results], designs, n_runs, exp_dir, config)

    total = len(all_results)
    passed = sum(1 for r in all_results if r.get("pass"))
    print(f"\n[RERUN] All {total} designs complete. Regenerated summary.csv, pass_at_k, and evaluation_report.")
    print(f"[RERUN] Overall: {passed}/{total} designs passed.")


def main():
    parser = argparse.ArgumentParser(description="Rerun failed designs in an existing experiment")
    parser.add_argument("--experiment", default=DEFAULT_EXPERIMENT,
                        help=f"Experiment directory name (default: {DEFAULT_EXPERIMENT})")
    parser.add_argument("--fail-mode", default="original", choices=["any", "original"],
                        help="Failure criteria: 'any' = enhanced or original failed; "
                             "'original' = only original TB failed (default: original). "
                             "Ignored when --only is given.")
    parser.add_argument("--only", default="",
                        help="Comma-separated list of design names to rerun. "
                             "When provided, --fail-mode auto-detection is "
                             "bypassed and ONLY the listed designs are rerun. "
                             "Unknown names abort the run before any work.")
    parser.add_argument("--override", action="append", default=[],
                        help="In-memory config override of the form "
                             "dotted.key=value (can be repeated). The on-disk "
                             "config_snapshot.yaml is NOT modified; overrides "
                             "only affect the current rerun process.")
    args = parser.parse_args()

    # Load config from experiment snapshot
    results_root = expand_path("~/MAS4RTL/coevo/results")
    exp_dir = os.path.join(results_root, args.experiment)
    config_path = os.path.join(exp_dir, "config_snapshot.yaml")
    if not os.path.exists(config_path):
        print(f"[RERUN] Config not found: {config_path}")
        return

    config = load_yaml(config_path)

    # Apply in-memory overrides BEFORE launching evolution. By design this
    # mutates only the local dict — `save_yaml` is never called here, so the
    # experiment's on-disk config_snapshot.yaml remains untouched.
    if args.override:
        print(f"[RERUN] Applying {len(args.override)} in-memory override(s) "
              f"(config_snapshot.yaml on disk will NOT be modified):")
        for ov in args.override:
            apply_override(config, ov)
            print(f"  - {ov}")
        # Echo a few commonly-overridden effective values so the user can
        # visually confirm the override landed.
        evo = config.get("evolution", {}) or {}
        print(f"[RERUN] Effective evolution config after overrides: "
              f"population_size={evo.get('population_size')} "
              f"offspring_count={evo.get('offspring_count')} "
              f"max_generations={evo.get('max_generations')} "
              f"repair_attempts={evo.get('repair_attempts')}")

    logging.basicConfig(
        level=getattr(logging, config.get("logging", {}).get("level", "INFO")),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)

    # Recover dataset selection from snapshot (default rtllm for old experiments)
    dataset_name = config.get("experiment", {}).get("dataset", "rtllm")
    adapter = get_adapter(dataset_name)
    dataset_root = expand_path(
        config["paths"].get(f"{dataset_name}_root")
        or config["paths"].get("rtllm_root"))
    all_designs = adapter.discover_designs(dataset_root)
    design_map = {d.name: d for d in all_designs}

    # Build the list of designs to rerun. --only takes precedence over
    # fail-mode auto-detection; names are validated against design_map so a
    # typo fails fast before we start clearing any directories.
    if args.only.strip():
        requested = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in requested if n not in design_map]
        if unknown:
            print(f"[RERUN] Unknown design name(s) in --only: {unknown}")
            print(f"[RERUN] Aborting — no directories have been modified.")
            return
        failed = requested
        print(f"[RERUN] Experiment: {args.experiment}")
        print(f"[RERUN] --only mode: {len(failed)} design(s) (fail-mode scan skipped)")
        for name in failed:
            print(f"  - {name}")
    else:
        failed = find_failed_designs(exp_dir, args.fail_mode)
        print(f"[RERUN] Experiment: {args.experiment}")
        print(f"[RERUN] Failed designs: {len(failed)}/{len(design_map)}")
        for name in failed:
            print(f"  - {name}")

    if not failed:
        print("[RERUN] Nothing to rerun.")
        return

    # Rerun each failed design
    results = []
    for name in failed:
        design_info = design_map.get(name)
        if design_info is None:
            print(f"[RERUN] {name}: design not found in {dataset_name}, skipping")
            continue

        # Clean old results for this design
        old_dir = os.path.join(exp_dir, name)
        if os.path.isdir(old_dir):
            shutil.rmtree(old_dir)

        print(f"\n[RERUN] === Rerunning: {name} ===")
        try:
            evo = CoevoEvolution(design_info, config, exp_dir, adapter)
            result = evo.run()
            results.append(result)
            print(f"[RERUN] {name}: pass={result['pass']}, "
                  f"enhanced={result['enhanced_score']:.3f}, "
                  f"orig_pass={result['original_tb_pass']}")
        except Exception as e:
            print(f"[RERUN] {name}: FAILED - {e}")
            results.append({
                "design": name, "pass": False,
                "enhanced_score": 0, "original_tb_pass": False,
                "best_ppa": None, "ref_ppa": None, "cost": {},
            })

    # Write rerun summary
    rerun_csv = os.path.join(exp_dir, "rerun_summary.csv")
    write_summary_csv(results, rerun_csv)

    passed = sum(1 for r in results if r.get("pass"))
    print(f"\n[RERUN] Done. {passed}/{len(results)} rerun designs passed.")
    print(f"[RERUN] Rerun summary: {rerun_csv}")

    # Check if all designs are complete; if so, regenerate full experiment output
    regenerate_full_output(exp_dir, design_map, config)


if __name__ == "__main__":
    main()
