import re
from coevo.llm.prompt_templates import (
    build_initial_generation_prompt, build_strategy_selection_prompt, STRATEGY_DESCRIPTIONS
)


class InitializationOperator:
    def __init__(self, config: dict):
        self.strategies = config['initialization']['strategies']
        self.auto_select = config['initialization'].get('auto_select_strategies', True)

    def select_strategies(self, spec: str, llm_client, config: dict) -> list:
        """Ask LLM which strategies apply, or fall back to all."""
        if not self.auto_select:
            return self.strategies

        try:
            prompt = build_strategy_selection_prompt(spec)
            response = llm_client.call(
                config['llm']['analysis_model'], prompt,
                temperature=0.3, max_tokens=256
            )
            content = response['content'].lower()
            valid = list(STRATEGY_DESCRIPTIONS.keys())
            selected = [s for s in valid if s in content]
            if selected:
                return selected
        except Exception:
            pass

        return self.strategies

    def build_initial_prompt(self, spec: str, module_header: str, strategy: str) -> list:
        return build_initial_generation_prompt(spec, module_header, strategy)
