# RTLLM 2.0 Benchmark Fix Log

**Scope:** 50 designs, compared against the original RTLLM (`~/RTLLM`). Fixes cover design descriptions, original testbenches, and verified reference RTL. All verified reference module names were normalized.

> **Verification:** all 50 modified references pass their original testbenches (iverilog: syntax 50/50, function 50/50).

### Contents

1. Design Description Fixes (14)
2. Original Testbench Fixes (11)
3. Verified Reference RTL Fixes (17)
4. Module Name Normalization

<br>

## Section 1: Design Description Fixes (14)

### 1. div_16bit
- **Path:** `RTLLM/Arithmetic/Divider/div_16bit/design_description.txt`
- **Priority:** MEDIUM
- **Issue:** "if the dividend bits are greater" used a strict comparison. A quotient bit is 1 when the partial remainder is greater than or equal to the divisor. The reference RTL uses `>=`.
- **Fix:** Changed "are greater" to "are greater than or equal to the divisor".

### 2. radix2_div
- **Path:** `RTLLM/Arithmetic/Divider/radix2_div/design_description.txt`
- **Priority:** HIGH
- **Issue:** Missing `res_ready` input description. Absolute value and negation steps were underspecified. `res_valid` behavior referenced an unspecified "consumed" condition instead of the ready handshake.
- **Fix:** Added `res_ready` description. Specified `dividend_abs_reg` and `neg_divisor_reg` computation via `always @(*)`, SR initialization, and the `res_valid`/`res_ready` handshake (both high clears `res_valid`).

### 3. multi_booth_8bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_booth_8bit/design_description.txt`
- **Priority:** HIGH
- **Issue:** Title named a "Radix-4 booth multiplier" but the algorithm is a shift-and-add (one bit per cycle, 16 iterations). Sensitivity list stated async reset, but the reference uses sync reset.
- **Fix:** Retitled to "8-bit signed multiplier using the shift-and-add algorithm". Changed sensitivity to posedge clk only. Removed Booth algorithm and Booth encoding references.

### 4. RAM
- **Path:** `RTLLM/Miscellaneous/RISC-V/RAM/design_description.txt`
- **Priority:** HIGH
- **Issue:** Formula `reg [DEPTH-1:0] RAM [2**WIDTH-1:0]` expands to 64x8 bits, contradicting the text (depth 8, width 6 bits). WIDTH and DEPTH were swapped.
- **Fix:** Changed formula to `reg [WIDTH-1:0] RAM [DEPTH-1:0]` and the text to "providing DEPTH memory locations, each with a width of WIDTH bits".

### 5. alu
- **Path:** `RTLLM/Miscellaneous/RISC-V/alu/design_description.txt`
- **Priority:** MEDIUM
- **Issue:** LUI was described as using the upper 16 bits of a. MIPS LUI uses the lower 16 bits. The flag and default outputs were described as `'z'` (high impedance), which is not synthesizable and not what the reference produces.
- **Fix:** Changed "upper 16 bits" to "lower 16 bits". Changed `'z'` outputs to `'0'`.

### 6. fixed_point_subtractor
- **Path:** `RTLLM/Arithmetic/Other/fixed_point_subtractor/design_description.txt`
- **Priority:** HIGH
- **Issue:** Same-sign subtraction claimed the result keeps the input sign, which is wrong when |b| > |a| (e.g. +3 minus +5 is -2). Different-sign subtraction made the sign depend on magnitude, but positive minus negative is always positive and negative minus positive is always negative.
- **Fix:** Same sign: added magnitude comparison; if |a| < |b|, magnitude is |b|-|a| and the sign flips. Different sign: result is always positive (a>0,b<0) or always negative (a<0,b>0).

### 7. sequence_detector
- **Path:** `RTLLM/Control/Finite State Machine/sequence_detector/design_description.txt`
- **Priority:** MEDIUM
- **Issue:** Port named `reset_n` in the spec but `rst_n` in the reference. Reset behavior said "When reset is high", contradicting the active-low `rst_n` used by the reference.
- **Fix:** Changed `reset_n` to `rst_n` and "When reset is high" to "When rst_n is low (active)".

### 8. up_down_counter
- **Path:** `RTLLM/Control/Counter/up_down_counter/design_description.txt`
- **Priority:** LOW
- **Issue:** "synchronous process triggered by the rising edge of clk" implies sync-only reset, but the reference uses async reset.
- **Fix:** Changed to "a process triggered by the rising edge of the clock signal (clk) or the rising edge of the reset signal".

### 9. barrel_shifter
- **Path:** `RTLLM/Memory/Shifter/barrel_shifter/design_description.txt`
- **Priority:** LOW
- **Issue:** "rotating bits" and "shifts or rotates" are inaccurate. The implementation only does logical right shift (fills with zeros).
- **Fix:** Changed "rotating" to "shifting" and "shifts or rotates" to "shifts".

