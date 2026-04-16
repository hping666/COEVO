import re
import os

SYSTEM_MESSAGE = """You are an expert Verilog RTL hardware designer.
You must respond with exactly one complete, synthesizable Verilog module.
Format your response as:
<thought>Your design strategy explanation here</thought>
<code>
```verilog
// Your complete Verilog module here
```
</code>
Important: Generate ONLY standard Verilog-2001. No SystemVerilog.

Synthesis rules (MUST follow to ensure the design can be synthesized):
- Each reg/wire must be driven by exactly ONE always block or assign. Never drive the same signal from multiple always blocks.
- Do not use === or !== (four-state comparison). Use == and != only.
- Do not use initial blocks for logic initialization; they are not synthesizable. Use reset logic instead.
- Ensure all branches of combinational always blocks assign all outputs to avoid inferred latches.
- Do not use real-number types or time-related constructs (#delay) in synthesizable code."""


VERILOGEVAL_SYSTEM_MESSAGE = """You are an expert SystemVerilog RTL hardware designer.
You must respond with exactly one complete, synthesizable SystemVerilog module.
Format your response as:
<thought>Your design strategy explanation here</thought>
<code>
```systemverilog
// Your complete SystemVerilog module here
```
</code>
Important: The module MUST be named exactly as specified by the interface (typically `TopModule`). Use SystemVerilog (IEEE 1800) — constructs such as `always_comb`, `always_ff`, `logic`, `typedef`, packed structs are allowed.

Synthesis rules (MUST follow to ensure the design can be synthesized):
- Each reg/wire/logic must be driven by exactly ONE always block or assign. Never drive the same signal from multiple always blocks.
- Do not use === or !== (four-state comparison). Use == and != only.
- Do not use initial blocks for logic initialization; they are not synthesizable. Use reset logic instead.
- Every combinational always block (`always_comb` / `always @*`) must assign all its outputs in every branch; include a `default` clause in every `case` statement to avoid inferred latches and Yosys synthesis failures.
- Do not use real-number types or time-related constructs (#delay) in synthesizable code.

Specification fidelity rules (MUST follow to match the reference behavior exactly):
- Reset style: if the specification explicitly says "synchronous" reset, write `always_ff @(posedge clk) if (reset) ... else ...;`. Do NOT use `always_ff @(posedge clk or posedge reset)` or `always_ff @(posedge clk or negedge resetn)`. If the specification explicitly says "asynchronous", use the async form. If the specification does not mention reset style, default to synchronous reset. Always honor the exact polarity stated (active-high reset vs active-low resetn).
- Do not add reset, clear, or initialization logic that the specification does not request. In particular, never add a negedge-clock branch to clear a register unless the specification explicitly describes such behavior. Never add an extra `always_ff` block whose only purpose is to clear a signal that another always_ff block already drives.
- For edge-detection, sticky-bit, or accumulator registers, prefer a single-expression non-blocking assignment such as `out <= out | (~in & prev_in);` over a for-loop with conditional NBA assignments. The single-expression form is race-free under simulator scheduler ordering and matches the reference model's coding convention."""

STRATEGY_DESCRIPTIONS = {
    "behavioral": "Use behavioral Verilog (always blocks, if/else, case statements) for clarity and correctness.",
    "structural": "Use structural decomposition with explicit sub-modules or gate-level instantiations.",
    "pipeline": "Use pipeline stages with registers to improve throughput and reduce critical path.",
    "resource_shared": "Share arithmetic/logic resources across clock cycles to minimize area.",
    "fsm_minimized": "Use a minimal FSM with optimized state encoding.",
}


def extract_module_header(design_dir: str) -> str:
    """Extract module header from testbench_enhanced.v DUT instantiation."""
    tb_path = os.path.join(design_dir, "testbench_enhanced.v")
    if not os.path.exists(tb_path):
        return ""
    with open(tb_path) as f:
        tb_text = f.read()
    return _parse_dut_instantiation(tb_text)


