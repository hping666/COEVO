# RTLLM Testbench Enhancement Guide

> **⚠️ CRITICAL CONSTRAINT**: This task ONLY creates new files named `testbench_enhanced.v` in each design directory. Do **NOT** modify, rename, delete, or overwrite any existing files (`testbench.v`, `verified_*.v`, `design_description.txt`, `makefile`, or any other file). All temporary files generated during validation (e.g., compiled simulation binaries) must be cleaned up after use. If in doubt, do not touch any file that already exists.

## 1. Mission

For **every** design directory under `~/MAS4RTL/RTLLM/`, generate an enhanced testbench file named `testbench_enhanced.v`. This enhanced testbench must:

1. Provide a **fine-grained correctness score**: print `[FORGE_SCORE] X/Y` where X = passed checks, Y = total checks
2. Provide **per-check diagnostic output**: for each check, print pass/fail with expected vs actual values
3. **Significantly expand test coverage** beyond the original testbench using the verified reference design as a golden oracle
4. Be **fully self-contained** and runnable with iverilog without external data files (like `reference.dat`)
5. **Pass when run against the verified reference design** (this is the validation criterion)

## 2. Environment

- Conda environment: `PPA` (activate with `conda activate PPA`)
- Simulator: `iverilog` (Icarus Verilog), available in the PPA environment
- Run command: `iverilog -o sim_out testbench_enhanced.v verified_<design>.v && vvp sim_out`
- Project root: `~/MAS4RTL/`
- RTLLM dataset root: `~/MAS4RTL/RTLLM/`

## 3. RTLLM Directory Structure

```
RTLLM/
├── Arithmetic/
│   ├── <design_name>/
│   │   ├── design_description.txt    # Natural language spec
│   │   ├── testbench.v               # Original testbench
│   │   ├── verified_<design_name>.v  # Golden reference implementation
│   │   └── makefile                  # Build rules
│   └── ...
├── Control/
│   ├── Counter/
│   ├── Finite State Machine/
├── Memory/
│   ├── FIFO/
│   ├── LIFO/
│   ├── Shifter/
├── Miscellaneous/
│   ├── Frequency divider/
│   ├── Others/
│   ├── RISC-V/
│   │   ├── alu/
│   │   ├── clkgenerator/
│   │   ├── instr_reg/
│   │   └── pe/
│   └── Signal generation/
└── ...
```

Each design directory always contains:
- `verified_<name>.v` — functionally correct reference implementation (the golden oracle)
- `testbench.v` — original testbench (limited coverage, usually binary pass/fail)
- `design_description.txt` — natural language specification

## 4. Original Testbench Patterns (3 Types Observed)

You will encounter three common testbench patterns. Understanding them is critical for enhancement.

### Pattern A: Hardcoded Stimulus + Stored Expected Results (e.g., `accu`)

```verilog
// Fixed stimulus sequence
#(PERIOD) data_in = 8'd1; valid_in = 1;
#(PERIOD) data_in = 8'd2;
...
// Pre-stored expected results
reg [9:0] result [0:2];
initial begin result[0] = 9'd20; result[1] = 9'd114; result[2] = 9'd68; end
// Single error counter, binary output
if(error==0 && casenum==3) $display("Passed"); else $display("Error");
```

**Limitations**: Only 3 test cases, no per-case reporting, no corner cases.

### Pattern B: Random Stimulus + Inline Golden Computation (e.g., `adder_pipe_64bit`)

```verilog
repeat (100) begin
    PLUS_A = $random * $random;
    PLUS_B = $random * $random;
    ...
    error = ((PLUS_A + PLUS_B) == SUM_OUT) ? error : error + 1;
end
if (error == 0) $display("Passed");
```

**Limitations**: No per-check reporting, no corner cases (all random), no boundary values.

### Pattern C: External File + Enumerated Operations (e.g., `alu`)

```verilog
$readmemh("reference.dat", reference);
for(cnt=0; cnt<17; cnt=cnt+1) begin
    aluc = opcodes[cnt]; #5;
    error = error | (reference[cnt] != r);
end
```

