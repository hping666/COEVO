"""RTLLM dataset adapter.

Layout (per design):

    <root>/<design_name>/
        design_description.txt      # specification
        testbench.v                 # original (binary) testbench
        testbench_enhanced.v        # enhanced (continuous-score) testbench
        verified_*.v                # golden reference RTL
"""
import glob
import os
import re
from typing import List, Optional

from coevo.datasets.base import DatasetAdapter, DesignInfo


class RTLLMAdapter(DatasetAdapter):
    NAME = "rtllm"
    CODE_FILE_EXT = "v"
    IVERILOG_FLAGS: List[str] = []  # Verilog-2001, no extra flags

    def __init__(self):
        # Designs whose verified ref RTL intentionally cannot be synthesized
        # (e.g. clock generators). Preserved from prior config default.
        self.SKIP_PPA_SYNTHESIS = ["clkgenerator"]

    # ---------------------------------------------------------------- discovery
    def discover_designs(self, root: str) -> List[DesignInfo]:
        """Find all RTLLM design directories with required files."""
        designs = []
        for cur_root, _dirs, files in os.walk(root):
            has_tb = "testbench_enhanced.v" in files
            has_ref = any(f.startswith("verified_") and f.endswith(".v") for f in files)
            has_spec = "design_description.txt" in files
            if has_tb and has_ref and has_spec:
                name = os.path.basename(cur_root)
                designs.append(DesignInfo(name=name, dir=cur_root))
        designs.sort(key=lambda d: d.name)
        return designs

    # -------------------------------------------------------------- per-design
    def load_spec(self, design: DesignInfo) -> str:
        with open(os.path.join(design.dir, "design_description.txt")) as f:
            return f.read()

    def extract_module_name(self, design: DesignInfo) -> str:
        """Extract DUT module name from ``<design>.<name> uut (`` in enhanced TB."""
        tb_path = self.get_enhanced_tb_path(design)
        if not tb_path or not os.path.exists(tb_path):
            return design.name
        with open(tb_path) as f:
            tb_text = f.read()
        # Parameterized: module_name #(...) uut (
        m = re.search(r"(\w+)\s+#\s*\(.*?\)\s*uut\s*\(", tb_text, re.DOTALL)
        if not m:
            m = re.search(r"(\w+)\s+uut\s*\(", tb_text)
        return m.group(1) if m else design.name

    def load_module_header(self, design: DesignInfo) -> str:
        """Reconstruct the module header by parsing the DUT instantiation."""
        # Delegate to the existing implementation in prompt_templates so the
        # exact same regex-based reconstruction is used.
        from coevo.llm.prompt_templates import extract_module_header
        return extract_module_header(design.dir)

    # -------------------------------------------------------- testbench paths
    def get_enhanced_tb_path(self, design: DesignInfo) -> Optional[str]:
        return os.path.join(design.dir, "testbench_enhanced.v")

    def get_original_tb_path(self, design: DesignInfo) -> Optional[str]:
        return os.path.join(design.dir, "testbench.v")

    def get_original_tb_extra_files(self, design: DesignInfo) -> List[str]:
        # RTLLM original TBs are self-contained and only need the candidate.
        return []

    # ------------------------------------------------------------- TB parsing
    def check_original_tb_result(self, stdout: str) -> bool:
        """Return True iff 'passed' appears and 'error' does not (case insensitive)."""
        lower = stdout.lower()
        return "passed" in lower and "error" not in lower

    # ---------------------------------------------------------------- reference
    def load_reference_code(self, design: DesignInfo) -> Optional[str]:
        pattern = os.path.join(design.dir, "verified_*.v")
        ref_files = glob.glob(pattern)
        if not ref_files:
            return None
        with open(ref_files[0]) as f:
            return f.read()

    # -------------------------------------------------------------------- LLM
    def get_system_message(self) -> str:
        from coevo.llm.prompt_templates import SYSTEM_MESSAGE
        return SYSTEM_MESSAGE
