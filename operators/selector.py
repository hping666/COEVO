import math
import random
from typing import List

from coevo.operators.base import BaseOperator


class OperatorSelector:
    def __init__(self, config: dict, operators: List[BaseOperator]):
        self.operators = operators
        ucb_cfg = config['evolution']['ucb']
        self.c = ucb_cfg['exploration_coeff']
        self.tau = ucb_cfg['softmax_temperature']
        init_reward = ucb_cfg['initial_reward']

        # Near-miss explore boost (config-gated; default off = no behavior change).
        nm_cfg = config['evolution'].get('near_miss_mode', {}) or {}
        self.nm_boost_enabled = nm_cfg.get('explore_boost', False)
        self.near_miss_mode = False   # toggled per generation by evolution loop

        self.Q = {op.name: init_reward for op in operators}
        self.N = {op.name: 0 for op in operators}
        self.total = 0

    def set_near_miss_mode(self, mode: bool):
        """Toggle near-miss explore boost for subsequent select() calls."""
        self.near_miss_mode = mode

    def select(self) -> BaseOperator:
        """UCB-Softmax adaptive operator selection.

        When both `near_miss_mode.explore_boost` is enabled AND the evolution loop
        has flagged this generation as near-miss, blend the softmax probabilities
        50/50 with an explore-heavy prior (explore=0.4, ppa_aware_fix=0.3, rest=0.3)
        to diversify exploration when best individual is stuck at [threshold, 1.0).
        Default OFF -> original UCB-Softmax behavior preserved.
        """
        scores = {}
        for op in self.operators:
            if self.N[op.name] == 0:
                scores[op.name] = float('inf')
            else:
                scores[op.name] = self.Q[op.name] + self.c * math.sqrt(
                    math.log(self.total + 1) / self.N[op.name])

        # Handle inf scores (untried operators)
        inf_ops = [k for k, v in scores.items() if v == float('inf')]
        if inf_ops:
            chosen_name = random.choice(inf_ops)
        else:
            max_s = max(scores.values())
            exp_scores = {k: math.exp((v - max_s) / self.tau) for k, v in scores.items()}
            total_exp = sum(exp_scores.values())
            probs = {k: v / total_exp for k, v in exp_scores.items()}

            # Near-miss explore-heavy blend (gated; no-op when disabled).
            if (self.nm_boost_enabled and self.near_miss_mode
                    and 'explore' in probs and 'ppa_aware_fix' in probs):
                boost = {}
                rest_names = [n for n in probs if n not in ('explore', 'ppa_aware_fix')]
                boost['explore'] = 0.4
                boost['ppa_aware_fix'] = 0.3
                if rest_names:
                    share = 0.3 / len(rest_names)
                    for n in rest_names:
                        boost[n] = share
                # 50/50 blend with original softmax probs, then renormalize.
                probs = {k: 0.5 * probs[k] + 0.5 * boost.get(k, 0.0) for k in probs}
                s = sum(probs.values())
                if s > 0:
                    probs = {k: v / s for k, v in probs.items()}

            chosen_name = random.choices(list(probs.keys()), weights=list(probs.values()))[0]

        self.total += 1
        self.N[chosen_name] += 1
        return next(op for op in self.operators if op.name == chosen_name)

    def update_reward(self, operator: BaseOperator, offspring, parents: list):
        """Update Q-value based on offspring quality vs parents."""
        best_parent = max(parents, key=lambda p: p.correctness_score)
        reward = 0.0

        if operator.category == "correctness":
            if offspring.correctness_score > best_parent.correctness_score:
                reward = 1.0
        elif operator.category == "ppa":
            ppa_improved = False
            if offspring.ppa and best_parent.ppa:
                ppa_improved = (offspring.ppa.area < best_parent.ppa.area or
                                offspring.ppa.delay < best_parent.ppa.delay or
                                offspring.ppa.power < best_parent.ppa.power)
            if ppa_improved and offspring.correctness_score >= best_parent.correctness_score:
                reward = 1.0
        else:  # cross: graduated reward
            # Correctness improvement contributes up to 0.5
            if offspring.correctness_score > best_parent.correctness_score:
                reward += 0.5
            # PPA improvement or preservation contributes up to 0.5
            if offspring.ppa and best_parent.ppa:
                ppa_improved = (offspring.ppa.area < best_parent.ppa.area or
                                offspring.ppa.delay < best_parent.ppa.delay or
                                offspring.ppa.power < best_parent.ppa.power)
                ppa_preserved = (offspring.ppa.area <= best_parent.ppa.area and
                                 offspring.ppa.delay <= best_parent.ppa.delay and
                                 offspring.ppa.power <= best_parent.ppa.power)
                if ppa_preserved:
                    reward += 0.5
                elif ppa_improved:
                    reward += 0.25  # Partial: improved one metric but worsened another
            elif offspring.correctness_score >= best_parent.correctness_score and offspring.ppa is not None:
                reward += 0.25  # Gained synthesis success

        # Incremental average
        n = self.N[operator.name]
        if n > 0:
            self.Q[operator.name] += (reward - self.Q[operator.name]) / n