### 10. asyn_fifo
- **Path:** `RTLLM/Memory/FIFO/asyn_fifo/design_description.txt`
- **Priority:** LOW
- **Issue:** "4-bit Gray code, depth 8, four-digit binary, lower three digits" contradicts DEPTH=16 (address 4 bits, pointers 5 bits).
- **Fix:** Changed to "5-bit Gray code", "depth 16", "five-digit binary", and "lower four digits".

### 11. freq_divbyeven
- **Path:** `RTLLM/Miscellaneous/Frequency divider/freq_divbyeven/design_description.txt`
- **Priority:** LOW
- **Issue:** Module name written as `freq_diveven`.
- **Fix:** Changed to `freq_divbyeven`.

### 12. pulse_detect
- **Path:** `RTLLM/Miscellaneous/Others/pulse_detect/design_description.txt`
- **Priority:** LOW
- **Issue:** Implied one clocked always block for both state and output. The given example (data_in=01010, data_out=00101) requires a combinational `data_out`; a registered output would lag one cycle.
- **Fix:** Clarified that state registers are clocked but `data_out` is combinational (same cycle as pulse completion).

### 13. traffic_light
- **Path:** `RTLLM/Miscellaneous/Others/traffic_light/design_description.txt`
- **Priority:** LOW
- **Issue:** "pass_request: Request signal for allowing vehicles to pass" is misleading. The signal is a pedestrian crossing request that shortens the green phase.
- **Fix:** Changed to "Pedestrian crossing request signal".

### 14. ROM
- **Path:** `RTLLM/Miscellaneous/RISC-V/ROM/design_description.txt`
- **Priority:** LOW
- **Issue:** Described preloading only locations 0 to 3, leaving the rest undefined.
- **Fix:** Specified preloading all 256 locations via a for loop with formula `mem[i] = {2{8'hA0 + i*8'h11}}`.

<br>

## Section 2: Original Testbench Fixes (11)

### 1. multi_pipe_4bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_pipe_4bit/testbench.v`
- **Priority:** HIGH
- **Issue:** A "without pipeline" check incremented `fail_count` when the output matched (correct), polluting the shared error counter.
- **Fix:** Removed the inverted check. The real check is correct and sufficient.

### 2. multi_pipe_8bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_pipe_8bit/testbench.v`
- **Priority:** HIGH
- **Issue:** A premature check incremented `error` when `mul_en_out` was high AND the output was correct.
- **Fix:** Removed the inverted check. The real check after waiting for `mul_en_out` is correct and sufficient.

### 3. fixed_point_adder
- **Path:** `RTLLM/Arithmetic/Other/fixed_point_adder/testbench.v`
- **Priority:** HIGH
- **Issue:** The reference model did raw binary add/sub on sign-magnitude values, letting the sign bit participate in the arithmetic (wrong result).
- **Fix:** Replaced with sign-magnitude addition: same sign adds magnitudes and keeps the sign; different sign subtracts the smaller magnitude and takes the larger operand's sign; zero result forces sign 0.

### 4. fixed_point_subtractor
- **Path:** `RTLLM/Arithmetic/Other/fixed_point_subtractor/testbench.v`
- **Priority:** HIGH
- **Issue:** Same root cause as the adder. Raw binary subtraction on full N-bit sign-magnitude values lost the sign information.
- **Fix:** Replaced with sign-magnitude subtraction: same sign compares magnitudes; different sign adds magnitudes; zero result forces sign 0.

### 5. edge_detect
- **Path:** `RTLLM/Miscellaneous/Others/edge_detect/testbench.v`
- **Priority:** HIGH
- **Issue:** Four checks used `&&` instead of `||`, so an error was flagged only when both outputs were wrong simultaneously.
- **Fix:** Changed all four `&&` to `||`.

### 6. traffic_light
- **Path:** `RTLLM/Miscellaneous/Others/traffic_light/testbench.v`
- **Priority:** HIGH
- **Issue:** `error = (clock!=(clock_cnt+3)) ? error : error+1` had two bugs. The ternary was inverted (counted error on a match), and the counter counts down so the expected value is `clock_cnt-3`.
- **Fix:** Changed to `error = (clock!=(clock_cnt-3)) ? error+1 : error`.

### 7. ring_counter
- **Path:** `RTLLM/Control/Counter/ring_counter/testbench.v`
- **Priority:** HIGH
- **Issue:** One always block printed "Failed" without counting errors, another unconditionally printed "Passed" at i==9, so every design passed. The data array also used aggregate initialization (not Verilog-2001).
- **Fix:** Added an error counter, moved array init into an initial block, merged the two blocks, counted mismatches, and made the verdict conditional on `error==0`.