def _parse_dut_instantiation(tb_text: str) -> str:
    """Parse DUT instantiation to reconstruct module header."""
    # Handle parameterized: module_name #(...) uut ( .port(sig), ... );
    param_match = re.search(r'(\w+)\s+#\s*\((.*?)\)\s*uut\s*\((.*?)\);', tb_text, re.DOTALL)
    if param_match:
        module_name = param_match.group(1)
        param_text = param_match.group(2)
        port_text = param_match.group(3)

        # Extract parameter mapping: .mod_param(tb_param)
        param_pairs = re.findall(r'\.(\w+)\s*\((\w+)\)', param_text)
        tb_to_mod = {tb: mod for mod, tb in param_pairs}

        # Build parameter declarations with defaults from testbench
        param_lines = []
        for mod_param, tb_param in param_pairs:
            default = _find_param_default(tb_text, tb_param)
            if default:
                param_lines.append(f"    parameter {mod_param} = {default}")
            else:
                param_lines.append(f"    parameter {mod_param}")

        # Extract ports with parameterized widths
        ports = re.findall(r'\.(\w+)\s*\((\w+)\)', port_text)
        port_lines = []
        for port_name, sig_name in ports:
            direction, width = _infer_port_info(tb_text, sig_name, port_name)
            width = _replace_param_names(width, tb_to_mod)
            if width and width != "[0:0]":
                port_lines.append(f"    {direction} {width} {port_name}")
            else:
                port_lines.append(f"    {direction} {port_name}")

        header = f"module {module_name} #(\n" + ",\n".join(param_lines) + "\n) (\n" + ",\n".join(port_lines) + "\n);"
        return header

    # Non-parameterized: module_name uut ( .port(sig), ... );
    m = re.search(r'(\w+)\s+uut\s*\((.*?)\);', tb_text, re.DOTALL)
    if not m:
        return ""

    module_name = m.group(1)
    port_text = m.group(2)

    # Extract port connections: .port_name(signal_name)
    ports = re.findall(r'\.(\w+)\s*\((\w+)\)', port_text)

    # Infer port directions/widths from signal declarations
    port_lines = []
    for port_name, sig_name in ports:
        direction, width = _infer_port_info(tb_text, sig_name, port_name)
        if width and width != "[0:0]":
            port_lines.append(f"    {direction} {width} {port_name}")
        else:
            port_lines.append(f"    {direction} {port_name}")

    header = f"module {module_name} (\n" + ",\n".join(port_lines) + "\n);"
    return header


def _find_param_default(tb_text: str, param_name: str) -> str:
    """Find default value for a parameter in testbench."""
    m = re.search(rf'parameter\s+{re.escape(param_name)}\s*=\s*([^;,\s]+)', tb_text)
    return m.group(1) if m else ""


def _replace_param_names(width: str, tb_to_mod: dict) -> str:
    """Replace testbench parameter names with module parameter names in width expression."""
    if not width or not tb_to_mod:
        return width
    for tb_name, mod_name in tb_to_mod.items():
        if tb_name != mod_name:
            width = re.sub(rf'\b{re.escape(tb_name)}\b', mod_name, width)
    return width


def _infer_port_info(tb_text: str, sig_name: str, port_name: str) -> tuple:
    """Infer direction and width from testbench signal declarations."""
    # Scan each line for reg/wire declarations containing the signal name
    for line in tb_text.splitlines():
        stripped = line.strip().rstrip(';').strip()
        # Match: reg [width] sig1, sig2, ... or reg sig1, sig2, ...
        if re.match(r'reg\b', stripped):
            # Check if sig_name is in this declaration
            if re.search(rf'\b{re.escape(sig_name)}\b', stripped):
                width = _extract_width(stripped)
                return ("input", width)
        elif re.match(r'wire\b', stripped):
            if re.search(rf'\b{re.escape(sig_name)}\b', stripped):
                width = _extract_width(stripped)
                return ("output", width)

    # Default: guess from common names
    if port_name in ('clk', 'clock', 'CLK', 'rst', 'rst_n', 'reset', 'en', 'enable',
                      'wclk', 'rclk', 'wrstn', 'rrstn'):
        return ("input", "")
    return ("output", "")


