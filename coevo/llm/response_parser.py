import re
from typing import Tuple


def parse_llm_response(content: str) -> Tuple[str, str]:
    """
    Extract (thought, code) from LLM response.
    Try multiple formats. Return (thought, code) or (thought, "") on failure.
    """
    if not content:
        return ("", "")

    thought = _extract_thought(content)
    code = _extract_code(content)
    return (thought, code)


def _extract_thought(content: str) -> str:
    m = re.search(r'<thought>(.*?)</thought>', content, re.DOTALL)
    return m.group(1).strip() if m else ""


def _extract_code(content: str) -> str:
    # Pattern 1: <code>```{verilog|systemverilog|sv|v}...```</code>
    m = re.search(
        r'<code>\s*```(?:systemverilog|verilog|sv|v)?\s*\n?(.*?)```\s*</code>',
        content, re.DOTALL)
    if m:
        return _clean_module(m.group(1))

    # Pattern 2: ```{verilog|systemverilog|sv|v}...```
    m = re.search(
        r'```(?:systemverilog|verilog|sv|v)\s*\n?(.*?)```',
        content, re.DOTALL)
    if m:
        return _clean_module(m.group(1))

    # Pattern 3: ```...``` with module keyword
    m = re.search(r'```\s*\n?(.*?)```', content, re.DOTALL)
    if m and 'module' in m.group(1):
        return _clean_module(m.group(1))

    # Pattern 4: Raw module...endmodule
    m = re.search(r'(module\s+\w+[\s\S]*?endmodule)', content)
    if m:
        return m.group(1).strip()

    return ""


def _clean_module(text: str) -> str:
    """Extract complete module...endmodule from text."""
    m = re.search(r'(module\s+\w+[\s\S]*?endmodule)', text)
    return m.group(1).strip() if m else text.strip()
