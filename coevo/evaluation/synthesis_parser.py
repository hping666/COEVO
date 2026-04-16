import re
from typing import Optional


def parse_yosys_stat(log_text: str) -> dict:
    """Parse Yosys stat output for area, cell count, wire count."""
    result = {'area': 0.0, 'num_cells': 0, 'num_wires': 0}

    m = re.search(r"Chip area for module.*?:\s+([\d.]+)", log_text)
    if m:
        result['area'] = float(m.group(1))

    # stat -liberty format: "  85  155.344 cells" or "  1652 1.92E+03 cells"
    m = re.search(r'^\s*(\d+)\s+[\d.]+(?:[eE][+-]?\d+)?\s+cells\s*$', log_text, re.MULTILINE)
    if m:
        result['num_cells'] = int(m.group(1))
    else:
        # Fallback: "Number of cells: N"
        m = re.search(r"Number of cells:\s+(\d+)", log_text)
        if m:
            result['num_cells'] = int(m.group(1))

    # stat -liberty format: "  186        - wires"
    m = re.search(r'^\s*(\d+)\s+.*?wires\s*$', log_text, re.MULTILINE)
    if m:
        result['num_wires'] = int(m.group(1))
    else:
        m = re.search(r"Number of wires:\s+(\d+)", log_text)
        if m:
            result['num_wires'] = int(m.group(1))

    return result


def parse_opensta_timing(log_text: str, clock_period: float = 10.0) -> Optional[float]:
    """Parse OpenSTA report_checks output for critical path delay.
    Handles both sequential (reg-to-reg) and combinational (input-to-output) designs.
    Uses max data arrival time as primary metric (consistent across both types)."""
    # Priority 1: max data arrival time across all reported paths
    # For sequential: arrival = clk-to-q + combinational delay (critical path)
    # For combinational: arrival = input-to-output propagation delay
    all_arrivals = re.findall(r'([\d.]+)\s+data arrival time', log_text)
    if all_arrivals:
        return max(float(a) for a in all_arrivals)

    # Priority 2: fallback to clock_period - slack
    slack_m = re.search(r'([-\d.]+)\s+slack\s+\((?:MET|VIOLATED)\)', log_text)
    if slack_m:
        slack = float(slack_m.group(1))
        return max(0.0, clock_period - slack)

    return None


def parse_opensta_power(log_text: str) -> Optional[float]:
    """Parse OpenSTA report_power output for total power in uW."""
    # Format: "Total  3.91e-05  1.52e-05  3.18e-06  5.75e-05 100.0%"
    # The 4th numeric column is total power in Watts
    for line in log_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("Total") and "%" in stripped:
            # Extract scientific notation numbers (power values)
            nums = re.findall(r'[-+]?\d+\.\d+[eE][-+]?\d+', stripped)
            if len(nums) >= 4:
                total_w = float(nums[3])  # 4th value is Total Power
                return total_w * 1e6  # Convert W to uW
            elif nums:
                total_w = float(nums[-1])
                return total_w * 1e6
    return None


def detect_clock_ports(verilog_code: str) -> list:
    """Find all INPUT clock ports in the module declaration.
    Handles both parameterized (#(...)) and non-parameterized modules.
    Returns list of port names (empty if no clocks found)."""
    m = re.search(r'module\s+\w+\s*(?:#\s*\(.*?\)\s*)?\((.*?)\);', verilog_code, re.DOTALL)
    if not m:
        return []

    port_section = m.group(1)

    # Strip comments to avoid false matches (e.g., "// clock signal")
    port_section = re.sub(r'//[^\n]*', '', port_section)
    port_section = re.sub(r'/\*.*?\*/', '', port_section, flags=re.DOTALL)

    # Extract input port names only (skip outputs that may contain 'clk')
    # ANSI style: "input [wire] [width] name"
    input_ports = set(re.findall(
        r'\binput\s+(?:wire\s+)?(?:reg\s+)?(?:\[.*?\]\s*)?(\w+)', port_section))
    # Old style: port names are just listed; check full code for "input name"
    if not input_ports:
        for name in re.findall(r'\b(\w+)\b', port_section):
            if re.search(rf'\binput\b[^;]*\b{re.escape(name)}\b', verilog_code):
                input_ports.add(name)

    found = []
    # Check known clock port names among input ports
    known = ['clk', 'clock', 'CLK', 'CLOCK', 'Clk',
             'wclk', 'rclk', 'WCLK', 'RCLK', 'clk_a', 'clk_b', 'CLK_in']
    for name in known:
        if name in input_ports and name not in found:
            found.append(name)

    # Any other input port containing 'clk' or 'clock' (case-insensitive)
    for name in input_ports:
        if re.search(r'clk|clock', name, re.IGNORECASE) and name not in found:
            found.append(name)

    return found


def detect_clock_port(verilog_code: str) -> Optional[str]:
    """Return first detected clock port name, or None. Convenience wrapper."""
    ports = detect_clock_ports(verilog_code)
    return ports[0] if ports else None
