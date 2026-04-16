from coevo.operators.base import BaseOperator
from coevo.llm.prompt_templates import (
    build_ppa_aware_fix_prompt, build_architecture_fusion_prompt
)


class PPAAwareFixOperator(BaseOperator):
    name = "ppa_aware_fix"
    category = "cross"

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        return build_ppa_aware_fix_prompt(parents[0], spec, module_header, memory_context)


class ArchitectureFusionOperator(BaseOperator):
    name = "architecture_fusion"
    category = "cross"
    requires_two_parents = True

    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        # Parent A: higher correctness; Parent B: different approach
        a, b = parents[0], parents[1]
        if b.correctness_score > a.correctness_score:
            a, b = b, a
        # Verify if B actually has better PPA (by ADP)
        b_has_ppa_advantage = (
            b.ppa is not None and a.ppa is not None
            and (b.ppa.area * b.ppa.delay) < (a.ppa.area * a.ppa.delay)
        )
        return build_architecture_fusion_prompt(
            a, b, spec, module_header, memory_context, b_has_ppa_advantage)