### 8. sub_64bit
- **Path:** `RTLLM/Arithmetic/Substractor/sub_64bit/testbench.v`
- **Priority:** HIGH
- **Issue:** `(A - B < 0 && overflow !== 1)` with unsigned `reg [63:0]` A and B is always false, so overflow was never checked.
- **Fix:** Replaced with signed overflow detection `overflow !== ((A[63]!=B[63]) && (result[63]!=A[63]))`.

### 9. asyn_fifo
- **Path:** `RTLLM/Memory/FIFO/asyn_fifo/testbench.v`
- **Priority:** HIGH
- **Issue:** `break` inside a repeat loop is SystemVerilog, not valid in Verilog-2001, so the testbench failed to compile cleanly.
- **Fix:** Replaced with a named block and `disable write_loop`.

### 10. square_wave
- **Path:** `RTLLM/Miscellaneous/Signal generation/square_wave/testbench.v`
- **Priority:** MEDIUM
- **Issue:** The only check was for more than 8 consecutive ones. A stuck-at-0 output always passed.
- **Fix:** Added a `zeros_count` check (symmetric to `ones_count`) and a `toggle_count` check requiring at least 2 transitions.

### 11. clkgenerator
- **Path:** `RTLLM/Miscellaneous/RISC-V/clkgenerator/testbench.v`
- **Priority:** HIGH
- **Issue:** The testbench declared `clk_tb` as reg and drove it, but the DUT outputs the clock. There was no timescale, and sampling hit the toggle edge.
- **Fix:** Changed `clk_tb` to a wire driven by the DUT, added `` `timescale 1ns/1ps ``, and adjusted sampling to avoid the race.

<br>

## Section 3: Verified Reference RTL Fixes (17)

### 1. radix2_div
- **Path:** `RTLLM/Arithmetic/Divider/radix2_div/verified_radix2_div.v`
- **Priority:** HIGH
- **Issue:** The reference produced wrong quotient and remainder (e.g. dividend 156, divisor 10 gave faf1 instead of 00f6) and failed its own testbench.
- **Fix:** Reworked absolute value and negation into `always @(*)` registers, corrected sign handling and bit widths, reset `NEG_DIVISOR`, and regularized the SR shift and handshake. Now passes.

### 2. alu
- **Path:** `RTLLM/Miscellaneous/RISC-V/alu/verified_alu.v`
- **Priority:** HIGH
- **Issue:** `zero` compared the full 33-bit `res` (including bit 32). `carry`, `negative`, and `overflow` outputs were undriven. `res` default was `'z'`.
- **Fix:** Changed `zero` to `res[31:0]==0`. Added `carry`, `negative`, and `overflow` assigns. Changed `res` default to `32'b0`.

### 3. multi_16bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_16bit/verified_multi_16bit.v`
- **Priority:** MEDIUM
- **Issue:** `yout_r` was not cleared at i==0, so a residual value from the previous computation contaminated the result.
- **Fix:** Added `yout_r <= 32'h00000000` in the i==0 branch.

### 4. multi_pipe_8bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_pipe_8bit/verified_multi_pipe_8bit.v`
- **Priority:** HIGH
- **Issue:** The reset block set `mul_a_reg` twice; `mul_b_reg` was never reset.
- **Fix:** Changed the second `mul_a_reg <= 'd0` to `mul_b_reg <= 'd0`.

### 5. ring_counter
- **Path:** `RTLLM/Control/Counter/ring_counter/verified_ring_counter.v`
- **Priority:** HIGH
- **Issue:** `output reg [7:0] out` was driven by a continuous assign, which is a compile error in iverilog.
- **Fix:** Changed to `output [7:0] out`.

### 6. freq_divbyodd
- **Path:** `RTLLM/Miscellaneous/Frequency divider/freq_divbyodd/verified_freq_divbyodd.v`
- **Priority:** HIGH
- **Issue:** `reg clk_div` conflicted with `assign clk_div = ...`, a compile error.
- **Fix:** Removed the `reg clk_div` declaration (`clk_div` is already an output wire).

### 7. float_multi
- **Path:** `RTLLM/Arithmetic/Other/float_multi/verified_float_multi.v`
- **Priority:** HIGH
- **Issue:** Multiple `always @(counter)` blocks drove the same signals (not synthesizable). Special case results written at counter==1 were unconditionally overwritten by the normal path at counter==6.
- **Fix:** Merged all stages into one `always @(posedge clk)` with `case(counter)`. Added a `special_case` flag, set in each special branch and used to guard the output stage with `if (!special_case)`.