**Limitations**: Depends on external file, only one input pair per operation, no edge cases, no per-check reporting.

## 5. Enhancement Strategy

For each design, the enhanced testbench must follow this architecture:

### 5.1 Overall Structure Template

```verilog
`timescale 1ns/1ps

module testbench_enhanced;

    // ============================================================
    // SECTION 1: Signal declarations and DUT instantiation
    // ============================================================
    // (Copy port declarations from the reference design's module header)
    // Instantiate DUT as: <module_name> uut (...);

    // ============================================================
    // SECTION 2: Clock and reset generation (if needed)
    // ============================================================
    // Standard clock generation for sequential designs
    // Reset sequence

    // ============================================================
    // SECTION 3: Test infrastructure
    // ============================================================
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;

    // ============================================================
    // SECTION 4: Check task definition
    // ============================================================
    // (See Section 5.2 below for the check task)

    // ============================================================
    // SECTION 5: Test cases
    // ============================================================
    // Group A: Original testbench cases (preserve existing coverage)
    // Group B: Boundary / corner cases
    // Group C: Randomized stress tests with inline golden computation
    // Group D: Special scenarios (reset behavior, enable toggling, etc.)

    // ============================================================
    // SECTION 6: Score reporting
    // ============================================================
    // (See Section 5.4 below for the reporting block)

endmodule
```

### 5.2 The Check Task (CRITICAL — use this exact format)

For **combinational** designs:

```verilog
task check;
    input integer id;
    input [WIDTH-1:0] expected;  // adjust WIDTH to match output
    input [WIDTH-1:0] actual;
    input [8*64-1:0] description;  // string description of the check
    begin
        total_checks = total_checks + 1;
        if (expected === actual) begin
            passed_checks = passed_checks + 1;
            // Optionally print passing checks too (commented out to reduce noise):
            // $display("[FORGE_CHECK %0d] PASS | %0s | expected=%h got=%h", id, description, expected, actual);
        end else begin
            failed_checks = failed_checks + 1;
            $display("[FORGE_CHECK %0d] FAIL | %0s | expected=%h got=%h | time=%0t",
                     id, description, expected, actual, $time);
        end
    end
endtask
```

For designs with **multiple outputs**, create one check call per output signal, or a combined check:

```verilog
task check_all_outputs;
    input integer id;
    input [31:0] exp_r;
    input [31:0] act_r;
    input exp_zero;
    input act_zero;
    input exp_flag;
    input act_flag;
    input [8*64-1:0] description;
    begin
        total_checks = total_checks + 1;
        if (exp_r === act_r && exp_zero === act_zero && exp_flag === act_flag) begin
            passed_checks = passed_checks + 1;
        end else begin
            failed_checks = failed_checks + 1;
            $display("[FORGE_CHECK %0d] FAIL | %0s | time=%0t", id, description, $time);
            if (exp_r !== act_r)
                $display("  -> r: expected=%h got=%h", exp_r, act_r);
            if (exp_zero !== act_zero)
                $display("  -> zero: expected=%b got=%b", exp_zero, act_zero);
            if (exp_flag !== act_flag)
                $display("  -> flag: expected=%b got=%b", exp_flag, act_flag);
        end
    end
endtask
```

### 5.3 Golden Output Generation Strategy

**CRITICAL RULE**: Never hardcode expected outputs yourself. Always compute them using one of these methods:

**Method 1 — Inline Verilog Golden Model (PREFERRED for combinational designs)**:

Instantiate the reference design IN the testbench as the golden model, alongside the DUT:

```verilog
// This is the key technique: run reference and DUT in parallel
// The reference module is from verified_<design>.v — it IS the golden oracle

// Instantiate DUT (this is the design under test — to be replaced by candidate)
<module_name> uut (
    .clk(clk), .rst_n(rst_n), .data_in(data_in), ...
    .data_out(dut_out), .valid_out(dut_valid)
);

