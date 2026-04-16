from coevo.operators.base import BaseOperator
from coevo.llm.prompt_templates import build_fix_prompt, build_simplify_prompt


class FixOperator(BaseOperator):
    name = "fix"
    category = "correctness"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_fix_prompt(parents[0], spec, module_header, memory_context)


class SimplifyOperator(BaseOperator):
    name = "simplify"
    category = "correctness"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_simplify_prompt(parents[0], spec, module_header, memory_context)
