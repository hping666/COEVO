import tempfile
import os
import re
import logging

from coevo.core.individual import PPAMetrics
from coevo.utils.timeout import run_with_timeout
from coevo.evaluation.synthesis_parser import (
    parse_yosys_stat, parse_opensta_timing, parse_opensta_power, detect_clock_ports
)

logger = logging.getLogger("coevo.ppa")


class PPAEvaluator:
    def __init__(self, config: dict, adapter=None):
        self.yosys = config['paths']['yosys_binary']
        self.opensta = config['paths']['opensta_binary']
        self.liberty = config['evaluation']['ppa']['liberty_file']
        self.clock_period = config['evaluation']['ppa']['default_clock_period']
        self.timeout = config['evaluation']['ppa']['timeout']
        # Config is authoritative for skip_list; adapter supplies any extras not
        # already in config (harmless additions for dataset-specific designs).
        self.adapter = adapter
        skip_list = list(config.get('design_overrides', {}).get('skip_ppa_synthesis', []))
        if adapter is not None:
            for name in getattr(adapter, 'SKIP_PPA_SYNTHESIS', []) or []:
                if name not in skip_list:
                    skip_list.append(name)
        self.skip_list = skip_list

    def evaluate(self, candidate_code: str, module_name: str, design_name: str):
        """Returns (PPAMetrics_or_None, yosys_log_str)."""
        if design_name in self.skip_list:
            return None, ""

        with tempfile.TemporaryDirectory() as tmp:
            cand_path = os.path.join(tmp, f"{module_name}.v")
            with open(cand_path, 'w') as f:
                f.write(candidate_code)

            # Step 1: Yosys synthesis
            netlist_path, yosys_log, yosys_stats = self._run_yosys(cand_path, module_name, tmp)
            if netlist_path is None:
                return None, yosys_log

            # Step 2: OpenSTA
            delay, power = self._run_opensta(netlist_path, module_name, tmp, candidate_code)

            ppa = PPAMetrics(
                area=yosys_stats.get('area', 0),
                delay=delay if delay else 0,
                power=power if power else 0,
                num_cells=yosys_stats.get('num_cells', 0),
                num_wires=yosys_stats.get('num_wires', 0)
            )
            return ppa, yosys_log

    def _run_yosys(self, cand_path: str, module_name: str, tmp_dir: str):
        """Run Yosys synthesis. Return (netlist_path, log_str, stats_dict) or (None, log, {})."""
        netlist_path = os.path.join(tmp_dir, f"{module_name}_netlist.v")
        tcl_path = os.path.join(tmp_dir, "synth.tcl")

        tcl_script = f"""read_verilog -sv {cand_path}
hierarchy -check -top {module_name}
flatten
proc; opt
fsm; opt
memory; opt
opt -full
techmap; opt
dfflibmap -liberty {self.liberty}
abc -liberty {self.liberty}
opt_clean -purge
write_verilog -noattr -noexpr -nohex -nodec {netlist_path}
stat -liberty {self.liberty}
"""
        with open(tcl_path, 'w') as f:
            f.write(tcl_script)

        result = run_with_timeout(f"{self.yosys} -s {tcl_path}", timeout=self.timeout, cwd=tmp_dir)
        log_text = result.stdout + "\n" + result.stderr

        if result.returncode != 0 or not os.path.exists(netlist_path):
            logger.debug(f"Yosys synthesis failed: {log_text[:300]}")
            return (None, log_text, {})

        stats = parse_yosys_stat(log_text)

        # Treat 0-cell netlist as synthesis failure (e.g. multi-driver → optimized away)
        if stats.get('num_cells', 0) == 0:
            logger.debug(f"Yosys produced 0 cells for {module_name}, treating as synthesis failure")
            return (None, log_text, {})

        return (netlist_path, log_text, stats)

    def _run_opensta(self, netlist_path: str, module_name: str, tmp_dir: str,
                     original_code: str = ""):
        """Run OpenSTA for timing and power. Return (delay_ns, power_uw)."""
        tcl_path = os.path.join(tmp_dir, "sta.tcl")

        # Detect clock(s) from original code
        clock_ports = detect_clock_ports(original_code) if original_code else []

        tcl_lines = [
            f"read_liberty {self.liberty}",
            f"read_verilog {netlist_path}",
            f"link_design {module_name}",
        ]
        if clock_ports:
            # Sequential design: create clock for each clock port
            for cp in clock_ports:
                tcl_lines.append(
                    f"create_clock -period {self.clock_period} [get_ports {cp}]")
            # I/O delays relative to first clock
            tcl_lines += [
                f"set_input_delay -clock [lindex [all_clocks] 0] 0 [all_inputs]",
                f"set_output_delay -clock [lindex [all_clocks] 0] 0 [all_outputs]",
            ]
        else:
            # Combinational design: virtual clock + I/O delays
            tcl_lines += [
                f"create_clock -name virtual_clock -period {self.clock_period}",
                f"set_input_delay -clock virtual_clock 0 [all_inputs]",
                f"set_output_delay -clock virtual_clock 0 [all_outputs]",
            ]
        # Max delay constraint for input-to-output combinational paths
        tcl_lines.append(f"set_max_delay {self.clock_period} -from [all_inputs] -to [all_outputs]")
        tcl_lines += [
            "report_checks -path_delay max",
            "report_checks -path_delay max -from [all_inputs] -to [all_outputs]",
            "report_power",
            "exit",
        ]

        with open(tcl_path, 'w') as f:
            f.write("\n".join(tcl_lines) + "\n")

        result = run_with_timeout(f"{self.opensta} -exit {tcl_path}", timeout=self.timeout, cwd=tmp_dir)
        log_text = result.stdout + "\n" + result.stderr

        delay = parse_opensta_timing(log_text, self.clock_period)
        power = parse_opensta_power(log_text)

        return (delay, power)

    def extract_synthesis_diagnosis(self, yosys_log: str) -> str:
        """Parse Yosys log to extract structured optimization guidance."""
        if not yosys_log:
            return "No synthesis log available."

        lines = []

        # Area
        m = re.search(r"Chip area for module.*?:\s+([\d.]+)", yosys_log)
        if m:
            lines.append(f"Total area: {m.group(1)} um^2")

        # Cell/wire counts
        m_cells = re.search(r"Number of cells:\s+(\d+)", yosys_log)
        m_wires = re.search(r"Number of wires:\s+(\d+)", yosys_log)
        if m_cells:
            lines.append(f"Cell count: {m_cells.group(1)}")
        if m_wires:
            lines.append(f"Wire count: {m_wires.group(1)}")

        # Logic levels from abc
        m_lev = re.search(r"ABC:\s+.*?lev\s*=\s*(\d+)", yosys_log)
        if m_lev:
            lines.append(f"Logic levels (abc): {m_lev.group(1)}")

        # FSM detection
        fsm_matches = re.findall(r"Found\s+FSM.*?(\d+)\s+state", yosys_log, re.IGNORECASE)
        if fsm_matches:
            for states in fsm_matches:
                lines.append(f"FSM detected: {states} states")

        return "\n".join(lines) if lines else "No detailed synthesis info extracted."