// Instantiate golden reference (always correct)
<module_name> golden_ref (
    .clk(clk), .rst_n(rst_n), .data_in(data_in), ...
    .data_out(ref_out), .valid_out(ref_valid)
);

// Compare outputs
always @(posedge clk) begin
    if (check_enable) begin
        check_id = check_id + 1;
        check(check_id, ref_out, dut_out, "functional check");
    end
end
```

**IMPORTANT**: When using this dual-instantiation method, the enhanced testbench will be compiled with the DUT file (candidate code), NOT with the reference file. So the golden reference module must be **embedded directly in the testbench file** with a renamed module name to avoid conflicts. See Section 5.5.

**Method 2 — Behavioral Golden Computation (for simple operations)**:

For simple arithmetic/logic where the golden output is trivially computable:

```verilog
// For an adder:
wire [64:0] golden_sum = adda + addb;
// Then compare: check(id, golden_sum, dut_result, "addition check");
```

Only use this for operations where the behavioral Verilog expression is unambiguously correct (addition, subtraction, bitwise logic, shifts, comparisons). Do NOT use this for complex sequential logic.

### 5.4 Score Reporting Block (CRITICAL — use this exact format)

Place this at the very end of the testbench, just before `$finish`:

```verilog
// ============================================================
// FORGE Score Report
// ============================================================
$display("===================================================");
$display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d", total_checks, passed_checks, failed_checks);
if (failed_checks == 0)
    $display("[FORGE_RESULT] STATUS=PASS SCORE=%0d/%0d", passed_checks, total_checks);
else
    $display("[FORGE_RESULT] STATUS=FAIL SCORE=%0d/%0d", passed_checks, total_checks);
$display("===================================================");
$finish;
```

The downstream FORGE system will parse the simulation log for `[FORGE_RESULT]` lines to extract the score.

### 5.5 Embedding the Reference Design as Golden Model

Since the testbench will be compiled with the DUT (candidate) code that uses the SAME module name as the reference, you must embed a renamed copy of the reference design directly in the testbench file.

**Procedure**:

1. Read `verified_<design>.v`
2. Copy the entire module
3. Rename the module to `golden_<design>` (e.g., `golden_accu`, `golden_alu`)
4. Place it at the bottom of `testbench_enhanced.v`
5. Instantiate it as `golden_<design>` in the testbench

Example:

```verilog
// At the bottom of testbench_enhanced.v:

// ============================================================
// Golden Reference Model (copied from verified_<design>.v, renamed)
// ============================================================
module golden_accu(
    input clk, input rst_n, input [7:0] data_in, input valid_in,
    output reg valid_out, output reg [9:0] data_out
);
    // ... exact copy of verified_accu.v internals ...
endmodule
```

**IMPORTANT**: If the reference design uses `$readmemh` or other external file dependencies, those must be resolved (inline the data or remove the dependency).

### 5.6 Test Case Categories

For every design, generate test cases in these categories:

#### Group A — Original Test Reproduction (minimum 3-5 cases)
Reproduce the exact stimulus from the original `testbench.v` to ensure backward compatibility. These should all pass on the reference design.

#### Group B — Boundary and Corner Cases (minimum 10-20 cases)
Based on the design type, systematically test:

| Design Type | Corner Cases to Include |
|---|---|
| Arithmetic (adders, multipliers) | All-zeros, all-ones, max positive, max negative (if signed), overflow boundary, carry propagation (e.g., 0xFFFF + 1), alternating bits (0xAAAA, 0x5555) |
| Counters | Reset during count, count to max then wrap, enable/disable toggling, back-to-back operations |
| FSMs | All state transitions, invalid inputs in each state, reset from each state, stuck-in-state detection |
| Memory (FIFO/LIFO/RAM) | Empty read, full write, simultaneous read/write, fill-then-drain, single element, reset while non-empty |
| Shifters | Shift by 0, shift by max, shift by 1, shift of all-ones, shift of single-bit |
| ALU | Each opcode with zero operands, max operands, signed boundary values, shift amounts of 0 and 31 |
| Signal generators | Reset behavior, boundary values of counters/waveforms, frequency edge cases |
| RISC-V modules | Each instruction type, pipeline hazards (if applicable), register file boundaries |

#### Group C — Randomized Stress Tests (minimum 20-50 cases)
Use `$random` with a fixed seed for reproducibility:

```verilog
// Fixed seed for reproducibility
integer seed = 42;
integer i;
initial begin
    for (i = 0; i < 50; i = i + 1) begin
        input_a = $random(seed);
        input_b = $random(seed);
        // Apply stimulus...
        // Wait for output...
        // Check against golden model...
    end
