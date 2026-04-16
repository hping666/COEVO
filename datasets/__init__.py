"""Dataset adapters for COEVO.

Each adapter encapsulates dataset-specific layout and I/O (discovery,
spec/tb/reference file paths, original-TB result parsing, language flags).
The framework code is dataset-agnostic and interacts with whichever adapter
is selected at run time via :func:`get_adapter`.
"""
from coevo.datasets.base import DatasetAdapter, DesignInfo
from coevo.datasets.rtllm import RTLLMAdapter


def get_adapter(name: str) -> DatasetAdapter:
    """Return a dataset adapter instance by name."""
    name = (name or "rtllm").lower()
    if name == "rtllm":
        return RTLLMAdapter()
    if name == "verilogeval":
        # Lazy import to avoid loading unused adapter at startup
        from coevo.datasets.verilogeval import VerilogEvalAdapter
        return VerilogEvalAdapter()
    raise ValueError(f"Unknown dataset: {name!r}. Supported: rtllm, verilogeval")


__all__ = ["DatasetAdapter", "DesignInfo", "RTLLMAdapter", "get_adapter"]
