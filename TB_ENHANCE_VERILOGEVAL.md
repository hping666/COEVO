# VerilogEval Testbench Enhancement Guide

> **STATUS (Phase A)**: The hand-written per-design workflow described in Sections 1–12 below has been **SUPERSEDED** by an automated code generator under `coevo/tb_gen/`. All 156 enhanced TBs are now produced from a single template and regenerated on demand. The original hand-written guidance is retained as historical background for the scoring protocol, module naming, and reset conventions; **new enhancements should land in the generator, not in per-design edits.** See Section 0 for the current architecture.

> **FILE-MODIFICATION POLICY**: In the normal course, do **NOT** modify, rename, delete, or overwrite any existing file under `~/MAS4RTL/VerilogEval/` (`*_test.sv`, `*_ref.sv`, `*_prompt.txt`, `problems.txt`, …). Phase A executed a **one-time, user-authorized exception** that overwrote all 156 `ProbXXX_*_test_enhanced.sv` files with generator output; that exception does **not** extend to any other file, and no further overwrites are permitted without explicit user approval. Temporary files generated during validation must always be cleaned up.

## 0. Phase A Overhaul — Generator-Produced Bucket-Scored TBs

Phase A replaced the hand-written `check_outputs` task model (Sections 5.2, 5.4) with a **continuous-monitor, bucket-scored** testbench produced by a single code generator. The resulting TB still emits a `[FORGE_RESULT] TOTAL=X PASSED=Y FAILED=Z` line for backward compatibility with `_parse_forge_output`, but the semantics and the diagnostic lines surrounding it have changed substantially.

### 0.1 Generator Layout (`coevo/tb_gen/`)

```
coevo/tb_gen/
├── template.py           # Core generator — single Jinja-like template producing
│                         #   one enhanced TB per design
├── port_parser.py        # Parses RefModule port list; classifies each design as
│                         #   combinational / sequential / sequential+pulse
├── generate_all.py       # Batch-generates all 156 TBs into the staging dir
├── validate_all.py       # Compiles each TB against the ref renamed to TopModule
│                         #   and fails loudly if weighted score < 1.0
└── _smoke_prob137.py     # Fast single-design smoke test (Prob137_fsm_serial)
```

Generated output is written to a **staging directory** first:
```
coevo/tb_templates_generated/
└── ProbXXX_*_test_enhanced.sv   # one file per design (156 total)
```

The staging dir is what `validate_all.py` checks. The **install step** (overwriting `VerilogEval/ProbXXX_*_test_enhanced.sv`) is deliberately manual and was executed exactly once under the one-time exception noted above.

### 0.2 Per-Design Classification

`port_parser.py` inspects each `<name>_ref.sv` header and assigns one of three categories, which gates which **buckets** the TB instantiates (see Section 0.3):

| Category              | Count | Trigger condition                                             |
|-----------------------|------:|---------------------------------------------------------------|
| combinational         | 82    | no `clk` port                                                 |
| sequential            | 67    | has `clk`; no obvious pulse-shaped output                     |
| sequential + pulse    | 7     | has `clk` **and** at least one output looks pulse-like (e.g. `done`, `valid`, edge-detect outputs) |

Classification also extracts: DUT instance name must be `uut`; reset port name and polarity (`reset` / `areset` / `resetn` / `aresetn`); clock port name (if any); per-output width.

### 0.3 Bucket Architecture

Rather than running a fixed sequence of `check_outputs` calls, the TB starts a **free-running monitor** immediately after reset and continuously samples DUT vs ref on every relevant clock edge (or every `#1` step, for combinational designs). Each sample is classified into **exactly one bucket**, and per-bucket pass/fail counters are maintained. Buckets are sized to fit the design category:

| Bucket         | Purpose                                                     | Weight | Applies to        |
|----------------|-------------------------------------------------------------|-------:|-------------------|
| `A_reset`      | samples during / immediately after reset                    |   0.05 | all               |
| `B_steady`     | steady-state operation after reset deassert                 |   0.40 | all               |
| `C_boundary`   | port boundary values (all-zero, all-ones, MSB only, …)      |   0.15 | all               |
| `D_backtoback` | back-to-back operations with no idle cycles                 |   0.10 | sequential only   |
| `F_longseq`    | long randomized stress sequence                             |   0.20 | all               |
| `G_pulse_edge` | one-cycle pulse / edge detection targets                    |   0.10 | sequential+pulse  |

(Weights sum to 1.0 per category after redistribution of unused buckets.)

### 0.4 Weighted Score Baked Into `FORGE_RESULT`

For backward compatibility with the existing RTLLM parser path, the generator **pre-scales** the weighted score to a fixed `TOTAL=10000`:

```
[FORGE_RESULT]            TOTAL=10000 PASSED=8167 FAILED=1833
[FORGE_SCORE_WEIGHTED]    0.8167
[FORGE_BUCKET]            A_reset=5/5 B_steady=50/50 C_boundary=18/18 D_backtoback=20/20 F_longseq=40/40 G_pulse_edge=29/48
[FORGE_FIRSTFAIL]         bucket=G_pulse_edge cyc=62 in=1 dut=1 ref=0
[FORGE_FIRSTFAIL]         bucket=G_pulse_edge cyc=74 in=0 dut=1 ref=0
[FORGE_RAW]               TOTAL=181 PASSED=162 FAILED=19
```

- `FORGE_RESULT` is the **scaled** line the score parser uses (`score = 8167/10000 = 0.8167`).
- `FORGE_SCORE_WEIGHTED` is the same number as a float, emitted for human/ log inspection.
- `FORGE_BUCKET` lists every active bucket as `name=passed/total`.
- `FORGE_FIRSTFAIL` is emitted **once per bucket** on its first mismatch, including the cycle, packed inputs, DUT output, and ref output (all hex).
- `FORGE_RAW` shows the unweighted pass/fail counts for reference; it is not used for scoring.

### 0.5 Identifier Convention — `fg_` Prefix

All TB-internal module-level identifiers use the `fg_` (forge) prefix to avoid collision with user port names in arbitrary VerilogEval designs. For example, port names `i`, `w`, `k` caused collisions in an earlier draft. The rule is:

