# VerilogEval 2.0 Benchmark Fix Log

**Scope:** 156 designs, compared against the original VerilogEval (`~/verilog-eval/dataset_spec-to-rtl`). Fixes cover prompts, reference RTL, and original testbenches.

> **Verification:** all 156 modified references pass their original testbenches (iverilog: syntax 156/156, function 156/156).

### Contents

1. Prompt (Specification) Fixes (9)
2. Reference RTL Synthesizability Fixes (8)
3. Original Testbench Fixes (2)

<br>

## Section 1: Prompt Fixes (9)

### 1. Prob099_m2014_q6c
- **Path:** `Prob099_m2014_q6c_prompt.txt`
- **Priority:** HIGH
- **Issue:** Text was corrupted ("The module shou module ment", duplicated lines, missing spaces) and named the outputs Y2 and Y4. The reference ports are Y1 and Y3 (corresponding to y[1] and y[3]).
- **Fix:** Rewrote the text cleanly and changed Y2/Y4 to Y1/Y3.

### 2. Prob155_lemmings4
- **Path:** `Prob155_lemmings4_prompt.txt`
- **Priority:** HIGH
- **Issue:** "falls for more than 20 clock cycles" did not match the reference boundary of 20 or more.
- **Fix:** Changed "more than 20" to "20 or more".

### 3. Prob136_m2014_q6
- **Path:** `Prob136_m2014_q6_prompt.txt`
- **Priority:** HIGH
- **Issue:** The reset was not specified, leaving polarity, timing, and target state ambiguous while the reference has a reset.
- **Fix:** Added "Reset is synchronous active-high and resets the FSM to state A".

### 4. Prob143_fsm_onehot
- **Path:** `Prob143_fsm_onehot_prompt.txt`
- **Priority:** MEDIUM
- **Issue:** The one-hot semantics for simultaneously active state bits were unstated.
- **Fix:** Added that `next_state[i]` is the logical OR of contributions from each active current-state bit. Also cleaned trailing whitespace.

### 5. Prob150_review2015_fsmonehot
- **Path:** `Prob150_review2015_fsmonehot_prompt.txt`
- **Priority:** MEDIUM
- **Issue:** The one-hot next-state derivation method was unstated.
- **Fix:** Added that each `next_state[i]` is the OR of all transitions entering state i, rather than a case on the current state.

### 6. Prob149_ece241_2013_q4
- **Path:** `Prob149_ece241_2013_q4_prompt.txt`
- **Priority:** MEDIUM
- **Issue:** The spec did not state that the FSM must track water level direction, which determines `dfr`.
- **Fix:** Added that the FSM must remember whether the water level is rising or falling.

### 7. Prob142_lemmings2
- **Path:** `Prob142_lemmings2_prompt.txt`
- **Priority:** LOW
- **Issue:** The Moore-machine requirement to encode walking direction in the state when falling was implicit.
- **Fix:** Added a note that the walking direction must be part of the state so it can resume after landing.

### 8. Prob152_lemmings3
- **Path:** `Prob152_lemmings3_prompt.txt`
- **Priority:** LOW
- **Issue:** Same implicit Moore-machine requirement as Prob142, also covering the digging state.
- **Fix:** Added a note that the walking direction must be part of the state when falling and digging.

### 9. Prob141_count_clock
- **Path:** `Prob141_count_clock_prompt.txt`
- **Priority:** LOW
- **Issue:** BCD increment semantics were not stated.
- **Fix:** Added a note: increment the low nibble; at `4'b1001` reset it to 0 and increment the high nibble.

<br>

## Section 2: Reference RTL Synthesizability Fixes (8)

### 1. Removed initial blocks
- **Paths:** `Prob034_dff8_ref.sv`, `Prob104_mt2015_muxdff_ref.sv`
- **Priority:** MEDIUM
- **Issue:** `initial q = 0` / `initial Q = 0` is not synthesizable. A real DFF powers up as X.
- **Fix:** Removed the initial blocks. The original testbench match formula `ref === (ref ^ dut ^ ref)` reduces to `ref===dut` when ref is known and is always true when ref is X, so a reference that powers up as X causes no false mismatch. Both functional and verification pass.

### 2. Added default case branches
- **Paths:** `Prob095_review2015_fsmshift_ref.sv`, `Prob096_review2015_fsmseq_ref.sv`, `Prob137_fsm_serial_ref.sv`, `Prob146_fsm_serialdata_ref.sv`, `Prob152_lemmings3_ref.sv`, `Prob155_lemmings4_ref.sv`
- **Priority:** MEDIUM
- **Issue:** Next-state case statements had no default, risking an inferred latch and Yosys synthesis failure.
- **Fix:** Added `default: next = <reset/idle state>` (B0, S, START, or WL). All reachable states were already covered, so behavior is unchanged.

<br>

## Section 3: Original Testbench Fixes (2)

### 1. Prob095_review2015_fsmshift
- **Path:** `Prob095_review2015_fsmshift_test.sv`
- **Priority:** MEDIUM
- **Issue:** `reset` was undefined at t=0, allowing X propagation on the first posedge.
- **Fix:** Added `reset = 1` at t=0.

### 2. Prob099_m2014_q6c
- **Path:** `Prob099_m2014_q6c_test.sv`
- **Priority:** HIGH
- **Issue:** The testbench used Y2 and Y4 for signals, port connections, error counters, dumpvars, and the match formula, but the reference ports are Y1 and Y3.
- **Fix:** Renamed all Y2/Y4 references to Y1/Y3.