end
```

#### Group D — Protocol/Timing Tests (minimum 5-10 cases, for sequential designs)
- Reset during operation (not just at start)
- Back-to-back valid transactions
- Idle periods between transactions
- Enable toggling mid-operation
- Multiple consecutive resets

### 5.7 Minimum Check Count Targets

| Design Complexity | Minimum total_checks |
|---|---|
| Simple combinational (mux, basic logic) | 50 |
| Arithmetic (adders, multipliers) | 80 |
| Sequential (counters, accumulators) | 60 |
| FSMs | 40 (but cover all transitions) |
| Memory (FIFO, LIFO, RAM, ROM) | 80 |
| Complex (ALU, PE, processors) | 100 |

## 6. Step-by-Step Workflow for Each Design

For each design directory, follow these steps:

### Step 1: Analyze
```bash
# Read the spec
cat design_description.txt

# Read the reference design to understand the interface and behavior
cat verified_<design>.v

# Read the original testbench to understand existing coverage
cat testbench.v
```

Identify:
- Module name and full port list (names, widths, directions)
- Whether it's combinational or sequential (has clock/reset?)
- Key functional behavior from the spec
- What the original testbench covers and what it misses

### Step 2: Generate `testbench_enhanced.v`

Follow the template in Section 5.1. Key decisions:
- If combinational: use Method 1 (dual instantiation) or Method 2 (behavioral golden)
- If sequential: use Method 1 (dual instantiation with embedded golden model)
- If the reference design has external file dependencies: resolve them by inlining

### Step 3: Validate

```bash
conda activate PPA

# Test 1: Compile and run with the reference design (MUST pass with 100% score)
cd ~/MAS4RTL/RTLLM/<category>/<design>/
iverilog -o test_enhanced testbench_enhanced.v verified_<design>.v 2>&1
vvp test_enhanced 2>&1

# Verify the output contains:
# [FORGE_RESULT] STATUS=PASS SCORE=<N>/<N>
# where the two numbers are equal (100% pass)
```

**If the enhanced testbench does NOT achieve 100% pass with the reference design, there is a bug in the testbench — fix it before moving on.**

### Step 4: Verify original testbench still works
```bash
# Sanity check: original testbench should also pass with reference
iverilog -o test_orig testbench.v verified_<design>.v 2>&1
vvp test_orig 2>&1
# Should print "Passed" or equivalent
```

## 7. Critical Rules and Pitfalls

### DO:
- Always embed a renamed copy of the golden reference module inside `testbench_enhanced.v`
- Always use `===` (case equality) for comparisons, not `==`, to handle X/Z values
- Always include `$finish` at the end
- Always use `timescale 1ns/1ps` at the top
- Always validate against the reference design before finalizing
- Use fixed random seeds for reproducibility
- Handle both posedge and negedge reset conventions (check the reference design)
- Wait adequate settling time after stimulus before checking outputs (especially for sequential)
- Add `#1` or small delays after clock edges before checking combinational outputs

### DO NOT:
- Never hardcode expected output values by manual computation — always derive from golden model
- Never use `$readmemh` or external files — everything must be self-contained in one `.v` file
- Never modify the DUT module interface (port names, widths) — the testbench must work with any design that implements the same interface
- Never use SystemVerilog syntax (keep to Verilog-2001 for iverilog compatibility)
- Never use `$urandom` (not supported in iverilog) — use `$random` instead
- Never create infinite loops without timeout — always add a watchdog: `initial begin #1000000; $display("[FORGE_RESULT] TIMEOUT"); $finish; end`
- Never have the total simulation time exceed 10ms (10,000,000 ns) — add watchdog accordingly