- **Fixed**: DUT instance name is `uut`; golden ref instance is `fg_gold`. These are hard-coded so `_parse_dut_instantiation()` in `coevo/llm/prompt_templates.py` can extract the module header from the enhanced TB.
- **Prefixed**: all other TB-internal names use `fg_*` — counters (`fg_passed`, `fg_failed`), weight arrays (`fg_w`), loop indices (`fg_i`, `fg_k`), bucket IDs (`fg_bucket_*`), and the sampler task (`fg_sample`).
- **Never touched**: DUT port names themselves (must match the candidate's module exactly).

### 0.6 Regeneration Commands

```bash
conda activate PPA
cd ~/MAS4RTL

# 1. (Re)generate all 156 enhanced TBs into the staging dir:
python -m coevo.tb_gen.generate_all

# 2. Validate: compile each TB against the ref (renamed to TopModule as the DUT),
#    confirm weighted score == 1.0. Parallelized; FORGE_WORKERS=N to tune.
python -m coevo.tb_gen.validate_all

# 3. Smoke-test Prob137 in isolation (fastest inner loop):
python -m coevo.tb_gen._smoke_prob137

# 4. INSTALL — copy staging dir over VerilogEval/ (requires explicit user approval
#    every time; Phase A's one-time exception does NOT auto-renew).
#    Example (manual):
#    cp coevo/tb_templates_generated/*_test_enhanced.sv VerilogEval/
```

### 0.7 Feedback Plumbing Into the LLM Repair Path

`coevo/evaluation/correctness.py::_parse_forge_output` dispatches between two mutually-exclusive feedback styles and the VE bucket path now reaches the LLM (this was the Prob137 evolution bug fix):

- **Path A — RTLLM** (`testbench_enhanced.v`): looks for `[FORGE_CHECK N] FAIL ...` lines. First 20 are joined into `error_feedback`. Takes priority if both styles appear.
- **Path B — VerilogEval** (`coevo/tb_gen/template.py` output): builds `error_feedback` from three sources:
    1. A miss-only bucket summary: `<bucket>: p/t (miss t-p)` for any bucket with `p < t`.
    2. Up to 10 `[FORGE_FIRSTFAIL]` snapshot lines.
    3. The `[FORGE_SCORE_WEIGHTED]` line.

The assembled `error_feedback` flows through `has_func_issue` in `coevo/core/evolution.py` and into `build_repair_prompt`, so the LLM now sees *which* bucket is failing and the concrete first-failing cycle. Before the Phase A fix, VE designs produced empty feedback and the LLM was repairing blind.

### 0.8 Historical Reference

The remainder of this document (Sections 1 onward) documents the original hand-written, per-check approach. It is preserved because the **scoring protocol** (`[FORGE_RESULT]` line, 100%-pass-against-ref requirement, watchdog, iverilog `-g2012`, `===`-for-X correctness) and the **reset/port conventions** (Sections 5.6, 5.7) are still normative for the generator. The `check_outputs`-task examples and Section 9 walkthrough, however, no longer reflect what the generator emits — consult `coevo/tb_gen/template.py` for the current shape.

---

## 1. Mission (historical — hand-written approach)

For **every** design in `~/MAS4RTL/VerilogEval/`, generate an enhanced testbench file. This enhanced testbench must:

1. Provide a **fine-grained correctness score** in FORGE format: `[FORGE_RESULT] TOTAL=X PASSED=Y FAILED=Z`
2. Provide **per-check diagnostic output**: `[FORGE_CHECK id] FAIL | desc | expected=X got=Y | time=T`
3. **Expand test coverage** beyond the original testbench with boundary/corner cases and structured stress tests
4. Be **fully self-contained**: the `RefModule` golden model is embedded, so compilation needs only 2 files
5. **Pass 100%** when run against a correct `TopModule` implementation

## 2. Environment

```bash
conda activate PPA
cd ~/MAS4RTL

# Compilation (enhanced TB):
iverilog -g2012 -o sim_out VerilogEval/ProbXXX_name_test_enhanced.sv candidate.sv && vvp sim_out

# Compilation (original TB for final pass@1 retest):
iverilog -g2012 -o sim_out VerilogEval/ProbXXX_name_test.sv VerilogEval/ProbXXX_name_ref.sv candidate.sv && vvp sim_out
```

Key differences from RTLLM:
- **`-g2012` flag required**: 49/156 ref files use SystemVerilog (`always_comb`, `logic`, `enum`, `typedef`), ALL test files use SV (`typedef struct packed`)
- **2-file compilation** for enhanced TB (RefModule embedded), **3-file** for original TB
- **`.sv` file extension** (not `.v`)

## 3. VerilogEval Directory Structure

```
VerilogEval/
├── problems.txt                          # 156 design names (one per line)
├── problems-temp.txt                     # 20-design subset
├── Prob001_zero_prompt.txt               # Design specification
├── Prob001_zero_ref.sv                   # RefModule — golden reference
├── Prob001_zero_test.sv                  # Original testbench (stimulus_gen + tb)
├── Prob001_zero_test_enhanced.sv         # ← NEW: Enhanced testbench (to generate)
├── Prob031_dff_prompt.txt
├── Prob031_dff_ref.sv
├── Prob031_dff_test.sv
├── Prob031_dff_test_enhanced.sv          # ← NEW
├── Prob062_bugs_mux2.sv                  # Extra artifact file (ignore — not a standard file)
├── Prob062_bugs_mux2_prompt.txt          # Prob062 has all 3 standard files, do NOT skip
├── Prob062_bugs_mux2_ref.sv
├── Prob062_bugs_mux2_test.sv
└── ...  (156 designs × 3 files + enhanced TBs)
```

Each design has exactly 3 files:
- `ProbXXX_name_prompt.txt` — natural language specification for the LLM
- `ProbXXX_name_ref.sv` — `RefModule`: functionally correct reference implementation
- `ProbXXX_name_test.sv` — original testbench with `stimulus_gen` + `tb` modules

**Module naming convention (FIXED across all designs)**:
- DUT: always `TopModule`, instance name `top_module1` (in original) or `uut` (in enhanced)
- Reference: always `RefModule`, instance name `good1` (in original) or `ref_model` (in enhanced)
- **No renaming needed**: unlike RTLLM where DUT and golden share the same module name, VerilogEval's `TopModule` ≠ `RefModule` — they never conflict

## 4. Original Testbench Patterns

All VerilogEval testbenches follow the same structural pattern:

```systemverilog
`timescale 1 ps/1 ps

module stimulus_gen (input clk, output reg[511:0] wavedrom_title, output reg wavedrom_enable);
    // Generates input stimulus, calls $finish when done
    // May include: handcrafted sequences, $random/$urandom, wavedrom sections
endmodule

module tb();
    typedef struct packed {
        int errors; int errortime;
        int errors_out1; int errortime_out1;  // per-output tracking
        // ... one pair per output signal ...
        int clocks;
    } stats;
    stats stats1;

    reg clk=0;
    initial forever #5 clk = ~clk;           // 10 ps clock

    RefModule good1 (.port1(out1_ref), ...);  // Golden reference
    TopModule top_module1 (.port1(out1_dut), ...);  // DUT

    // XOR-based verification (X in ref matches anything, X in DUT only matches X)
    assign tb_match = ( { out1_ref } === ( { out1_ref } ^ { out1_dut } ^ { out1_ref } ) );

    always @(posedge clk, negedge clk) begin
        stats1.clocks++;
        if (!tb_match) begin stats1.errors++; ... end
    end

    final begin
        $display("Hint: Output '%s' has %0d mismatches.", "out1", stats1.errors_out1);
        $display("Mismatches: %1d in %1d samples", stats1.errors, stats1.clocks);
    end

    initial begin #1000000 $display("TIMEOUT"); $finish(); end
endmodule
```

**Limitations of original testbench**:
- **Binary scoring**: `Mismatches: X in Y` → either 0 (pass) or >0 (fail), no continuous score
- **No per-check diagnostics**: only reports which outputs mismatch and first mismatch time
- **Limited stimulus variety**: many designs use only `$random`/`$urandom` with no systematic boundary testing
- **Sampling on both edges**: checks at posedge AND negedge, which can double-count for edge-triggered designs

**Three stimulus patterns observed in `stimulus_gen`**:

| Pattern | Example | Description |
|---------|---------|-------------|
| **Random only** | Prob031_dff | `d <= $urandom` every clock edge, ~100-200 cycles |
| **Handcrafted + Random** | Prob045_edgedetect2 | Specific sequences first, then random phase |
| **Pure random with scaling** | Prob150_review2015 | `state <= 1<<($unsigned($random)%10)`, 300 cycles |

## 5. Enhancement Strategy

### 5.1 Overall Structure Template

```systemverilog
`timescale 1 ps/1 ps

module testbench_enhanced;

    // ============================================================
    // SECTION 1: Signal Declarations
    // ============================================================
    reg clk;
    // All DUT input ports as reg
    // All DUT output ports split: wire xxx_dut, xxx_ref;

    // ============================================================
    // SECTION 2: Clock Generation
    // ============================================================
    // ALWAYS present (even for combinational designs — used for synchronization)
    initial clk = 0;
    always #5 clk = ~clk;  // 10 ps period, matching original TB

    // ============================================================
    // SECTION 3: Test Infrastructure
    // ============================================================
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed, i;

    // ============================================================
    // SECTION 4: DUT Instantiation
    // ============================================================
    TopModule uut ( .port1(input1), .port2(output1_dut), ... );

    // ============================================================
    // SECTION 5: Golden Reference Instantiation
    // ============================================================
    RefModule ref_model ( .port1(input1), .port2(output1_ref), ... );

    // ============================================================
    // SECTION 6: Check Task
    // ============================================================
    // (See Section 5.2)

    // ============================================================
    // SECTION 7: Watchdog Timer
    // ============================================================
    initial begin #5000000; $display("[FORGE_RESULT] TIMEOUT"); $finish; end

    // ============================================================
    // SECTION 8: Test Cases
    // ============================================================
    initial begin
        // Group A: Original stimulus reproduction
        // Group B: Boundary / corner cases
        // Group C: Randomized stress tests
        // Group D: Protocol / timing tests (sequential designs)

        // SECTION 9: Score Reporting
        // (See Section 5.4)
    end

endmodule

// ============================================================
// SECTION 10: Embedded RefModule (copied verbatim from ref.sv)
// ============================================================
```

**Key simplifications vs RTLLM**:
- Clock ALWAYS present (for synchronization, even if DUT is combinational)
- Unified check timing: `@(posedge clk); #1; check_outputs(...)` for ALL designs
- No module renaming needed (RefModule ≠ TopModule)
- SystemVerilog allowed (we compile with `-g2012`)

### 5.2 The Check Task

**Single-output design**:

```systemverilog
task check_outputs;
    input [511:0] description;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (q_dut === q_ref) begin
            passed_checks = passed_checks + 1;
        end else begin
            failed_checks = failed_checks + 1;
            $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%h got=%h | time=%0t",
                check_id, description, q_ref, q_dut, $time);
        end
    end
endtask
```

**Multi-output design** (e.g., 3 outputs):

```systemverilog
task check_outputs;
    input [511:0] description;
    begin
        check_id = check_id + 1;
        total_checks = total_checks + 1;
        if (out1_dut === out1_ref && out2_dut === out2_ref && out3_dut === out3_ref) begin
            passed_checks = passed_checks + 1;
        end else begin
            failed_checks = failed_checks + 1;
            $display("[FORGE_CHECK %0d] FAIL | %0s | time=%0t", check_id, description, $time);
            if (out1_dut !== out1_ref)
                $display("  -> out1: expected=%h got=%h", out1_ref, out1_dut);
            if (out2_dut !== out2_ref)
                $display("  -> out2: expected=%h got=%h", out2_ref, out2_dut);
            if (out3_dut !== out3_ref)
                $display("  -> out3: expected=%h got=%h", out3_ref, out3_dut);
        end
    end
endtask
```

**Rules**:
- Always use `===` (case equality), never `==`
- One check = one call to `check_outputs` = one increment of `total_checks`
- Only print on FAIL (reduces output noise)
- Description string helps LLM repair by indicating which test case failed

### 5.3 Golden Model Strategy

**VerilogEval is simpler than RTLLM here**: `RefModule` already has a different name from `TopModule`, so we embed it verbatim — no renaming, no prefix, no sub-module renaming.

**Procedure**:
1. Read `ProbXXX_name_ref.sv`
2. Copy the **entire file contents** (including any helper modules/functions)
3. Paste at the bottom of the enhanced testbench file (SECTION 10)
4. Instantiate as `RefModule ref_model (...)`

**Why this works**: When compiled as `iverilog -g2012 -o sim test_enhanced.sv candidate.sv`:
- `test_enhanced.sv` defines: `testbench_enhanced` (the TB) + `RefModule` (the golden)
- `candidate.sv` defines: `TopModule` (the DUT)
- No naming conflicts

**Edge cases**:
- If RefModule uses `initial q = 1'hx;` or similar X-initialization, preserve it — the check task's `===` handles X values correctly
- **All 156 ref files are single-module** — no sub-module instantiation found. Simply copy the full file.
- RefModule may use SystemVerilog features (`always_comb`, `always_ff`, `logic`, `enum`, `typedef`) — this is fine with `-g2012`
- **31 ref files use `parameter` or `localparam`** (e.g., Prob153_gshare: `parameter n = 7`). These are preserved verbatim when embedded. Do NOT override parameter defaults — the original test.sv also uses defaults.
- **1 ref file uses internal 2D arrays** (Prob153_gshare: `logic [1:0] pht [2**n-1:0]`). This is fine — it's internal to RefModule.

### 5.4 Score Reporting Block (use this exact format)

```systemverilog
$display("===================================================");
$display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d", total_checks, passed_checks, failed_checks);
if (failed_checks == 0)
    $display("[FORGE_RESULT] STATUS=PASS SCORE=%0d/%0d", passed_checks, total_checks);
else
    $display("[FORGE_RESULT] STATUS=FAIL SCORE=%0d/%0d", passed_checks, total_checks);
$display("===================================================");
$finish;
```

### 5.5 Test Case Categories

#### Group A — Original Stimulus Reproduction (5-15 checks)

Reproduce the key stimulus patterns from `stimulus_gen` in the original `test.sv`. This ensures backward compatibility.

**How to extract stimulus from `stimulus_gen`**:
1. Read the `stimulus_gen` module in `ProbXXX_name_test.sv`
2. Identify handcrafted stimulus sequences (specific values, not `$random`)
3. If stimulus is purely random, reproduce ~10-20 random cycles with a fixed seed
4. If stimulus has wavedrom sections, reproduce the specific values shown in wavedrom
5. Simplify: don't try to replicate exact random sequences or wavedrom timing — just cover the same scenarios

**Example** — for a design whose `stimulus_gen` does:
```systemverilog
in <= 0;      // 4 cycles of 0
in <= 1;      // 4 cycles of 1
in <= $random; // 200 random cycles
```
Group A would be:
```systemverilog
// Reproduce handcrafted portion
in = 0; repeat(4) begin @(posedge clk); #1; check_outputs("orig_zero"); end
in = 1; repeat(4) begin @(posedge clk); #1; check_outputs("orig_one"); end
// A few random cycles
for (i = 0; i < 10; i = i + 1) begin
    in = $random(seed); @(posedge clk); #1; check_outputs("orig_random");
end
```

#### Group B — Boundary and Corner Cases (10-25 checks)

Based on the design type and port widths, systematically test boundaries:

| Input Type | Boundary Values to Test |
|---|---|
| N-bit unsigned | `0`, `{N{1'b1}}` (all ones), `1`, `{1'b1, {(N-1){1'b0}}}` (MSB only), alternating `{N/2{2'b10}}` and `{N/2{2'b01}}` |
| 1-bit boolean | `0`, `1` |
| Signed N-bit | `0`, max positive (`{1'b0, {(N-1){1'b1}}}`), min negative (`{1'b1, {(N-1){1'b0}}}`), `-1` (`{N{1'b1}}`) |
| State/select | All valid encodings, one-hot if applicable |
| Clock/enable | Toggling, held high, held low |
| Reset | Assert/deassert, reset during operation, multiple resets |

**Design-specific boundaries** (derive from `prompt.txt`):

| Design Type | Additional Boundaries |
|---|---|
| DFF/Latch | Hold input stable, rapid toggle, change near clock edge |
| Arithmetic | Overflow, underflow, carry propagation, zero operands |
| Multiplexer | Each select value, undefined select |
| FSM | All state transitions, reset from each state, invalid inputs per state |
| Counter | Count to max/wrap, enable toggle, reset mid-count |
| Shift register | Shift by 0, by max, of all-ones, of single-bit |
| Decoder/Encoder | Each valid input, all-zero, all-one |
| Edge detector | Rising, falling, both, no edge, consecutive edges |

#### Group C — Randomized Stress Tests (30-50 checks)

```systemverilog
seed = 42;
for (i = 0; i < 50; i = i + 1) begin
    input1 = $random(seed);
    input2 = $random(seed);
    // ... all inputs randomized
    @(posedge clk); #1;
    check_outputs("random_stress");
end
```

- Always use `$random(seed)` with `seed = 42` for reproducibility
- Do NOT use `$urandom` — use `$random(seed)` for deterministic reproducibility with seed control
- For inputs ≤ 32 bits, one `$random(seed)` call suffices (returns 32 bits, truncated to fit)
- For inputs with constrained ranges (e.g., 3-bit select), use modulo: `sel = $random(seed) % 8;`
- **For wide inputs (> 32 bits)**: `$random` returns only 32 bits. Fill wide buses with multiple calls:
  ```systemverilog
  // Example: 512-bit input
  integer j;
  for (j = 0; j < 16; j = j + 1)
      data[j*32 +: 32] = $random(seed);
  ```
  For 100-bit inputs use 4 calls (`4 × 32 = 128 > 100`, excess bits are truncated).
  For 256-bit inputs use 8 calls. For 1024-bit inputs use 32 calls.

#### Group D — Protocol and Timing Tests (5-15 checks, sequential designs only)

Only include Group D if the DUT has `clk` and/or `reset`/`areset` ports:

- **Reset sequence**: Assert reset, verify outputs, deassert reset, verify recovery
- **Reset during operation**: Start a sequence, assert reset mid-way, verify clean restart
- **Back-to-back operations**: No idle cycles between transactions
- **Idle insertion**: Deassert enable/valid for several cycles, then resume
- **Multiple resets**: Assert reset twice consecutively

### 5.6 Timing and Synchronization

**Unified timing rule** — for BOTH combinational and sequential designs:

```systemverilog
// Apply stimulus
input1 = value;
// Wait for clock edge + settling time
@(posedge clk); #1;
// Check outputs
check_outputs("description");
```

**Why this works for combinational designs**: The clock is just a synchronization mechanism. Combinational outputs settle well before the next clock edge. Checking at `posedge + 1ps` captures stable outputs.

**Why this works for sequential designs**: Registered outputs update at posedge. The `#1` delay allows outputs to settle after the clock edge.

**Reset handling** for sequential designs:
```systemverilog
initial begin
    // Initialize all inputs to 0
    input1 = 0; input2 = 0;
    
    // Apply reset (check ref.sv to determine polarity and port name)
    // ---- Active-high reset (port: `reset`, sync or async) ----
    // 29 designs, e.g., Prob041_dff8r, Prob038_count15, Prob067_countslow
    // Check ref.sv sensitivity list to determine sync vs async:
    reset = 1;
    repeat(2) @(posedge clk); #1;
    reset = 0;
    @(posedge clk); #1;
    
    // ---- Active-high async reset (port: `areset`) ----
    // 14 designs, e.g., Prob047_dff8ar, Prob109_fsm1, Prob127_lemmings1
    // ref.sv uses: always @(posedge clk, posedge areset)
    areset = 1;
    repeat(2) @(posedge clk); #1;
    areset = 0;
    @(posedge clk); #1;
    
    // ---- Active-low sync reset (port: `resetn`) ----
    // 4 designs: Prob060_m2014_q4k, Prob073_dff16e, Prob139_2013_q2bfsm, Prob148_2013_q2afsm
    resetn = 0;
    repeat(2) @(posedge clk); #1;
    resetn = 1;
    @(posedge clk); #1;
    
    // ---- Active-low async reset (port: `aresetn`) ----
    // 1 design: Prob129_ece241_2013_q8
    // ref.sv uses: always @(posedge clk, negedge aresetn)
    aresetn = 0;
    repeat(2) @(posedge clk); #1;
    aresetn = 1;
    @(posedge clk); #1;
    
    // Begin test cases...
end
```

**Determining reset convention**: Read `ref.sv` to identify:
- Port name `areset` → active-high, async (check for `posedge areset` in sensitivity list)
- Port name `reset` → active-high, check sensitivity list: `always @(posedge clk)` = sync, `always @(posedge clk, posedge reset)` = async
- Port name `resetn` → active-low, check sensitivity list for `negedge resetn`
- Port name `aresetn` → active-low, async (check for `negedge aresetn` in sensitivity list)
- **No `rst_n` or `rst` exists in VerilogEval** — only the 4 patterns above
- If no reset port exists, skip reset sequence entirely

**Negedge-triggered designs**:

A few designs use `@(negedge clk)` instead of `@(posedge clk)`:
- **Prob046_dff8p**: `always @(negedge clk)` — negative-edge-triggered DFF with sync reset
- **Prob078_dualedge**: captures data on BOTH posedge and negedge

For these designs, the unified `@(posedge clk); #1;` timing still works correctly because both DUT and RefModule see the same clock. Negedge-triggered outputs will have settled before the next posedge check. However, for dual-edge designs, **add checks at both edges** to increase coverage:

```systemverilog
// For dual-edge designs (e.g., Prob078_dualedge):
for (i = 0; i < 50; i = i + 1) begin
    d = $random(seed);
    @(posedge clk); #1;
    check_outputs("random_pos");
    @(negedge clk); #1;
    check_outputs("random_neg");
end
```

### 5.7 Minimum Check Count Targets

| Design Complexity | Minimum total_checks |
|---|---|
| Trivial (constant output, wire) | 20 |
| Simple combinational (mux, basic gates) | 40 |
| Arithmetic (adders, comparators) | 60 |
| Sequential (DFF, counter, shift register) | 50 |
| FSM | 40 (but cover all transitions) |
| Complex combinational (ALU, encoder, decoder) | 60 |
| Complex sequential (multi-state FSM, pipeline) | 80 |

## 6. Step-by-Step Workflow for Each Design

### Step 1: Analyze

Read three files:
```bash
cat VerilogEval/ProbXXX_name_prompt.txt     # Design specification
cat VerilogEval/ProbXXX_name_ref.sv         # Reference implementation
cat VerilogEval/ProbXXX_name_test.sv        # Original testbench
```

Identify:
- **Ports**: names, directions, widths (from `RefModule` header or `TopModule` instantiation in test.sv)
- **Sequential or combinational**: does the DUT have `clk`? Any `reset`/`areset`?
- **Reset convention**: active-high or active-low? Synchronous or asynchronous?
- **Output signals**: list all output port names (for check task)
- **Original stimulus**: what does `stimulus_gen` do? Handcrafted or random?
- **Design semantics**: what does prompt.txt describe? What boundaries are relevant?

### Step 2: Generate Enhanced Testbench

1. **Section 1**: Declare all input regs and output wire pairs (`_dut`, `_ref`)
2. **Section 2**: Clock generation (always include)
3. **Section 3**: Test infrastructure variables
4. **Section 4**: `TopModule uut (...)` — copy port connections from original TB's `top_module1`
5. **Section 5**: `RefModule ref_model (...)` — same port connections but outputs go to `_ref` wires
6. **Section 6**: `check_outputs` task comparing all `_dut` vs `_ref` output pairs
7. **Section 7**: Watchdog timer
8. **Section 8**: Test cases (Groups A-D) with appropriate reset sequence
9. **Section 9**: FORGE score reporting + `$finish`
10. **Section 10**: Copy entire `ref.sv` contents (RefModule + any sub-modules)

### Step 3: Validate

```bash
cd ~/MAS4RTL

# Create a temporary TopModule that wraps RefModule behavior:
# (Since ref.sv defines RefModule, not TopModule, we need a correct TopModule for testing)
python3 -c "
import re, sys
ref = open('VerilogEval/ProbXXX_name_ref.sv').read()
# Replace 'module RefModule' with 'module TopModule'
top = re.sub(r'module\s+RefModule', 'module TopModule', ref, count=1)
open('/tmp/topmodule_test.sv', 'w').write(top)
"

# Compile and run
iverilog -g2012 -o /tmp/sim_out VerilogEval/ProbXXX_name_test_enhanced.sv /tmp/topmodule_test.sv 2>&1
vvp /tmp/sim_out 2>&1

# Expected output must include:
# [FORGE_RESULT] STATUS=PASS SCORE=N/N  (100% pass)

# Cleanup
rm -f /tmp/sim_out /tmp/topmodule_test.sv
```

**If the enhanced testbench does NOT achieve 100% pass when tested against the reference design (via renamed TopModule), there is a bug in the testbench — fix it before moving on.**

### Step 4: Verify Original TB Still Works

```bash
# Sanity: original test.sv should pass with ref.sv
# Create TopModule from RefModule for this test too
iverilog -g2012 -o /tmp/sim_orig VerilogEval/ProbXXX_name_test.sv VerilogEval/ProbXXX_name_ref.sv /tmp/topmodule_test.sv 2>&1
vvp /tmp/sim_orig 2>&1
# Should show: Mismatches: 0 in N samples
rm -f /tmp/sim_orig
```

## 7. Critical Rules and Pitfalls

### DO:
- Always use `===` (case equality) for comparisons, not `==`
- Always embed the full RefModule at the bottom of the enhanced testbench file
- Always use `$finish` at the end
- Always use `` `timescale 1 ps/1 ps `` (matching VerilogEval convention)
- Always include a watchdog: `initial begin #5000000; $display("[FORGE_RESULT] TIMEOUT"); $finish; end`
- Always validate against the reference design before finalizing
- Use `$random(seed)` with fixed `seed = 42` for reproducibility
- Handle both sync and async reset conventions (check the ref.sv)
- Use `@(posedge clk); #1;` before checking outputs (settling time)
- Include the `-g2012` flag in all iverilog commands

### DO NOT:
- Never hardcode expected output values — always derive from RefModule golden model
- Never modify the DUT interface (port names, widths) — the testbench must work with any `TopModule` that implements the same interface
- Never use `$readmemh` or external files — everything must be self-contained
- Never use `$urandom` — use `$random(seed)` instead (more portable)
- Never create infinite loops without watchdog
- Never use `$dumpfile`/`$dumpvars` (unnecessary for FORGE scoring, adds overhead)
- Never have total simulation time exceed 5ms (5,000,000 ps with `1 ps` timescale)
- Never modify any existing files in the VerilogEval directory

### SPECIAL HANDLING:
- **Designs with `initial` blocks in RefModule**: Some RefModules use `initial q = 1'hx;`. Preserve this — the `===` comparison handles X correctly. Start checking only AFTER the first clock edge (so initial X has been overwritten by real data).
- **RefModule using `always_comb`/`always_ff`/`enum`/`typedef`**: Fine — we compile with `-g2012`. Affects 49/156 designs.
- **Parameterized RefModule**: 31 designs use `parameter`/`localparam`. Embed verbatim; do not override defaults.
- **Purely combinational designs (no clk port)**: Still include clock for synchronization. `TopModule` won't connect to `clk`, but the test sequence uses `@(posedge clk)` for timing.
- **Designs with no inputs** (e.g., Prob001_zero: output is constant 0): Still run a few clock cycles and check. Even a trivial design needs at least 20 checks.
- **Wide bus designs** (32+ bit ports): Use `%h` (hex) format in FAIL messages, not `%b` (binary). Randomize with multiple `$random(seed)` calls (see Section 5.5 Group C).
- **Very wide bus designs** (100-1024 bit inputs): Found in Prob021_mux256to1v (`[1023:0] in`), Prob108_rule90 (`[511:0] data`), Prob144_conwaylife (`[255:0] data`), Prob030_popcount255 (`[254:0] in`), etc. Use loop-based random fill.
- **Multiple output designs (8+ outputs)**: The check task's `if` condition uses `&&` (all outputs must match to pass). In the `else` (fail) block, check each output individually with `!==` and print only mismatched ones. Prob150_review2015_fsmonehot has 8 outputs.
- **Negedge-triggered designs**: Prob046_dff8p uses `always @(negedge clk)`. The unified `@(posedge clk); #1;` check timing still works (both DUT and RefModule respond to same clock).
- **Dual-edge designs**: Prob078_dualedge captures on both posedge and negedge. For this design, check at BOTH edges for full coverage (see Section 5.6).
- **Prob062_bugs_mux2**: Has all 3 standard files plus an extra standalone `Prob062_bugs_mux2.sv`. Ignore the standalone file; generate enhanced TB as normal.

## 8. Output Parsing Specification

> **Phase A update**: the generator-produced TB no longer emits `[FORGE_CHECK ...]` lines. It emits a bucket-scored set of lines (`FORGE_BUCKET` / `FORGE_FIRSTFAIL` / `FORGE_SCORE_WEIGHTED`) while keeping `FORGE_RESULT` pre-scaled to `TOTAL=10000` for backward compatibility with the score parser. The `FORGE_CHECK` format below is kept only because RTLLM's hand-written enhanced TBs still use it, and `_parse_forge_output` retains a Path A fall-back for those.

### 8.1 Score line (both datasets)

```
[FORGE_RESULT] TOTAL=<N> PASSED=<M> FAILED=<K>       → summary counts
[FORGE_RESULT] TIMEOUT                                → simulation hung
```

Correctness score: `score = M / N` (float in [0.0, 1.0]). For VerilogEval under Phase A the generator always emits `TOTAL=10000` and `PASSED = round(weighted_score * 10000)` so the parser yields the weighted bucket score verbatim.

### 8.2 RTLLM feedback format (Path A — legacy, RTLLM only)

```
[FORGE_CHECK <id>] FAIL | <description> | expected=<X> got=<Y> | time=<T>
```

`_parse_forge_output` collects the first 20 such lines into `error_feedback`. If any `FORGE_CHECK` line is present, Path A wins and Path B is skipped (preserves RTLLM behavior exactly).

### 8.3 VerilogEval feedback format (Path B — Phase A bucket output)

```
[FORGE_BUCKET] A_reset=5/5 B_steady=50/50 C_boundary=18/18 D_backtoback=20/20 F_longseq=40/40 G_pulse_edge=29/48
[FORGE_FIRSTFAIL] bucket=<name> cyc=<c> in=<hex> dut=<hex> ref=<hex>      (one per failing bucket)
[FORGE_SCORE_WEIGHTED] <float>
[FORGE_RAW] TOTAL=<raw_n> PASSED=<raw_m> FAILED=<raw_k>                    (informational; not scored)
```

`_parse_forge_output` assembles `error_feedback` from:
1. a miss-only summary of `FORGE_BUCKET` (only buckets with `p < t`),
2. up to 10 `FORGE_FIRSTFAIL` snapshot lines,
3. the `FORGE_SCORE_WEIGHTED` value.

The resulting feedback is routed through `has_func_issue` in `coevo/core/evolution.py` into `build_repair_prompt`, so the LLM's repair attempt sees per-bucket coverage gaps and the first-failing cycle for each bucket.

## 9. Complete Example: Prob031_dff (D Flip-Flop)

**Design**: A simple positive-edge-triggered D flip-flop.

**Prompt** (`Prob031_dff_prompt.txt`):
> Create a single D flip-flop, triggered on the positive edge of clk.

**RefModule** (`Prob031_dff_ref.sv`):
```systemverilog
module RefModule (
  input clk,
  input d,
  output reg q
);
  initial q = 1'hx;
  always @(posedge clk) q <= d;
endmodule
```

**Original stimulus** (`Prob031_dff_test.sv`): Random `d` via `$urandom` for ~20 cycles + wavedrom, then 100 random cycles.

**Enhanced Testbench** (`Prob031_dff_test_enhanced.sv`):

```systemverilog
`timescale 1 ps/1 ps

module testbench_enhanced;

    // ============================================================
    // SECTION 1: Signal Declarations
    // ============================================================
    reg clk;
    reg d;
    wire q_dut, q_ref;

    // ============================================================
    // SECTION 2: Clock Generation
    // ============================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // ============================================================
    // SECTION 3: Test Infrastructure
    // ============================================================
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer seed, i;

    // ============================================================
    // SECTION 4: DUT Instantiation
    // ============================================================
    TopModule uut (
        .clk(clk), .d(d), .q(q_dut)
    );

    // ============================================================
    // SECTION 5: Golden Reference
    // ============================================================
    RefModule ref_model (
        .clk(clk), .d(d), .q(q_ref)
    );

    // ============================================================
    // SECTION 6: Check Task
    // ============================================================
    task check_outputs;
        input [511:0] description;
        begin
            check_id = check_id + 1;
            total_checks = total_checks + 1;
            if (q_dut === q_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%b got=%b | time=%0t",
                    check_id, description, q_ref, q_dut, $time);
            end
        end
    endtask

    // ============================================================
    // SECTION 7: Watchdog Timer
    // ============================================================
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // ============================================================
    // SECTION 8: Test Cases
    // ============================================================
    initial begin
        seed = 42;
        d = 0;

        // Allow initial state to settle
        @(posedge clk); #1;

        // ---- Group A: Original stimulus patterns ----
        // Original uses random d on every clock edge for ~120 cycles
        for (i = 0; i < 15; i = i + 1) begin
            d = $random(seed);
            @(posedge clk); #1;
            check_outputs("orig_random");
        end

        // ---- Group B: Boundary / corner cases ----
        // B1: d=0 held for multiple cycles
        d = 0;
        repeat(4) begin @(posedge clk); #1; check_outputs("hold_0"); end

        // B2: d=1 held for multiple cycles
        d = 1;
        repeat(4) begin @(posedge clk); #1; check_outputs("hold_1"); end

        // B3: Rapid toggling every cycle
        repeat(8) begin
            d = ~d;
            @(posedge clk); #1;
            check_outputs("toggle");
        end

        // B4: 0->1 transition
        d = 0;
        @(posedge clk); #1; check_outputs("trans_0");
        d = 1;
        @(posedge clk); #1; check_outputs("trans_0to1");

        // B5: 1->0 transition
        d = 1;
        @(posedge clk); #1; check_outputs("trans_1");
        d = 0;
        @(posedge clk); #1; check_outputs("trans_1to0");

        // B6: d changes mid-cycle (should not affect output until next posedge)
        d = 0;
        @(posedge clk); #1; check_outputs("mid_cycle_start_0");
        #3; d = 1;  // change d between clock edges
        @(posedge clk); #1; check_outputs("mid_cycle_change");

        // B7: Same value for many cycles then change
        d = 0;
        repeat(6) begin @(posedge clk); #1; check_outputs("long_hold_0"); end
        d = 1;
        @(posedge clk); #1; check_outputs("after_long_hold");

        // ---- Group C: Randomized stress test ----
        for (i = 0; i < 50; i = i + 1) begin
            d = $random(seed);
            @(posedge clk); #1;
            check_outputs("random_stress");
        end

        // ---- Group D: Protocol / timing tests ----
        // D1: Alternating pattern for 10 cycles
        d = 1;
        repeat(10) begin
            d = ~d;
            @(posedge clk); #1;
            check_outputs("alt_pattern");
        end

        // D2: Burst of same value
        d = 1;
        repeat(10) begin @(posedge clk); #1; check_outputs("burst_1"); end
        d = 0;
        repeat(10) begin @(posedge clk); #1; check_outputs("burst_0"); end

        // ============================================================
        // FORGE Score Report
        // ============================================================
        $display("===================================================");
        $display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d",
                 total_checks, passed_checks, failed_checks);
        if (failed_checks == 0)
            $display("[FORGE_RESULT] STATUS=PASS SCORE=%0d/%0d",
                     passed_checks, total_checks);
        else
            $display("[FORGE_RESULT] STATUS=FAIL SCORE=%0d/%0d",
                     passed_checks, total_checks);
        $display("===================================================");
        $finish;
    end