def _extract_width(decl_line: str) -> str:
    """Extract width specifier like [7:0] or [WIDTH-1:0] from a declaration line."""
    m = re.search(r'\[([^\]]+)\]', decl_line)
    if not m:
        return ""
    return f"[{m.group(1).strip()}]"


# ----------------------------------------------------------------------------
# Active system message: defaults to the RTLLM SYSTEM_MESSAGE so unchanged
# RTLLM behavior is preserved. CoevoEvolution sets this from its adapter
# before running, so the VerilogEval adapter can install its own SV-specific
# system message without touching every prompt builder.
# ----------------------------------------------------------------------------
_ACTIVE_SYSTEM_MESSAGE: str = SYSTEM_MESSAGE


def set_active_system_message(message: str) -> None:
    """Install the system message used by all subsequent build_* prompts."""
    global _ACTIVE_SYSTEM_MESSAGE
    if message:
        _ACTIVE_SYSTEM_MESSAGE = message


def build_system_message() -> dict:
    return {"role": "system", "content": _ACTIVE_SYSTEM_MESSAGE}


def build_initial_generation_prompt(spec: str, module_header: str, strategy: str,
                                     memory_context: str = "") -> list:
    desc = STRATEGY_DESCRIPTIONS.get(strategy, strategy)
    user_msg = f"""Implement the following hardware design using a {strategy} approach.
{desc}

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

{memory_context}

Remember: Generate ONLY standard Verilog-2001. The module header above must be used exactly."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_fix_prompt(parent, spec: str, module_header: str,
                     memory_context: str = "") -> list:
    user_msg = f"""The following design has functional errors. Fix the specific failing test cases described in the feedback. Preserve the overall design architecture.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Design Strategy
{parent.thought}

## Current Code
```verilog
{parent.code}
```

## Error Feedback (failing test cases)
{parent.error_feedback}

{memory_context}

Fix ONLY the failing test cases. Do not rewrite the entire design."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_repair_prompt(parent, spec: str, module_header: str,
                        memory_context: str = "") -> list:
    """Unified repair prompt: handles functional errors, synthesis errors, or both."""
    feedback_sections = []

    if parent.error_feedback:
        feedback_sections.append(
            f"## Functional Error Feedback (failing test cases)\n{parent.error_feedback}")

    if parent.ppa is None and parent.synth_diagnosis:
        feedback_sections.append(
            f"## Synthesis Error Feedback\n{parent.synth_diagnosis}\n\n"
            "Common synthesis issues and fixes:\n"
            "- \"Driver-driver conflict\": A signal is driven by multiple always blocks. "
            "Merge them into one block per signal.\n"
            "- 0-cell netlist: Logic was optimized away. Check for === (use ==), "
            "unreachable code, or signals overwritten by constants.\n"
            "- Crash/abort: Simplify complex memory or array constructs.")

    feedback_text = "\n\n".join(feedback_sections)

    user_msg = f"""The following design has issues that need to be fixed. Fix ALL reported issues while preserving the overall design architecture.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Design Strategy
{parent.thought}

## Current Code
```verilog
{parent.code}
```

{feedback_text}

{memory_context}

Fix all reported issues. The design must be functionally correct AND synthesizable."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_simplify_prompt(parent, spec: str, module_header: str,
                          memory_context: str = "") -> list:
    user_msg = f"""Simplify this design to reduce complexity and potential for errors, while preserving all functionality.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Design Strategy
{parent.thought}

## Current Code
```verilog
{parent.code}
```

{memory_context}