### Special Handling:
- **Designs with `$readmemh`**: If the reference design reads from a file, the golden model embedded in the testbench must also have access. Either inline the data as `initial begin mem[0]=...; mem[1]=...; end` or ensure the file path is correct.
- **Parameterized designs**: Copy all parameters from the reference design to the golden model.
- **Multi-module designs**: If the reference design instantiates sub-modules, all sub-modules must also be copied (renamed if they conflict with the DUT's sub-modules). In practice, if this gets too complex, fall back to Method 2 (behavioral golden computation) for the specific outputs.
- **Asynchronous reset vs synchronous reset**: Check the reference design's always block sensitivity list. `always @(posedge clk or negedge rst_n)` = async active-low reset. Match this in your golden model.

## 8. Output Parsing Specification

The FORGE system will parse simulation stdout for these patterns:

```
[FORGE_CHECK <id>] PASS | <description> | ...      → individual check passed
[FORGE_CHECK <id>] FAIL | <description> | ...      → individual check failed (with details)
[FORGE_RESULT] TOTAL=<N> PASSED=<M> FAILED=<K>     → summary counts
[FORGE_RESULT] STATUS=PASS|FAIL SCORE=<M>/<N>       → final verdict and score
[FORGE_RESULT] TIMEOUT                               → simulation hung
```

The correctness score used by FORGE is: `score = M / N` (float in [0.0, 1.0]).

## 9. Complete Example: Enhanced Testbench for `accu`

Below is a complete example showing how to enhance the `accu` testbench. Use this as a reference for style and structure.

```verilog
`timescale 1ns/1ps

module testbench_enhanced;

    // ============================================================
    // Parameters and Signal Declarations
    // ============================================================
    parameter PERIOD = 10;

    reg clk;
    reg rst_n;
    reg [7:0] data_in;
    reg valid_in;

    // DUT outputs
    wire valid_out_dut;
    wire [9:0] data_out_dut;

    // Golden reference outputs
    wire valid_out_ref;
    wire [9:0] data_out_ref;

    // ============================================================
    // Test Infrastructure
    // ============================================================
    integer total_checks = 0;
    integer passed_checks = 0;
    integer failed_checks = 0;
    integer check_id = 0;
    integer i;

    // ============================================================
    // Clock Generation
    // ============================================================
    initial clk = 0;
    always #(PERIOD/2) clk = ~clk;

    // ============================================================
    // DUT Instantiation (will be replaced by candidate design)
    // ============================================================
    accu uut (
        .clk(clk), .rst_n(rst_n),
        .data_in(data_in), .valid_in(valid_in),
        .valid_out(valid_out_dut), .data_out(data_out_dut)
    );

    // ============================================================
    // Golden Reference Instantiation
    // ============================================================
    golden_accu ref_model (
        .clk(clk), .rst_n(rst_n),
        .data_in(data_in), .valid_in(valid_in),
        .valid_out(valid_out_ref), .data_out(data_out_ref)
    );

    // ============================================================
    // Check Task
    // ============================================================
    task check_outputs;
        input integer id;
        input [8*64-1:0] desc;
        begin
            total_checks = total_checks + 1;
            if (valid_out_dut === valid_out_ref && data_out_dut === data_out_ref) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                $display("[FORGE_CHECK %0d] FAIL | %0s | time=%0t", id, desc, $time);
                if (valid_out_dut !== valid_out_ref)
                    $display("  -> valid_out: expected=%b got=%b", valid_out_ref, valid_out_dut);
                if (data_out_dut !== data_out_ref)
                    $display("  -> data_out: expected=%0d got=%0d", data_out_ref, data_out_dut);
            end
        end
    endtask

    // ============================================================
    // Watchdog Timer
    // ============================================================
    initial begin
        #5000000;
        $display("[FORGE_RESULT] TIMEOUT");
        $finish;
    end

    // ============================================================
    // Test Sequence
    // ============================================================
    integer seed = 42;
    reg [7:0] rand_val;

    initial begin
        // ---- Reset ----
        rst_n = 0;
        data_in = 0;
        valid_in = 0;
        #(PERIOD * 2);
        rst_n = 1;
        #(PERIOD);

        // ---- Group A: Original testbench cases ----
        // Sequence 1: {1, 2, 3, 14} -> sum = 20
        @(posedge clk); #1;
        data_in = 8'd1; valid_in = 1;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq1_cycle1");
        data_in = 8'd2;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq1_cycle2");
        data_in = 8'd3;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq1_cycle3");
        data_in = 8'd14;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq1_cycle4_expect_valid");

        // Sequence 2: {5, 2, 103, 4} -> sum = 114
        data_in = 8'd5;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq2_cycle1");
        data_in = 8'd2;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq2_cycle2");
        data_in = 8'd103;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq2_cycle3");
        data_in = 8'd4;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq2_cycle4_expect_valid");

        // Sequence 3: {5, 6, 3, 54} -> sum = 68
        data_in = 8'd5;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq3_cycle1");
        data_in = 8'd6;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq3_cycle2");
        data_in = 8'd3;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq3_cycle3");
        data_in = 8'd54;
        @(posedge clk); #1;
        check_id = check_id + 1; check_outputs(check_id, "orig_seq3_cycle4_expect_valid");

        // ---- Group B: Boundary cases ----
        // All zeros
        data_in = 8'd0; valid_in = 1;
        repeat(4) begin
            @(posedge clk); #1;
            check_id = check_id + 1; check_outputs(check_id, "boundary_all_zeros");
        end

        // All max (255)
        data_in = 8'd255;
        repeat(4) begin
            @(posedge clk); #1;
            check_id = check_id + 1; check_outputs(check_id, "boundary_all_max");
        end

        // Mixed: {0, 255, 0, 255}
        data_in = 8'd0;   @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "boundary_mixed_0");
        data_in = 8'd255;  @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "boundary_mixed_255");
        data_in = 8'd0;   @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "boundary_mixed_0b");
        data_in = 8'd255;  @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "boundary_mixed_255b");

        // Single value repeated: {128, 128, 128, 128}
        data_in = 8'd128;
        repeat(4) begin
            @(posedge clk); #1;
            check_id = check_id + 1; check_outputs(check_id, "boundary_repeated_128");
        end

        // ---- Group C: Randomized stress test ----
        for (i = 0; i < 10; i = i + 1) begin
            // Each iteration is a group of 4 values
            rand_val = $random(seed); data_in = rand_val;
            @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "random_grp");
            rand_val = $random(seed); data_in = rand_val;
            @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "random_grp");
            rand_val = $random(seed); data_in = rand_val;
            @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "random_grp");
            rand_val = $random(seed); data_in = rand_val;
            @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "random_grp");
        end

        // ---- Group D: Protocol / timing tests ----
        // Test: valid_in toggling (deassert mid-sequence)
        valid_in = 1; data_in = 8'd10;
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_on1");
        data_in = 8'd20;
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_on2");
        valid_in = 0;  // Deassert valid
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_off");
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_off2");
        valid_in = 1; data_in = 8'd30;  // Resume
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_resume1");
        data_in = 8'd40;
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "valid_toggle_resume2");

        // Test: Reset mid-operation
        valid_in = 1; data_in = 8'd50;
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "reset_mid_1");
        data_in = 8'd60;
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "reset_mid_2");
        rst_n = 0;  // Assert reset
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "reset_asserted");
        @(posedge clk); #1;
        rst_n = 1;  // Deassert reset
        @(posedge clk); #1; check_id = check_id+1; check_outputs(check_id, "post_reset");

        // Resume normal operation after reset
        valid_in = 1; data_in = 8'd1;
        repeat(4) begin
            @(posedge clk); #1;
            check_id = check_id + 1; check_outputs(check_id, "post_reset_normal");
            data_in = data_in + 1;
        end

        // Wait a few more cycles
        repeat(5) begin
            @(posedge clk); #1;
            check_id = check_id + 1; check_outputs(check_id, "final_drain");
        end
        valid_in = 0;
        repeat(3) @(posedge clk);

        // ============================================================
        // FORGE Score Report
        // ============================================================
        $display("===================================================");
        $display("[FORGE_RESULT] TOTAL=%0d PASSED=%0d FAILED=%0d", total_checks, passed_checks, failed_checks);
        if (failed_checks == 0)
            $display("[FORGE_RESULT] STATUS=PASS SCORE=%0d/%0d", passed_checks, total_checks);
        else
            $display("[FORGE_RESULT] STATUS=FAIL SCORE=%0d/%0d", passed_checks, total_checks);
        $display("===================================================");
        $finish;
    end

