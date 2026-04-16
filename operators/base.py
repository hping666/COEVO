from abc import ABC, abstractmethod


class BaseOperator(ABC):
    name: str = ""
    category: str = ""  # "correctness", "ppa", "cross"
    requires_two_parents: bool = False

    @abstractmethod
    def build_prompt(self, parents: list, spec: str, module_header: str,
                     memory_context: str = "") -> list:
        """Return list of message dicts for OpenAI API."""
        pass

    def compute_reward(self, offspring, parents: list) -> float:
        """Default reward: 0. Override per category."""
        return 0.0