Simplify the logic while ensuring correctness."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_optimize_prompt(parent, spec: str, module_header: str,
                          memory_context: str = "") -> list:
    ppa_info = ""
    if parent.ppa:
        ppa_info = f"Current PPA: area={parent.ppa.area:.1f}um^2, delay={parent.ppa.delay:.2f}ns, power={parent.ppa.power:.2f}uW"
    diag = parent.synth_diagnosis or "No synthesis diagnosis available."

    user_msg = f"""Optimize this design for better PPA (Power, Performance, Area) based on the synthesis analysis below.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Design Strategy
{parent.thought}

## Current Code
```verilog
{parent.code}
```

## {ppa_info}

## Synthesis Analysis
{diag}

{memory_context}

Optimize for PPA while maintaining functional correctness."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_restructure_prompt(parent, spec: str, module_header: str,
                             memory_context: str = "") -> list:
    diag = parent.synth_diagnosis or "No synthesis diagnosis available."
    user_msg = f"""Restructure the critical path identified in the synthesis analysis to reduce delay.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Design Strategy
{parent.thought}

## Current Code
```verilog
{parent.code}
```

## Synthesis Analysis (focus on critical path)
{diag}

{memory_context}

Restructure to reduce the critical path delay. Maintain functional correctness."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_explore_prompt(parent, spec: str, module_header: str,
                         memory_context: str = "") -> list:
    user_msg = f"""Design a completely different architecture for the same specification. Do not reuse the parent's approach.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Approach to AVOID (do NOT reuse this)
{parent.thought}

{memory_context}

Create a fundamentally different implementation."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_ppa_aware_fix_prompt(parent, spec: str, module_header: str,
                               memory_context: str = "") -> list:
    ppa_info = ""
    if parent.ppa:
        ppa_info = f"Current PPA: area={parent.ppa.area:.1f}um^2, delay={parent.ppa.delay:.2f}ns, power={parent.ppa.power:.2f}uW"
    structures = parent.thought or "unknown structures"

    user_msg = f"""Fix the failing test cases, but you MUST preserve the following PPA-beneficial structures: {structures}. Only modify the logic related to the failing cases.

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Current Code
```verilog
{parent.code}
```

## Error Feedback
{parent.error_feedback}

## {ppa_info}

{memory_context}

Fix ONLY the failing tests. Preserve the PPA-beneficial design structures."""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_architecture_fusion_prompt(parent_a, parent_b, spec: str, module_header: str,
                                      memory_context: str = "",
                                      b_has_ppa_advantage: bool = True) -> list:
    ppa_a = ""
    if parent_a.ppa:
        ppa_a = f"area={parent_a.ppa.area:.1f}, delay={parent_a.ppa.delay:.2f}, power={parent_a.ppa.power:.2f}"
    ppa_b = ""
    if parent_b.ppa:
        ppa_b = f"area={parent_b.ppa.area:.1f}, delay={parent_b.ppa.delay:.2f}, power={parent_b.ppa.power:.2f}"

    if b_has_ppa_advantage:
        instruction = (
            "Combine the strengths of two parent designs. "
            "Take the functional correctness approach from Parent A "
            "and the PPA optimization technique from Parent B.")
        closing = "Combine: take functional correctness from Parent A and PPA optimization from Parent B."
    else:
        instruction = (
            "Combine the strengths of two parent designs with different architectures. "
            "Analyze both designs and create a new design that takes the best aspects of each "
            "to maximize both correctness and PPA.")
        closing = "Create a design that combines the best architectural ideas from both parents."

    user_msg = f"""{instruction}

## Specification
{spec}

## Module Header (must match exactly)
{module_header}

## Parent A (correctness={parent_a.correctness_score:.2f}, PPA: {ppa_a or 'N/A'})
Strategy: {parent_a.thought}
```verilog
{parent_a.code}
```

## Parent B (correctness={parent_b.correctness_score:.2f}, PPA: {ppa_b or 'N/A'})
Strategy: {parent_b.thought}
```verilog
{parent_b.code}
```

{memory_context}

{closing}"""

    return [build_system_message(), {"role": "user", "content": user_msg}]


def build_strategy_selection_prompt(spec: str) -> list:
    user_msg = f"""Given this hardware spec, which implementation strategies are applicable?
Options: behavioral, structural, pipeline, resource_shared, fsm_minimized.
Return only the applicable ones as a comma-separated list.

## Specification
{spec}"""

    return [{"role": "system", "content": "You are a hardware design expert. Respond with only a comma-separated list of applicable strategies."},
            {"role": "user", "content": user_msg}]