endmodule

// ============================================================
// Golden Reference Model (copied from verified_accu.v, renamed)
// ============================================================
module golden_accu(
    input               clk,
    input               rst_n,
    input       [7:0]   data_in,
    input               valid_in,
    output  reg         valid_out,
    output  reg [9:0]   data_out
);
    // ... (paste exact copy of verified_accu.v internals here) ...
endmodule
```

## 10. Batch Processing Approach

Process all designs systematically:

```bash
# 1. First, discover all design directories
find ~/MAS4RTL/RTLLM -name "verified_*.v" -exec dirname {} \; | sort | uniq > /tmp/design_dirs.txt

# 2. For each directory, generate testbench_enhanced.v

# 3. After generating, validate ALL enhanced testbenches:
while read dir; do
    design=$(basename "$dir")
    ref_file=$(ls "$dir"/verified_*.v 2>/dev/null | head -1)
    if [ -z "$ref_file" ]; then
        echo "SKIP: $dir (no reference found)"
        continue
    fi
    cd "$dir"
    iverilog -o test_enh testbench_enhanced.v "$ref_file" 2>compile_err.txt
    if [ $? -ne 0 ]; then
        echo "COMPILE_FAIL: $dir"
        cat compile_err.txt
        continue
    fi
    result=$(vvp test_enh 2>&1)
    if echo "$result" | grep -q "STATUS=PASS"; then
        score=$(echo "$result" | grep "FORGE_RESULT.*SCORE" | tail -1)
        echo "PASS: $dir | $score"
    else
        echo "FAIL: $dir"
        echo "$result" | grep "FORGE"
    fi
    rm -f test_enh compile_err.txt