endmodule

// ============================================================
// SECTION 10: Golden Reference (copied from Prob031_dff_ref.sv)
// ============================================================
module RefModule (
  input clk,
  input d,
  output reg q
);
  initial
    q = 1'hx;
  always @(posedge clk)
    q <= d;
endmodule
```

**Validation**:
```bash
# Create TopModule wrapper from RefModule
echo 'module TopModule(input clk, input d, output reg q); initial q=1'"'"'hx; always @(posedge clk) q<=d; endmodule' > /tmp/top_dff.sv

# Compile and run
iverilog -g2012 -o /tmp/sim_dff VerilogEval/Prob031_dff_test_enhanced.sv /tmp/top_dff.sv && vvp /tmp/sim_dff
# Expected: [FORGE_RESULT] STATUS=PASS SCORE=130/130

rm -f /tmp/sim_dff /tmp/top_dff.sv
```

## 10. Batch Validation Script

After generating all enhanced testbenches, validate them all:

```bash
#!/bin/bash
cd ~/MAS4RTL

pass=0; fail=0; skip=0

for test_enh in VerilogEval/*_test_enhanced.sv; do
    # Extract design name: ProbXXX_name
    base=$(basename "$test_enh" _test_enhanced.sv)
    ref_file="VerilogEval/${base}_ref.sv"

    if [ ! -f "$ref_file" ]; then
        echo "SKIP: $base (no ref.sv)"
        skip=$((skip + 1))
        continue
    fi

    # Create temporary TopModule from RefModule
    sed 's/module RefModule/module TopModule/' "$ref_file" > /tmp/topmodule_val.sv

    # Compile
    if ! iverilog -g2012 -o /tmp/sim_val "$test_enh" /tmp/topmodule_val.sv 2>/tmp/compile_err.txt; then
        echo "COMPILE_FAIL: $base"
        cat /tmp/compile_err.txt
        fail=$((fail + 1))
        continue
    fi

    # Run
    result=$(vvp /tmp/sim_val 2>&1)
    if echo "$result" | grep -q "STATUS=PASS"; then
        score=$(echo "$result" | grep "FORGE_RESULT.*SCORE" | tail -1)
        echo "PASS: $base | $score"
        pass=$((pass + 1))
    else
        echo "FAIL: $base"
        echo "$result" | grep -E "FORGE|TIMEOUT"
        fail=$((fail + 1))
    fi
done

rm -f /tmp/sim_val /tmp/topmodule_val.sv /tmp/compile_err.txt
echo ""
echo "Results: $pass passed, $fail failed, $skip skipped (total: $((pass+fail+skip)))"
```

## 11. Checklist Before Marking a Design as Done

For each design, verify:

- [ ] `ProbXXX_name_test_enhanced.sv` exists in `VerilogEval/`
- [ ] Compiles without errors: `iverilog -g2012 -o sim test_enhanced.sv topmodule.sv`
- [ ] Runs and produces `[FORGE_RESULT]` output
- [ ] Achieves `STATUS=PASS` with 100% score against reference
- [ ] Contains at least the minimum number of checks for the design complexity
- [ ] Covers Groups A, B, C (and D if sequential)
- [ ] RefModule is embedded verbatim at the bottom of the file
- [ ] No external file dependencies
- [ ] Has a watchdog timer (`#5000000`)
- [ ] Uses `===` for comparisons (not `==`)
- [ ] Uses `` `timescale 1 ps/1 ps ``
- [ ] Uses `$random(seed)` not `$urandom`

## 12. Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `Module RefModule already defined` | RefModule in both enhanced TB and ref.sv are compiled together | Enhanced TB should only compile with candidate.sv, not ref.sv |
| `Unknown module type: TopModule` | candidate.sv not provided or wrong module name | Ensure candidate defines `module TopModule(...)` |
| `syntax error` with `always_comb` | Missing `-g2012` flag | Always use `iverilog -g2012` |
| Score < 100% on reference | Bug in enhanced TB timing or port connections | Check: port widths match ref.sv, reset polarity correct, settling time adequate |
| X values causing failures | Outputs uninitialized before first clock edge | Skip checking during reset; or start checking after reset deasserts |
| `$random` returns same sequence | Forgot to use `seed` variable | Use `$random(seed)`, not `$random` |
| Simulation hangs | No `$finish` or blocked on signal | Verify watchdog present; check for `@(signal)` that may never trigger |
| `Port size mismatch` | Width in TB doesn't match RefModule/TopModule | Cross-check port widths with `ref.sv` module header |
| `TIMEOUT` in output | Test sequence too long or clock period mismatch | Reduce test count or increase watchdog limit |
| Compile warning: implicit wire | Output wire not declared | Declare all DUT/Ref output wires explicitly |
| Wide input always zero/same | `$random(seed)` only fills lowest 32 bits | Use loop: `for(j=0;j<N/32;j++) data[j*32+:32]=$random(seed);` |
| `parameter` mismatch | RefModule has parameters; TB overrides them | Do NOT pass parameter overrides; use defaults (matches original test.sv) |
| Negedge design: output checks "lag" | Design captures at negedge, checking at posedge | This is correct — both DUT and RefModule have same lag. Not a bug. |

## 13. Key Differences Summary: RTLLM vs VerilogEval Enhanced TB

| Aspect | RTLLM | VerilogEval (Phase A) |
|---|---|---|
| Authoring workflow | Hand-written per-design under `RTLLM/**/testbench_enhanced.v` | Generated from `coevo/tb_gen/template.py`; staged in `coevo/tb_templates_generated/` |
| File extension | `.v` | `.sv` |
| Timescale | `1ns/1ps` | `1 ps/1 ps` |
| iverilog flag | (none) | `-g2012` |
| Golden model naming | Rename to `golden_*` | Embed `RefModule` verbatim |
| DUT module name | Design-specific | Always `TopModule` |
| DUT instance name | `uut` | `uut` |
| Ref instance name | `ref_model` | `fg_gold` |
| Compilation (enhanced) | `iverilog -o sim tb_enh.v candidate.v` | `iverilog -g2012 -o sim tb_enh.sv candidate.sv` |
| Compilation (original) | `iverilog -o sim tb.v candidate.v` | `iverilog -g2012 -o sim test.sv ref.sv candidate.sv` |
| Language | Verilog-2001 only | SystemVerilog allowed |
| Clock in TB | Only for sequential | Always (synchronization) |
| Scoring model | Discrete per-check (`[FORGE_CHECK N]`) | Continuous bucket monitor, weighted score pre-scaled to `TOTAL=10000` |
| Feedback style | `[FORGE_CHECK N] FAIL ...` lines | `[FORGE_BUCKET]` + `[FORGE_FIRSTFAIL]` + `[FORGE_SCORE_WEIGHTED]` |
| Parser path | `_parse_forge_output` Path A | `_parse_forge_output` Path B |
| Directory | Hierarchical per-design | Flat, all in one directory |
| Number of designs | 50 | 156 |