### 8. LIFObuffer
- **Path:** `RTLLM/Memory/LIFO/LIFObuffer/verified_LIFObuffer.v`
- **Priority:** MEDIUM
- **Issue:** On reset, `FULL` was never cleared, so a stale FULL=1 could persist.
- **Fix:** Added `FULL = 0` in the reset block.

### 9. multi_8bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_8bit/verified_multi_8bit.v`
- **Priority:** HIGH
- **Issue:** `for (int i = 0; ...)` uses SystemVerilog syntax, a compile error in Verilog-2001.
- **Fix:** Declared `integer i` and changed the loop to `for (i = 0; ...)`.

### 10. fixed_point_subtractor
- **Path:** `RTLLM/Arithmetic/Other/fixed_point_subtractor/verified_fixed_point_subtractor.v`
- **Priority:** HIGH
- **Issue:** Same-sign subtraction always kept a's sign, wrong when |b| > |a|. Different-sign branches had incorrect sign and zero handling.
- **Fix:** Same sign: compare magnitudes, subtract smaller from larger, flip sign when |a| < |b|, clear sign on zero. Different sign: result is always positive or always negative with a zero-magnitude check.

### 11. synchronizer
- **Path:** `RTLLM/Miscellaneous/Others/synchronizer/verified_synchronizer.v`
- **Priority:** MEDIUM
- **Issue:** The reset used `brstn` instead of `arstn` for `en_data_reg` (wrong reset domain). The original testbench did not expose it.
- **Fix:** Changed `if(!brstn)` to `if(!arstn)`.

### 12. RAM
- **Path:** `RTLLM/Miscellaneous/RISC-V/RAM/verified_RAM.v`
- **Priority:** MEDIUM
- **Issue:** Array declared `reg [7:0] RAM [11:0]` (8 wide, 12 deep), not matching the spec parameters WIDTH=6, DEPTH=8.
- **Fix:** Changed to `reg [5:0] ram_mem [7:0]` and renamed the array to avoid sharing the module name.

### 13. ROM
- **Path:** `RTLLM/Miscellaneous/RISC-V/ROM/verified_ROM.v`
- **Priority:** LOW
- **Issue:** Only locations 0 to 3 were initialized, leaving the rest undefined.
- **Fix:** Initialized all 256 locations with a for loop matching the spec formula.

### 14. fsm
- **Path:** `RTLLM/Control/Finite State Machine/fsm/verified_fsm.v`
- **Priority:** MEDIUM
- **Issue:** The next-state case had no default (risk of an inferred latch and synthesis failure). `MATCH` used non-blocking assignment inside a combinational block.
- **Fix:** Added `default: ST_nt = s0`. Changed `MATCH` to blocking assignment.

### 15. multi_booth_8bit
- **Path:** `RTLLM/Arithmetic/Multiplier/multi_booth_8bit/verified_multi_booth_8bit.v`
- **Priority:** LOW
- **Issue:** Sensitivity list used `posedge clk or posedge reset` (async), not matching the synchronous reset stated in the corrected spec.
- **Fix:** Changed to `posedge clk` only.

### 16. clkgenerator
- **Path:** `RTLLM/Miscellaneous/RISC-V/clkgenerator/verified_clkgenerator.v`
- **Priority:** LOW
- **Issue:** No timescale, needed for consistent clock generation timing with the testbench.
- **Fix:** Added `` `timescale 1ns/1ps `` at the top of the file.

### 17. accu
- **Path:** `RTLLM/Arithmetic/Accumulator/accu/verified_accu.v`
- **Priority:** MEDIUM
- **Issue:** `data_out` was updated every cycle with the running partial sum, exposing interim values on the output port. The spec states there is no output before four data_in values arrive.
- **Fix:** Moved accumulation to an internal `data_out_reg` and update `data_out` only at `end_cnt` with the final sum, so the output is stable and valid only on the `valid_out` cycle.

<br>

## Section 4: Module Name Normalization

### 1. Verified reference module names
- **Scope:** 33 `verified_*.v` files
- **Priority:** HIGH
- **Issue:** Original verified references were inconsistently named. Many declared `module verified_X` while testbenches instantiate the canonical name `X uut (...)`, so the reference and its testbench could not compile together. COEVO also embeds the reference as a golden model under the canonical name and synthesizes it for PPA.
- **Fix:** Normalized every `module verified_X` to `module X`. Two files and one directory were also renamed:

```text
verified_adder_64bit.v   ->  verified_adder_pipe_64bit.v
    (module verified_adder_64bit       -> adder_pipe_64bit)
verified_booth4_mul.v    ->  verified_multi_booth_8bit.v
    (module verified_multi_booth_8bit  -> multi_booth_8bit)
directory fixed_point_substractor      -> fixed_point_subtractor
```