done < /tmp/design_dirs.txt
```

## 11. Checklist Before Marking a Design as Done

For each design, verify:

- [ ] `testbench_enhanced.v` exists in the design directory
- [ ] Compiles without errors: `iverilog -o test testbench_enhanced.v verified_<design>.v`
- [ ] Runs and produces `[FORGE_RESULT]` output
- [ ] Achieves `STATUS=PASS` with 100% score when tested against the reference design
- [ ] Contains at least the minimum number of checks for the design complexity
- [ ] Covers all 4 test groups (A: original, B: boundary, C: random, D: protocol/timing)
- [ ] Golden model is embedded (renamed) inside the testbench file
- [ ] No external file dependencies (`$readmemh`, etc.)
- [ ] Has a watchdog timer
- [ ] Uses `===` for comparisons (not `==`)

## 12. Troubleshooting Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `Module xxx already defined` | DUT and golden model have same module name | Rename golden model to `golden_xxx` |
| `Unknown module type` | Sub-module not included | Copy all sub-modules into testbench with renamed names |
| Score < 100% on reference design | Bug in testbench, not in DUT | Check timing: add delays after stimulus, check reset polarity |
| `$random` not working | iverilog seed issue | Use `$random(seed)` with explicit integer seed variable |
| X/Z values in comparison | Signals not initialized | Ensure proper reset sequence; use `===` not `==` |
| Simulation hangs | No `$finish` or infinite wait | Ensure watchdog timer is present; check for blocking waits on signals that may never toggle |
| `Port size mismatch` | Wrong width in testbench port | Cross-check with the module header in `verified_<design>.v` |