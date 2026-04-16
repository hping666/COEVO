from dataclasses import dataclass, field
from typing import Optional, List


@dataclass
class MemoryEntry:
    category: str           # "effective_optimization" | "successful_fix" | "failed_attempt"
    strategy_summary: str
    operator: str
    ppa_delta: Optional[dict] = None
    correctness_delta: float = 0.0
    generation: int = 0


class StrategyMemory:
    def __init__(self, config: dict):
        self.max_entries = config.get('max_entries', 30)
        self.inject_top_k = config.get('inject_top_k', 3)
        self.entries: List[MemoryEntry] = []

    def reset(self):
        self.entries = []

    def record(self, offspring, parents: list, operator_name: str):
        """Compare offspring vs best parent. Record if noteworthy."""
        if not parents:
            return

        best_parent = max(parents, key=lambda p: p.correctness_score)
        corr_delta = offspring.correctness_score - best_parent.correctness_score

        ppa_delta = None
        ppa_improved = False
        if offspring.ppa and best_parent.ppa:
            ppa_delta = {
                'area': best_parent.ppa.area - offspring.ppa.area,
                'delay': best_parent.ppa.delay - offspring.ppa.delay,
                'power': best_parent.ppa.power - offspring.ppa.power,
            }
            ppa_improved = (ppa_delta['area'] > 0 or ppa_delta['delay'] > 0 or ppa_delta['power'] > 0)

        category = None
        if ppa_improved and offspring.correctness_score >= best_parent.correctness_score:
            category = "effective_optimization"
        elif corr_delta > 0.1:
            category = "successful_fix"
        elif corr_delta < -0.2 or self._adp_worsened(offspring, best_parent):
            category = "failed_attempt"

        if category is None:
            return

        entry = MemoryEntry(
            category=category,
            strategy_summary=offspring.thought[:200] if offspring.thought else "",
            operator=operator_name,
            ppa_delta=ppa_delta,
            correctness_delta=corr_delta,
            generation=offspring.generation,
        )
        self.entries.append(entry)

        # Trim oldest if exceeds max
        if len(self.entries) > self.max_entries:
            self.entries = self.entries[-self.max_entries:]

    def retrieve(self, operator_category: str) -> List[MemoryEntry]:
        """Return top-k most recent entries relevant to operator category."""
        if operator_category == "correctness":
            relevant = [e for e in self.entries if e.category in ("successful_fix", "failed_attempt")]
        elif operator_category == "ppa":
            relevant = [e for e in self.entries if e.category in ("effective_optimization", "failed_attempt")]
        else:  # cross
            relevant = list(self.entries)

        return relevant[-self.inject_top_k:]

    @staticmethod
    def _adp_worsened(offspring, parent, threshold: float = 0.2) -> bool:
        """Check if composite PPA metric (ADP) worsened by > threshold (20%)."""
        if not offspring.ppa or not parent.ppa:
            return False
        parent_adp = parent.ppa.area * parent.ppa.delay
        if parent_adp <= 0:
            return False
        offspring_adp = offspring.ppa.area * offspring.ppa.delay
        return (offspring_adp - parent_adp) / parent_adp > threshold

    def format_for_prompt(self, entries: List[MemoryEntry]) -> str:
        if not entries:
            return ""
        lines = ["## Previously Learned Strategies"]
        for e in entries:
            tag = "effective" if e.category == "effective_optimization" else (
                "fix" if e.category == "successful_fix" else "failed")
            lines.append(f"- [{tag}] {e.strategy_summary}")
        return "\n".join(lines)
