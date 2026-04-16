import random
from typing import List, Optional, Tuple

from coevo.core.individual import Individual


class Population:
    def __init__(self, max_size: int, config: dict):
        self.individuals: List[Individual] = []
        self.max_size = max_size
        self.config = config
        self.crossover_donors: List[Individual] = []
        self._cached_ranks: dict = None  # {id(ind): rank} cache for select_parent

    def _invalidate_cache(self):
        self._cached_ranks = None

    def add(self, individual: Individual):
        self.individuals.append(individual)
        self._invalidate_cache()

    def select_parent(self) -> Individual:
        """Fitness-proportional selection based on Pareto rank.
        Only selects from main population (excludes crossover_donors).
        Caches Pareto ranks; invalidated on add()/survivor_selection()."""
        if not self.individuals:
            raise ValueError("Population is empty")

        if self._cached_ranks is None:
            levels = self._non_dominated_sort(self.individuals)
            self._cached_ranks = {}
            for level_idx, level in enumerate(levels):
                for ind in level:
                    self._cached_ranks[id(ind)] = level_idx + 1

        weights = [1.0 / self._cached_ranks.get(id(ind), len(self._cached_ranks))
                   for ind in self.individuals]
        return random.choices(self.individuals, weights=weights)[0]

    def select_two_parents(self) -> Tuple[Individual, Individual]:
        """Select two different parents. Second parent includes crossover_donors."""
        all_candidates = self.individuals + self.crossover_donors
        if len(all_candidates) < 2:
            p = all_candidates[0]
            return (p, p)

        # P1: from main population (high quality)
        p1 = self.select_parent()

        # P2: from individuals + donors (Pareto-rank-proportional)
        levels = self._non_dominated_sort(all_candidates)
        rank_map = {}
        for level_idx, level in enumerate(levels):
            for ind in level:
                rank_map[id(ind)] = level_idx + 1
        # Exclude p1 from p2 candidates
        p2_candidates = [ind for ind in all_candidates if ind.id != p1.id]
        if not p2_candidates:
            return (p1, p1)
        weights = [1.0 / rank_map.get(id(ind), len(levels)) for ind in p2_candidates]
        p2 = random.choices(p2_candidates, weights=weights)[0]
        return (p1, p2)

    def survivor_selection(self, offspring: List[Individual], theta: float):
        """Combine population + offspring, apply gate + Pareto selection."""
        combined = self.individuals + offspring

        # Step 1: Gate filter
        pool = [ind for ind in combined if ind.correctness_score >= theta]
        below_threshold = [ind for ind in combined if ind.correctness_score < theta]
        if not pool:
            pool = combined
            below_threshold = []

        # Step 2: Non-dominated sorting
        levels = self._non_dominated_sort(pool)

        # Step 3: Intra-level sort (configurable, default=correctness descending)
        sort_by = self.config['evolution']['selection'].get('intra_level_sort_by', 'correctness')
        for level in levels:
            if sort_by == 'correctness':
                level.sort(key=lambda ind: ind.correctness_score, reverse=True)
            else:
                # Sort by PPA metric (ascending = lower is better), correctness as tiebreaker
                metric_fn = self.PPA_METRICS.get(sort_by, self.PPA_METRICS.get('adp'))
                level.sort(key=lambda ind: (
                    metric_fn(ind.ppa) if ind.ppa else float('inf'),
                    -ind.correctness_score
                ))

        # Step 4: Slot allocation
        strategy = self.config['evolution']['selection']['strategy']
        if strategy == "proportional":
            survivors = self._proportional_allocate(levels, self.max_size)
        else:
            survivors = self._sequential_allocate(levels, self.max_size)

        # Step 5: Keep crossover donors from below-threshold
        donor_count = self.config['evolution']['selection'].get('crossover_donor_count', 3)
        below_threshold.sort(key=lambda ind: ind.correctness_score, reverse=True)
        self.crossover_donors = below_threshold[:donor_count]

        self.individuals = survivors
        self._invalidate_cache()

    def _non_dominated_sort(self, pool: List[Individual]) -> List[List[Individual]]:
        """Standard non-dominated sorting on 4 objectives (all maximized)."""
        n = len(pool)
        if n == 0:
            return []

        # Extract objectives: (correctness, -area, -delay, -power) — higher is better
        def objectives(ind):
            c = ind.correctness_score
            if ind.ppa:
                return (c, -ind.ppa.area, -ind.ppa.delay, -ind.ppa.power)
            return (c, float('-inf'), float('-inf'), float('-inf'))

        objs = [objectives(ind) for ind in pool]

        domination_count = [0] * n
        dominated_set = [[] for _ in range(n)]

        for i in range(n):
            for j in range(i + 1, n):
                if self._dominates(objs[i], objs[j]):
                    dominated_set[i].append(j)
                    domination_count[j] += 1
                elif self._dominates(objs[j], objs[i]):
                    dominated_set[j].append(i)
                    domination_count[i] += 1

        # Build fronts
        levels = []
        current_front = [i for i in range(n) if domination_count[i] == 0]

        while current_front:
            levels.append([pool[i] for i in current_front])
            next_front = []
            for i in current_front:
                for j in dominated_set[i]:
                    domination_count[j] -= 1
                    if domination_count[j] == 0:
                        next_front.append(j)
            current_front = next_front

        return levels

    @staticmethod
    def _dominates(a: tuple, b: tuple) -> bool:
        """A dominates B if A >= B on all dimensions and > on at least one."""
        at_least_one_better = False
        for ai, bi in zip(a, b):
            if ai < bi:
                return False
            if ai > bi:
                at_least_one_better = True
        return at_least_one_better

    def _proportional_allocate(self, levels: List[List[Individual]], N: int) -> List[Individual]:
        """POET-style 1/k proportional allocation with cascade."""
        if not levels:
            return []

        # Compute weights
        weights = [1.0 / (k + 1) for k in range(len(levels))]
        total_w = sum(weights)
        slots = [round(w / total_w * N) for w in weights]

        # Adjust to sum to N
        diff = sum(slots) - N
        if diff > 0:
            # Reduce from lowest-priority levels, allowing reduction to 0
            for i in range(len(slots) - 1, -1, -1):
                reduce = min(diff, slots[i])
                slots[i] -= reduce
                diff -= reduce
                if diff == 0:
                    break
        elif diff < 0:
            slots[0] += abs(diff)

        survivors = []
        remainder = 0
        for level_idx, level in enumerate(levels):
            available = slots[level_idx] + remainder
            if len(level) <= available:
                survivors.extend(level)
                remainder = available - len(level)
            else:
                survivors.extend(level[:available])
                remainder = 0

            if len(survivors) >= N:
                break

        # Backfill: proportional truncation may leave survivors < N.
        # Fill remaining spots sequentially (F1 → F2 → ...) from unselected individuals.
        if len(survivors) < N:
            selected = {id(ind) for ind in survivors}
            for level in levels:
                for ind in level:
                    if id(ind) not in selected:
                        survivors.append(ind)
                        if len(survivors) >= N:
                            break
                if len(survivors) >= N:
                    break

        return survivors[:N]

    def _sequential_allocate(self, levels: List[List[Individual]], N: int) -> List[Individual]:
        """Fill from F1 downward."""
        survivors = []
        for level in levels:
            if len(survivors) + len(level) <= N:
                survivors.extend(level)
            else:
                remaining = N - len(survivors)
                survivors.extend(level[:remaining])
                break
        return survivors

    def get_pareto_front(self, correct_only: bool = True) -> List[Individual]:
        """Return F1 individuals."""
        pool = self.individuals
        if correct_only:
            pool = [ind for ind in pool if ind.correctness_score >= 1.0]
        if not pool:
            return []
        levels = self._non_dominated_sort(pool)
        return levels[0] if levels else []

    PPA_METRICS = {
        "area":  lambda p: p.area,
        "delay": lambda p: p.delay,
        "power": lambda p: p.power,
        "adp":   lambda p: p.area * p.delay,
        "pdp":   lambda p: p.power * p.delay,
        "adpwr": lambda p: p.area * p.delay * p.power,
    }

    def get_best_correct(self, metric: str = "adp") -> Optional[Individual]:
        """Return individual with best PPA by given metric among correctness==1.0."""
        correct = [ind for ind in self.individuals if ind.correctness_score >= 1.0]
        if not correct:
            # Fall back to highest correctness
            if self.individuals:
                return max(self.individuals, key=lambda i: i.correctness_score)
            return None

        key_fn = self.PPA_METRICS.get(metric, self.PPA_METRICS["adp"])

        def ppa_score(ind):
            if ind.ppa:
                return key_fn(ind.ppa)
            return float('inf')

        return min(correct, key=ppa_score)

    def get_best_per_metric(self) -> dict:
        """Return {metric_name: Individual} for all 5 metrics.
        Only from correctness>=1.0 and ppa is not None."""
        pool = [ind for ind in self.individuals
                if ind.correctness_score >= 1.0 and ind.ppa is not None]
        if not pool:
            return {}

        result = {}
        for name, key_fn in self.PPA_METRICS.items():
            result[name] = min(pool, key=lambda ind, fn=key_fn: fn(ind.ppa))
        return result
