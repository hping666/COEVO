from dataclasses import dataclass, field
from typing import Optional, List


@dataclass
class PPAMetrics:
    area: float         # um^2
    delay: float        # ns
    power: float        # uW
    num_cells: int = 0
    num_wires: int = 0


@dataclass
class Individual:
    id: str
    design_name: str
    thought: str
    code: str
    correctness_score: float = 0.0
    passed_checks: int = 0
    total_checks: int = 0
    original_tb_pass: bool = False
    error_feedback: str = ""
    ppa: Optional[PPAMetrics] = None
    synth_diagnosis: Optional[str] = None
    parent_ids: List[str] = field(default_factory=list)
    operator: str = ""
    generation: int = 0
