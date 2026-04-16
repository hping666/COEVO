from coevo.operators.base import BaseOperator
from coevo.llm.prompt_templates import (
    build_optimize_prompt, build_restructure_prompt, build_explore_prompt
)


class OptimizeOperator(BaseOperator):
    name = "optimize"
    category = "ppa"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_optimize_prompt(parents[0], spec, module_header, memory_context)


class RestructureOperator(BaseOperator):
    name = "restructure"
    category = "ppa"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_restructure_prompt(parents[0], spec, module_header, memory_context)


class ExploreOperator(BaseOperator):
    name = "explore"
    category = "ppa"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_explore_prompt(parents[0], spec, module_header, memory_context)
