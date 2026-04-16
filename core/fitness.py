import logging
import re
from uuid import uuid4

from coevo.core.individual import Individual
from coevo.datasets.base import DatasetAdapter, DesignInfo
from coevo.evaluation.correctness import CorrectnessEvaluator
from coevo.evaluation.ppa import PPAEvaluator

logger = logging.getLogger("coevo.fitness")


class Evaluator:
    def __init__(self, design: DesignInfo, config: dict, adapter: DatasetAdapter):
        self.design = design
        # Convenience aliases kept so existing callers (evolution.py) continue
        # to read self.design_name / self.design_dir without changes.
        self.design_name = design.name
        self.design_dir = design.dir
        self.config = config
        self.adapter = adapter
        self.correctness_eval = CorrectnessEvaluator(config, adapter)
        self.ppa_eval = PPAEvaluator(config, adapter)
        self.module_name = adapter.extract_module_name(design)

    def evaluate(self, thought: str, code: str, generation: int = 0,
                 parent_ids: list = None, operator: str = "") -> Individual:
        """Run correctness + PPA evaluation. Return a fully populated Individual."""
        corr = self.correctness_eval.evaluate(code, self.design, self.module_name)

        ppa = None
        synth_diag = None
        if corr['score'] > 0:
            if self.design_name in self.ppa_eval.skip_list:
                # Explicitly skipped (design is known to synthesize to 0 cells
                # or is otherwise unsynthesizable). Leave both ppa and
                # synth_diag as None so Pareto sort degrades cleanly to pure
                # correctness and neither repair nor PPA-operator prompts get
                # polluted with a spurious "synthesis failed" diagnosis.
                pass
            else:
                try:
                    ppa, yosys_log = self.ppa_eval.evaluate(code, self.module_name, self.design_name)
                    if ppa:
                        synth_diag = self.ppa_eval.extract_synthesis_diagnosis(yosys_log)
                    else:
                        # Synthesis genuinely failed — extract failure diagnosis for repair
                        synth_diag = self._extract_synth_failure_diagnosis(yosys_log)
                except Exception as e:
                    logger.warning(f"PPA evaluation failed: {e}")

        return Individual(
            id=f"gen{generation}_{operator}_{uuid4().hex[:6]}",
            design_name=self.design_name,
            thought=thought,
            code=code,
            correctness_score=corr['score'],
            passed_checks=corr['passed'],
            total_checks=corr['total'],
            original_tb_pass=corr.get('original_pass', False),
            error_feedback=corr['error_feedback'],
            ppa=ppa,
            synth_diagnosis=synth_diag,
            parent_ids=parent_ids or [],
            operator=operator,
            generation=generation
        )

    def _extract_synth_failure_diagnosis(self, yosys_log: str) -> str:
        """Extract key warnings/errors from Yosys log when synthesis fails."""
        if not yosys_log:
            return "Synthesis failed (no log available)"

        lines = []
        # Driver-driver conflicts
        conflicts = re.findall(r'Warning: Driver-driver conflict.*', yosys_log)
        if conflicts:
            lines.append(f"Driver-driver conflicts ({len(conflicts)} total):")
            for c in conflicts[:5]:
                lines.append(f"  {c.strip()}")
            if len(conflicts) > 5:
                lines.append(f"  ... and {len(conflicts) - 5} more")

        # Check for 0-cell result
        m = re.search(r'Number of cells:\s+(\d+)', yosys_log)
        if m and int(m.group(1)) == 0:
            lines.append("Result: 0 cells after synthesis (all logic optimized away)")

        # Yosys errors
        errors = re.findall(r'ERROR:.*', yosys_log)
        for e in errors[:3]:
            lines.append(f"Error: {e.strip()}")

        # Crash/abort
        if 'Aborted' in yosys_log or 'core dumped' in yosys_log:
            lines.append("Yosys crashed (possible unsupported construct)")

        return "\n".join(lines) if lines else "Synthesis failed (unknown reason)"

    def evaluate_reference_ppa(self):
        """Synthesize reference RTL for baseline PPA. Called only at results phase."""
        ref_code = self.adapter.load_reference_code(self.design)
        if not ref_code:
            return None
        try:
            ppa, _ = self.ppa_eval.evaluate(ref_code, self.module_name, self.design_name)
            return ppa
        except Exception as e:
            logger.warning(f"Reference PPA evaluation failed: {e}")
            return None
