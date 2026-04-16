import os
import json
import logging
from datetime import datetime


class EvolutionLogger:
    def __init__(self, experiment_dir: str, design_name: str):
        self.design_dir = os.path.join(experiment_dir, design_name)
        os.makedirs(self.design_dir, exist_ok=True)

        self.logger = logging.getLogger(f"coevo.{design_name}")
        if not self.logger.handlers:
            fh = logging.FileHandler(os.path.join(self.design_dir, "evolution.log"))
            fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
            self.logger.addHandler(fh)
            sh = logging.StreamHandler()
            sh.setFormatter(logging.Formatter("%(message)s"))
            self.logger.addHandler(sh)
            self.logger.setLevel(logging.INFO)

        self.generation_log = []

    def set_level(self, level: str):
        self.logger.setLevel(getattr(logging, level.upper(), logging.INFO))

    def log_generation(self, gen: int, population, theta: float, stats: dict,
                       ref_ppa=None, best_metric: str = "adp"):
        scores = [ind.correctness_score for ind in population.individuals]
        best = max(scores) if scores else 0
        avg = sum(scores) / len(scores) if scores else 0
        perfect = sum(1 for s in scores if s >= 1.0)

        # PPA summary
        synth_ok = sum(1 for ind in population.individuals if ind.ppa is not None)
        ppa_str = f"synth={synth_ok}/{len(scores)}"

        best_ind = population.get_best_correct(best_metric)
        if best_ind and best_ind.ppa:
            p = best_ind.ppa
            if ref_ppa:
                a_pct = (p.area - ref_ppa.area) / ref_ppa.area * 100 if ref_ppa.area else 0
                d_pct = (p.delay - ref_ppa.delay) / ref_ppa.delay * 100 if ref_ppa.delay else 0
                w_pct = (p.power - ref_ppa.power) / ref_ppa.power * 100 if ref_ppa.power else 0
                ppa_str += f" best: area={a_pct:+.1f}% delay={d_pct:+.1f}% power={w_pct:+.1f}%"
            else:
                ppa_str += f" best: area={p.area:.1f} delay={p.delay:.2f} power={p.power:.1f}"

        entry = {
            "generation": gen, "theta": round(theta, 4),
            "pop_size": len(scores), "best_score": round(best, 4),
            "avg_score": round(avg, 4), "perfect_count": perfect,
            "synth_ok": synth_ok,
            "cost": stats.get("total_cost", 0),
        }
        self.generation_log.append(entry)

        self.logger.info(
            f"[Gen {gen}] theta={theta:.3f} best={best:.3f} avg={avg:.3f} "
            f"perfect={perfect}/{len(scores)} cost=${stats.get('total_cost', 0):.4f} "
            f"| {ppa_str}"
        )

    def log_individual(self, individual, generation: int):
        ind_dir = os.path.join(self.design_dir, "candidates")
        os.makedirs(ind_dir, exist_ok=True)
        with open(os.path.join(ind_dir, f"{individual.id}.v"), 'w') as f:
            f.write(individual.code)
        meta = {
            "id": individual.id, "generation": generation,
            "correctness": individual.correctness_score,
            "operator": individual.operator,
            "ppa": individual.ppa.__dict__ if individual.ppa else None,
        }
        with open(os.path.join(ind_dir, f"{individual.id}.json"), 'w') as f:
            json.dump(meta, f, indent=2)

    def log_cost(self, cost_summary: dict):
        self.logger.info(
            f"[Cost] tokens_in={cost_summary['total_input_tokens']} "
            f"tokens_out={cost_summary['total_output_tokens']} "
            f"cost=${cost_summary['total_cost']:.4f}"
        )

    def save_generation_log(self):
        with open(os.path.join(self.design_dir, "generation_log.json"), 'w') as f:
            json.dump(self.generation_log, f, indent=2)
