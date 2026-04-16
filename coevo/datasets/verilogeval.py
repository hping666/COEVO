"""VerilogEval dataset adapter.

Layout (flat, per-design file prefix = design name):

    <root>/
        problems.txt                       # one design name per line
        <name>_prompt.txt                  # specification
        <name>_ref.sv                      # golden reference (module RefModule)
        <name>_test.sv                     # original testbench
        <name>_test_enhanced.sv            # enhanced testbench (uses TopModule uut)

The DUT module is always named ``TopModule``. The original testbench
instantiates BOTH ``TopModule`` (as DUT) and ``RefModule`` (as golden
reference), so compiling it requires the ref file to be supplied alongside
the candidate.

Reference-PPA synthesis expects the candidate's module name, so
:meth:`load_reference_code` rewrites ``module RefModule`` → ``module TopModule``
before returning the code.
"""
import os
import re
from typing import List, Optional

from coevo.datasets.base import DatasetAdapter, DesignInfo


_DUT_MODULE_NAME = "TopModule"
_REF_MODULE_NAME = "RefModule"


class VerilogEvalAdapter(DatasetAdapter):
    NAME = "verilogeval"
    CODE_FILE_EXT = "sv"
    IVERILOG_FLAGS: List[str] = ["-g2012"]  # SystemVerilog 1800-2012

    def __init__(self):
        # Designs known to be unsynthesizable by Yosys (wire-only / constant-
        # only / pure bit-reordering / assign-only interconnect). PPAEvaluator
        # short-circuits these so we don't waste synthesis time and don't
        # misreport them as failures. Verified against a full synthesis sweep
        # of VerilogEval (14/156 FAIL).
        self.SKIP_PPA_SYNTHESIS: List[str] = [
            "Prob001_zero", "Prob002_m2014_q4i", "Prob003_step_one",
            "Prob004_vector2", "Prob006_vectorr",  "Prob007_wire",
            "Prob008_m2014_q4h", "Prob015_vector1", "Prob023_vector100r",
            "Prob028_m2014_q4a", "Prob032_vector0", "Prob042_vector4",
            "Prob059_wire4",     "Prob064_vector3",
        ]

    # ---------------------------------------------------------------- discovery
    def discover_designs(self, root: str) -> List[DesignInfo]:
        """Discover designs by reading ``problems.txt`` or scanning ``*_ref.sv``.

        ``DesignInfo.dir`` is set to ``root`` for every design because
        VerilogEval uses a flat layout (all files prefixed with the name).
        """
        root = os.path.abspath(root)
        problems_file = os.path.join(root, "problems.txt")
        names: List[str] = []

        if os.path.isfile(problems_file):
            with open(problems_file) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        names.append(line)
        else:
            # Fallback: derive from *_ref.sv filenames
            for entry in os.listdir(root):
                if entry.endswith("_ref.sv"):
                    names.append(entry[: -len("_ref.sv")])

        # Keep only designs whose required files actually exist
        designs: List[DesignInfo] = []
        for name in names:
            ref = os.path.join(root, f"{name}_ref.sv")
            prompt = os.path.join(root, f"{name}_prompt.txt")
            test = os.path.join(root, f"{name}_test.sv")
            if os.path.isfile(ref) and os.path.isfile(prompt) and os.path.isfile(test):
                designs.append(DesignInfo(name=name, dir=root))
        designs.sort(key=lambda d: d.name)
        return designs

    # -------------------------------------------------------------- per-design
    def load_spec(self, design: DesignInfo) -> str:
        with open(os.path.join(design.dir, f"{design.name}_prompt.txt")) as f:
            return f.read()

    def extract_module_name(self, design: DesignInfo) -> str:
        """The DUT is always ``TopModule`` in VerilogEval."""
        return _DUT_MODULE_NAME

    def load_module_header(self, design: DesignInfo) -> str:
        """Extract module header from the enhanced TB's ``TopModule uut (...)``.

        Uses the same parsing helper as RTLLM since the enhanced TBs share
        the ``uut`` instance-name convention. Falls back to reading the ref
        file's ``module RefModule`` declaration if the enhanced TB is absent.
        """
        from coevo.llm.prompt_templates import _parse_dut_instantiation

        tb_path = self.get_enhanced_tb_path(design)
        if tb_path and os.path.exists(tb_path):
            with open(tb_path) as f:
                tb_text = f.read()
            header = _parse_dut_instantiation(tb_text)
            if header:
                return header

        # Fallback: derive from ref file by rewriting module name
        ref_path = os.path.join(design.dir, f"{design.name}_ref.sv")
        if os.path.isfile(ref_path):
            with open(ref_path) as f:
                ref_text = f.read()
            m = re.search(
                r"module\s+" + re.escape(_REF_MODULE_NAME) + r"\b([\s\S]*?;)",
                ref_text)
            if m:
                return f"module {_DUT_MODULE_NAME}" + m.group(1).rstrip()
        return ""

    # -------------------------------------------------------- testbench paths
    def get_enhanced_tb_path(self, design: DesignInfo) -> Optional[str]:
        return os.path.join(design.dir, f"{design.name}_test_enhanced.sv")

    def get_original_tb_path(self, design: DesignInfo) -> Optional[str]:
        return os.path.join(design.dir, f"{design.name}_test.sv")

    def get_original_tb_extra_files(self, design: DesignInfo) -> List[str]:
        """VerilogEval original TBs instantiate BOTH TopModule and RefModule,
        so the ref file must be compiled alongside the candidate."""
        ref_path = os.path.join(design.dir, f"{design.name}_ref.sv")
        return [ref_path] if os.path.isfile(ref_path) else []

    # ------------------------------------------------------------- TB parsing
    def check_original_tb_result(self, stdout: str) -> bool:
        """VerilogEval original TBs print ``Mismatches: N in M samples``.

        Returns True iff a ``Mismatches: 0 in M samples`` line appears with
        M > 0.  The explicit mismatch count is checked first so that TB-printed
        ``TIMEOUT`` markers (emitted when simulation hits its internal time
        limit but still completes all comparisons) do not cause false failures.
        """
        if not stdout:
            return False
        # Prioritize explicit mismatch count — definitive when present
        m = re.search(r"Mismatches:\s*(\d+)\s+in\s+(\d+)\s+samples", stdout)
        if m:
            return int(m.group(1)) == 0 and int(m.group(2)) > 0
        # No Mismatches line → heuristics
        lower = stdout.lower()
        if "timeout" in lower:
            return False
        return "passed" in lower and "error" not in lower

    # ---------------------------------------------------------------- reference
    def load_reference_code(self, design: DesignInfo) -> Optional[str]:
        """Return ref RTL with ``RefModule`` renamed to ``TopModule``.

        The reference PPA pipeline expects the module name to match the
        candidate's (``TopModule``), so we rewrite the declaration here.
        """
        ref_path = os.path.join(design.dir, f"{design.name}_ref.sv")
        if not os.path.isfile(ref_path):
            return None
        with open(ref_path) as f:
            code = f.read()
        # Replace both "module RefModule" and any bare RefModule references
        code = re.sub(
            r"\b" + re.escape(_REF_MODULE_NAME) + r"\b",
            _DUT_MODULE_NAME, code)
        return code

    # -------------------------------------------------------------------- LLM
    def get_system_message(self) -> str:
        from coevo.llm.prompt_templates import VERILOGEVAL_SYSTEM_MESSAGE
        return VERILOGEVAL_SYSTEM_MESSAGE
