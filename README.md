# COEVO: Co-Evolutionary RTL Design with LLMs

A co-evolutionary framework that uses Large Language Models (LLMs) to generate synthesizable Verilog/SystemVerilog RTL code with joint optimization of **functional correctness** and **PPA** (Power, Performance, Area).

COEVO evolves a population of hardware designs through LLM-driven mutation operators, evaluated by simulation ([Icarus Verilog](https://github.com/steveicarus/iverilog)) and synthesis ([Yosys](https://github.com/YosysHQ/yosys) + [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA)), using Pareto-based selection to balance correctness and PPA trade-offs.

## Key Features

- **Co-evolutionary optimization** &mdash; jointly optimizes functional correctness and PPA instead of treating them as separate objectives
- **7 LLM-driven operators** &mdash; Fix, Simplify, Optimize, Restructure, Explore, PPA-Aware Fix, Architecture Fusion
- **UCB-Softmax adaptive selection** &mdash; dynamically allocates operator usage based on observed rewards
- **Pareto-based survivor selection** &mdash; NSGA-II style non-dominated sorting on 4 objectives (correctness, area, delay, power)
- **Unified repair mechanism** &mdash; combines functional error feedback and synthesis failure diagnosis into a single repair prompt
- **Multi-dataset support** &mdash; dataset-agnostic core with adapters for [RTLLM](https://github.com/hkust-zhiyao/RTLLM) (50 designs) and VerilogEval (156 designs)
- **Multi-run pass@k evaluation** &mdash; unbiased pass@k estimator across independent runs
- **Parallel execution** &mdash; configurable parallel offspring generation via `ThreadPoolExecutor`

## Architecture

```
                        +------------------+
                        |   run_coevo.py   |    Entry point
                        +--------+---------+
                                 |
                    +------------v-----------+
                    |   CoevoEvolution       |    Orchestrator
                    |   (core/evolution.py)  |
                    +---+------+------+------+
                        |      |      |
           +------------+   +--+--+   +-------------+
           |                |     |                  |
    +------v------+  +-----v-+  +v--------+  +------v-------+
    | Population  |  | LLM   |  |Operators|  | Evaluator    |
    | (Pareto     |  |Client |  |Selector |  | (fitness.py) |
    |  selection) |  +-------+  |(UCB)    |  +---+------+---+
    +-------------+             +---------+      |      |
                                          +------v-+ +--v----------+
                                          |Correct-| |PPA Evaluator|
                                          |ness    | |(Yosys +     |
                                          |Eval    | | OpenSTA)    |
                                          +--------+ +-------------+
```

### Evolution Pipeline

1. **Initialization** &mdash; generate diverse population via multiple architecture strategies (behavioral, structural, pipeline, resource-shared, FSM-minimized), optionally auto-selected by LLM
2. **Evolution Loop** &mdash; for each generation:
   - Select operator via UCB-Softmax bandit
   - Generate offspring through LLM mutation
   - Evaluate correctness (iverilog simulation) + PPA (Yosys + OpenSTA)
   - Unified repair for synthesis failures and functional errors
   - Pareto-based survivor selection with adaptive correctness gate
3. **Results** &mdash; re-evaluate best individual with original testbench; save best designs per PPA metric

## Repository Structure

```
MAS4RTL/
├── coevo/                              # Framework source code
│   ├── run_coevo.py                    # Main entry point (all designs)
│   ├── run_single_design.py            # Single design entry point
│   ├── benchmark_models.py             # Baseline: N independent LLM generations
│   ├── rerun_failed.py                 # Rerun failed designs from existing experiment
│   ├── evaluate_experiment.py          # Re-evaluate completed experiments
│   │
│   ├── config/
│   │   ├── default.yaml                # Hyperparameters, paths, evaluation settings
│   │   └── models.yaml                 # LLM model definitions and API keys
│   │
│   ├── core/
│   │   ├── evolution.py                # CoevoEvolution: main loop orchestrator
│   │   ├── individual.py               # Individual & PPAMetrics dataclasses
│   │   ├── population.py               # Population management + Pareto sorting
│   │   ├── fitness.py                  # Unified evaluator (correctness + PPA)
│   │   └── strategy_memory.py          # Per-design strategy memory
│   │
│   ├── llm/
│   │   ├── api_client.py               # LLMClient (standard / GPT-5 / Codex APIs)
│   │   ├── response_parser.py          # Extract thought + Verilog from LLM output
│   │   └── prompt_templates.py         # System messages + operator prompt builders
│   │
│   ├── operators/
│   │   ├── base.py                     # BaseOperator ABC
│   │   ├── initialization.py           # Multi-strategy initial generation
│   │   ├── correctness_ops.py          # Fix, Simplify
│   │   ├── ppa_ops.py                  # Optimize, Restructure, Explore
│   │   ├── cross_ops.py                # PPA-Aware Fix, Architecture Fusion
│   │   └── selector.py                 # UCB-Softmax adaptive selection
│   │
│   ├── evaluation/
│   │   ├── correctness.py              # iverilog simulation + FORGE output parsing
│   │   ├── ppa.py                      # Yosys synthesis + OpenSTA timing/power
│   │   └── synthesis_parser.py         # Yosys/OpenSTA log parsers + clock detection
│   │
│   ├── datasets/
│   │   ├── base.py                     # DatasetAdapter ABC + DesignInfo
│   │   ├── rtllm.py                    # RTLLM adapter (nested dir layout)
│   │   └── verilogeval.py              # VerilogEval adapter (flat file layout)
│   │
│   ├── utils/
│   │   ├── timeout.py                  # Subprocess timeout with process group kill
│   │   ├── file_io.py                  # YAML/text I/O utilities
│   │   └── logger.py                   # EvolutionLogger
│   │
│   └── results/                        # Experiment outputs (auto-created)
│
├── RTLLM/                              # RTLLM benchmark dataset (read-only)
│   └── <category>/<subcategory>/<design>/
│       ├── design_description.txt
│       ├── testbench.v
│       ├── testbench_enhanced.v
│       └── verified_*.v
│
└── VerilogEval/                        # VerilogEval benchmark dataset (read-only)
    ├── problems.txt
    ├── <design>_prompt.txt
    ├── <design>_ref.sv
    ├── <design>_test.sv
    └── <design>_test_enhanced.sv
```

## Prerequisites

### Software Dependencies

| Tool | Purpose | Version Tested |
|------|---------|----------------|
| Python | Runtime | 3.11 |
| [Icarus Verilog](https://github.com/steveicarus/iverilog) | RTL simulation | 12.0 |
| [Yosys](https://github.com/YosysHQ/yosys) | Logic synthesis | 0.63 |
| [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA) | Timing & power analysis | via OpenROAD |
| [NanGate45 Liberty](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) | Standard cell library | NangateOpenCellLibrary |

### Python Packages

```bash
pip install openai pyyaml numpy
```

### Environment Setup

```bash
# Activate the conda environment with all EDA tools available
conda activate PPA

# Set OpenAI API key (if not hardcoded in models.yaml)
export OPENAI_API_KEY="your-api-key"
```

## Usage

All commands should be run from the repository root (`MAS4RTL/`).

### Run Full Experiment (All Designs)

```bash
# RTLLM dataset (50 designs)
python -m coevo.run_coevo --config coevo/config/default.yaml --dataset rtllm

# VerilogEval dataset (156 designs)
python -m coevo.run_coevo --config coevo/config/default.yaml --dataset verilogeval
```

### Run Single Design

```bash
# RTLLM
python -m coevo.run_single_design --design accu --dataset rtllm \
    --config coevo/config/default.yaml

# VerilogEval
python -m coevo.run_single_design --design Prob137_fsm_serial --dataset verilogeval \
    --config coevo/config/default.yaml
```

### Multi-Run with pass@k

```bash
# 10 independent runs for pass@k evaluation
python -m coevo.run_coevo --config coevo/config/default.yaml --dataset rtllm --runs 10

python -m coevo.run_single_design --design accu --dataset rtllm \
    --config coevo/config/default.yaml --runs 5
```

### Config Overrides

Override any config value from the command line without editing YAML files:

```bash
python -m coevo.run_coevo --config coevo/config/default.yaml --dataset rtllm \
    --override llm.mutation_model=gpt-5-mini \
    --override evolution.max_generations=20 \
    --override evolution.population_size=15
```

### Baseline Comparison

Run N independent single-shot LLM generations (no evolution) for baseline pass@k:

```bash
python -m coevo.benchmark_models --config coevo/config/default.yaml \
    --dataset verilogeval --runs 10 --model gpt-4o-mini
```

### Rerun Failed Designs

```bash
# Rerun all failed designs in an existing experiment
python -m coevo.rerun_failed --experiment <experiment_name>

# Rerun specific designs with config overrides
python -m coevo.rerun_failed --experiment <experiment_name> \
    --only Prob068_countbcd,Prob141_count_clock \
    --override evolution.max_generations=20
```

### Re-evaluate Experiment

```bash
python -m coevo.evaluate_experiment --experiment <experiment_name>
python -m coevo.evaluate_experiment --experiment <experiment_name> --skip-ppa
```

## Configuration

The main config file (`coevo/config/default.yaml`) controls all aspects of the framework:

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `evolution.population_size` | 10 | Population size per generation |
| `evolution.offspring_count` | 10 | Offspring generated per generation |
| `evolution.max_generations` | 10 | Maximum evolution generations |
| `evolution.repair_attempts` | 3 | Repair attempts per failed individual |
| `evolution.parallel_workers` | 10 | Parallel offspring evaluation threads |
| `evolution.synth_failure_mode` | `"keep"` | `"keep"` preserves correctness; `"zero"` penalizes |
| `evolution.best_metric` | `"adp"` | Metric for global best selection |
| `evolution.selection.strategy` | `"proportional"` | `"proportional"` (POET 1/k) or `"sequential"` |
| `llm.generation_model` | `"gpt-4o-mini"` | Model for initial generation |
| `llm.mutation_model` | `"gpt-4o-mini"` | Model for mutation operators |
| `evaluation.correctness.simulation_timeout` | 120 | Seconds before simulation timeout |
| `evaluation.ppa.default_clock_period` | 10 | Clock period (ns) for OpenSTA |

### PPA Metrics

Six PPA metrics are tracked, with the best design saved for each:

| Metric | Formula | Description |
|--------|---------|-------------|
| `area` | Area | Chip area (um^2) |
| `delay` | Delay | Critical path delay (ns) |
| `power` | Power | Total power (uW) |
| `adp` | Area x Delay | Area-delay product |
| `pdp` | Power x Delay | Power-delay product |
| `adpwr` | Area x Delay x Power | Combined metric |

### Supported Models

Configured in `coevo/config/models.yaml`. The framework supports:

- **Standard models**: GPT-4o, GPT-4o-mini, GPT-4.1-mini (chat completions with `max_tokens`)
- **GPT-5 series**: GPT-5, GPT-5.1, GPT-5.4, GPT-5-mini, GPT-5.4-mini (chat completions with `max_completion_tokens`)
- **Codex models**: GPT-5-codex, GPT-5.1-codex, GPT-5.1-codex-mini (responses API with `instructions`/`input`)

## Output Structure

```
results/<experiment_name>/
├── config_snapshot.yaml            # Frozen config for reproducibility
├── summary.csv                     # Per-design results table
├── pass_at_k.csv                   # Per-design pass@k scores
├── pass_at_k.json                  # Detailed pass@k with global averages
├── evaluation_report.txt           # Human-readable summary report
│
├── <design_name>/
│   ├── summary.json                # Design result summary
│   ├── best_correct.v              # Best design (by configured metric)
│   ├── best_area.v                 # Best design by area
│   ├── best_delay.v                # Best design by delay
│   ├── best_power.v                # Best design by power
│   ├── best_adp.v                  # Best design by area-delay product
│   ├── best_pdp.v                  # Best design by power-delay product
│   ├── best_adpwr.v                # Best design by area-delay-power product
│   ├── ppa_comparison.json         # Candidate vs reference PPA
│   ├── evolution.log               # Per-generation log
│   ├── generation_log.json         # Structured generation history
│   └── pareto/                     # Pareto front designs
│       └── *.v
│
└── run_<id>/                       # Per-run directories (when runs > 1)
    └── ...
```

## Design Decisions

- **Enhanced testbench for evolution**: During evolution, only the enhanced testbench (continuous score [0, 1]) is used. The original testbench (binary pass/fail) is re-evaluated fresh on the best individual at the results phase for final pass@1 reporting.

- **Unified repair**: Synthesis failures and functional errors are combined into a single repair prompt. Synthesis diagnosis is extracted from Yosys logs (driver conflicts, 0-cell netlists, crashes).

- **Skip-list short-circuit**: Designs known to synthesize to 0 cells (wire-only, constant-only, pure bit-reordering) are short-circuited in PPA evaluation. Both `ppa` and `synth_diagnosis` are left as `None` to prevent spurious repair attempts.

- **Per-dataset system prompts**: RTLLM uses Verilog-2001 with 5 synthesis rules. VerilogEval adds 3 specification fidelity rules (sync-reset default, no stray negedge-clock clear, race-safe single-expression NBA) to close the gap between LLM conventions and VerilogEval reference models.

- **Strategy memory**: Per-design memory records effective optimizations, successful fixes, and failed attempts. Reset between designs to avoid cross-design contamination.

- **Adaptive correctness gate**: Annealing schedule from `theta_min` to `theta_max` with P25 fallback when no individual meets the primary threshold.

## License

This project is for research and educational purposes.

## Acknowledgments

- [RTLLM](https://github.com/hkust-zhiyao/RTLLM) benchmark for RTL generation evaluation
- [Yosys](https://github.com/YosysHQ/yosys) open-source synthesis suite
- [OpenSTA](https://github.com/The-OpenROAD-Project/OpenSTA) static timing analysis
- [OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) flow scripts and NanGate45 library
