"""Base class for dataset adapters.

A :class:`DatasetAdapter` abstracts the layout and conventions of a specific
benchmark dataset (RTLLM, VerilogEval, ...) so the evolution core can run
unchanged across datasets. Every dataset-specific detail (file paths, module
naming, original-TB output format, LLM system message, iverilog flags, ...)
lives behind the adapter interface.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class DesignInfo:
    """Minimal design identifier used by the framework.

    ``dir`` has slightly different semantics per dataset:

    - **RTLLM**: the design's own subdirectory (contains spec, TBs, ref files).
    - **VerilogEval**: the dataset root (flat layout; per-design files are
      prefixed with ``name``).
    """
    name: str
    dir: str


class DatasetAdapter(ABC):
    """Abstract base class for dataset adapters."""

    # Human-readable dataset name (e.g. "rtllm", "verilogeval")
    NAME: str = ""

    # File extension used when writing candidate RTL to disk (without leading dot)
    CODE_FILE_EXT: str = "v"

    # Extra flags prepended to iverilog invocations (e.g. ["-g2012"] for SV)
    IVERILOG_FLAGS: List[str] = []

    # Design names whose ref RTL is known not to synthesize to cells
    # (wire-only / constant-only designs etc.). Used by the PPA evaluator
    # to short-circuit synthesis.
    SKIP_PPA_SYNTHESIS: List[str] = []

    # ---------------------------------------------------------------- discovery
    @abstractmethod
    def discover_designs(self, root: str) -> List[DesignInfo]:
        """Return every design in the dataset rooted at ``root``, sorted by name."""

    # -------------------------------------------------------------- per-design
    @abstractmethod
    def load_spec(self, design: DesignInfo) -> str:
        """Return the natural-language specification text for ``design``."""

    @abstractmethod
    def extract_module_name(self, design: DesignInfo) -> str:
        """Return the DUT module name used by the candidate RTL."""

    @abstractmethod
    def load_module_header(self, design: DesignInfo) -> str:
        """Return a Verilog ``module ...;`` header the candidate must match."""

    # -------------------------------------------------------- testbench paths
    @abstractmethod
    def get_enhanced_tb_path(self, design: DesignInfo) -> Optional[str]:
        """Return path to the enhanced (evolutionary-score) testbench, or None."""

    @abstractmethod
    def get_original_tb_path(self, design: DesignInfo) -> Optional[str]:
        """Return path to the original (binary pass/fail) testbench, or None."""

    @abstractmethod
    def get_original_tb_extra_files(self, design: DesignInfo) -> List[str]:
        """Return extra files that must be compiled alongside the original TB.

        For RTLLM this is always empty. For VerilogEval the ref file must be
        supplied because the original TB instantiates both ``TopModule`` and
        ``RefModule``.
        """

    # ------------------------------------------------------------- TB parsing
    @abstractmethod
    def check_original_tb_result(self, stdout: str) -> bool:
        """Return ``True`` iff the original TB stdout indicates success."""

    # ---------------------------------------------------------------- reference
    @abstractmethod
    def load_reference_code(self, design: DesignInfo) -> Optional[str]:
        """Return reference RTL code (after any module-name rewriting).

        Used only for the baseline PPA comparison at the results phase. May
        return ``None`` when no reference is available.
        """

    # -------------------------------------------------------------------- LLM
    @abstractmethod
    def get_system_message(self) -> str:
        """Return the system prompt used when asking the LLM to generate RTL."""

    # --------------------------------------------------------------- utility
    def get_design_working_dir(self, design: DesignInfo) -> str:
        """Return the directory used as ``cwd`` when running simulation.

        Defaults to ``design.dir`` which is correct for both datasets (RTLLM
        per-design subdir, VerilogEval flat root — both are where any
        auxiliary files referenced by ``$readmemh`` live).
        """
        return design.dir
