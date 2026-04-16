import os
import json
import logging
import math
from concurrent.futures import ThreadPoolExecutor, as_completed

from coevo.core.individual import Individual
from coevo.core.population import Population
from coevo.core.fitness import Evaluator
from coevo.core.strategy_memory import StrategyMemory
from coevo.datasets.base import DatasetAdapter, DesignInfo
from coevo.llm.api_client import LLMClient
from coevo.llm.response_parser import parse_llm_response
from coevo.operators.initialization import InitializationOperator
from coevo.operators.correctness_ops import FixOperator, SimplifyOperator
from coevo.operators.ppa_ops import OptimizeOperator, RestructureOperator, ExploreOperator
from coevo.operators.cross_ops import PPAAwareFixOperator, ArchitectureFusionOperator
from coevo.operators.selector import OperatorSelector
from coevo.utils.file_io import ensure_dir
from coevo.utils.logger import EvolutionLogger

logger = logging.getLogger("coevo.evolution")


class CoevoEvolution:
    def __init__(self, design: DesignInfo, config: dict, experiment_dir: str,
                 adapter: DatasetAdapter):
        self.design = design
        self.design_name = design.name
        self.design_dir = design.dir
        self.config = config
        self.experiment_dir = experiment_dir
        self.adapter = adapter

        self.llm = LLMClient(config['models'], config.get('llm', {}))
        self.evaluator = Evaluator(design, config, adapter)
        self.memory = StrategyMemory(config.get('strategy_memory', {}))

        all_ops = [
            FixOperator(), SimplifyOperator(),
            OptimizeOperator(), RestructureOperator(), ExploreOperator(),
            PPAAwareFixOperator(), ArchitectureFusionOperator()
        ]
        self.operator_selector = OperatorSelector(config, all_ops)
        self.population = Population(config['evolution']['population_size'], config)

        self.spec = adapter.load_spec(design)
        self.module_header = adapter.load_module_header(design)

        # Install dataset-specific system message for all prompt builders
        from coevo.llm.prompt_templates import set_active_system_message
        set_active_system_message(adapter.get_system_message())

        self.evo_logger = EvolutionLogger(experiment_dir, self.design_name)
        self.evo_logger.set_level(config.get('logging', {}).get('level', 'INFO'))

    def run(self) -> dict:
        """Execute COEVO for one design. Return results dict."""
        self.memory.reset()
        self.best_metric = self.config['evolution'].get('best_metric', 'adp')

        # Pre-compute reference PPA for logging and final comparison
        self.ref_ppa = self.evaluator.evaluate_reference_ppa()

        # Phase 1: Initialize population
        logger.info(f"[{self.design_name}] Phase 1: Initializing population")
        self._initialize_population()
        logger.info(f"[{self.design_name}] Population initialized with {len(self.population.individuals)} individuals")

        # Save all initial candidates if configured
        if self.config.get('logging', {}).get('save_all_candidates', False):
            for ind in self.population.individuals:
                self.evo_logger.log_individual(ind, 0)

        # Phase 2: Evolution loop
        max_gen = self.config['evolution']['max_generations']
        for gen in range(max_gen):
            logger.info(f"[{self.design_name}] Generation {gen}/{max_gen}")
            theta = self._compute_adaptive_gate(gen)
            offspring = self._generate_offspring(gen)

            # Save all offspring candidates if configured
            if self.config.get('logging', {}).get('save_all_candidates', False):
                for ind in offspring:
                    self.evo_logger.log_individual(ind, gen)

            if self.config['evaluation']['formal']['enabled']:
                offspring = self._attempt_formal_repair(offspring, gen)

            self.population.survivor_selection(offspring, theta)
            self.evo_logger.log_generation(gen, self.population, theta,
                                           self.llm.get_usage_summary(),
                                           self.ref_ppa, self.best_metric)

            # Log pareto front individuals
            if self.config.get('logging', {}).get('save_pareto_candidates', True):
                for ind in self.population.get_pareto_front(correct_only=False):
                    self.evo_logger.log_individual(ind, gen)

            # Early stop if perfect score found with good PPA
            best = self.population.get_best_correct(self.best_metric)
            if best and best.correctness_score >= 1.0 and best.ppa:
                logger.info(f"[{self.design_name}] Perfect correctness with PPA at gen {gen}")

        # Phase 3: Compile results
        self.evo_logger.save_generation_log()
        self.evo_logger.log_cost(self.llm.get_usage_summary())
        return self._compile_results()

    def _initialize_population(self):
        """Generate initial population using multi-architecture strategies."""
        init_op = InitializationOperator(self.config)
        strategies = init_op.select_strategies(self.spec, self.llm, self.config)
        logger.info(f"[{self.design_name}] Using strategies: {strategies}")

        candidates_per = math.ceil(self.config['evolution']['population_size'] / len(strategies))
        workers = self.config['evolution'].get('parallel_workers', 1)

        # Build task list: (strategy,) for each candidate
        tasks = []
        for strategy in strategies:
            for _ in range(candidates_per):
                tasks.append(strategy)

        if workers <= 1:
            # Sequential: original logic
            for strategy in tasks:
                try:
                    ind = self._init_one_candidate(init_op, strategy)
                    if ind:
                        self.population.add(ind)
                        logger.info(f"  init_{strategy}: score={ind.correctness_score:.3f}")
                except Exception as e:
                    logger.warning(f"  init_{strategy} failed: {e}")
        else:
            # Parallel
            with ThreadPoolExecutor(max_workers=workers) as pool:
                futures = {pool.submit(self._init_one_candidate, init_op, s): s for s in tasks}
                for future in as_completed(futures):
                    strategy = futures[future]
                    try:
                        ind = future.result()
                        if ind:
                            self.population.add(ind)
                            logger.info(f"  init_{strategy}: score={ind.correctness_score:.3f}")
                    except Exception as e:
                        logger.warning(f"  init_{strategy} failed: {e}")

    def _init_one_candidate(self, init_op, strategy: str):
        """Generate and evaluate one initial candidate. Thread-safe."""
        prompt = init_op.build_initial_prompt(self.spec, self.module_header, strategy)
        response = self.llm.call(
            self.config['llm']['generation_model'], prompt,
            temperature=self.config['llm']['temperature']['generation'])
        thought, code = parse_llm_response(response['content'])
        if code:
            return self.evaluator.evaluate(thought, code, generation=0,
                                           operator=f"init_{strategy}")
        return None

    def _generate_offspring(self, generation: int) -> list:
        # Near-miss detection drives selector.set_near_miss_mode() for this generation.
        # Guarded by near_miss_mode.enabled + explore_boost, both default False -> no-op for RTLLM.
        nm_cfg = self.config['evolution'].get('near_miss_mode', {}) or {}
        if nm_cfg.get('enabled', False) and nm_cfg.get('explore_boost', False):
            threshold = nm_cfg.get('repair_threshold', 0.90)
            persistent = nm_cfg.get('persistent_gens', 2)
            best_score = max(
                (ind.correctness_score for ind in self.population.individuals),
                default=0.0)
            if threshold <= best_score < 1.0:
                self._nm_counter = getattr(self, '_nm_counter', 0) + 1
            else:
                self._nm_counter = 0
            self.operator_selector.set_near_miss_mode(self._nm_counter >= persistent)

        workers = self.config['evolution'].get('parallel_workers', 1)
        n = self.config['evolution']['offspring_count']

        if workers <= 1:
            return self._generate_offspring_sequential(generation, n)
        else:
            return self._generate_offspring_parallel(generation, n, workers)

    def _generate_offspring_sequential(self, generation: int, n: int) -> list:
        """Original sequential logic — unchanged behavior."""
        offspring = []
        for i in range(n):
            try:
                operator = self.operator_selector.select()

                if operator.requires_two_parents:
                    parents = list(self.population.select_two_parents())
                else:
                    parents = [self.population.select_parent()]

                memory_text = ""
                if self.config.get('strategy_memory', {}).get('enabled', False):
                    entries = self.memory.retrieve(operator.category)
                    memory_text = self.memory.format_for_prompt(entries)

                prompt = operator.build_prompt(parents, self.spec,
                                               self.module_header, memory_text)
                response = self.llm.call(
                    self.config['llm']['mutation_model'], prompt,
                    temperature=self.config['llm']['temperature']['mutation'])
                thought, code = parse_llm_response(response['content'])

                if not code:
                    continue

                ind = self.evaluator.evaluate(thought, code, generation=generation,
                                               parent_ids=[p.id for p in parents],
                                               operator=operator.name)

                # Unified repair: synthesis errors + functional errors
                has_synth_issue = ind.ppa is None and ind.synth_diagnosis
                has_func_issue = ind.correctness_score < 1.0 and ind.error_feedback
                if has_synth_issue or has_func_issue:
                    ind = self._attempt_repair(ind, generation)

                # Record memory and reward BEFORE penalty (use true correctness)
                self.memory.record(ind, parents, operator.name)
                self.operator_selector.update_reward(operator, ind, parents)

                # Apply synth_failure_mode penalty (after recording)
                if (ind.ppa is None
                        and self.config['evolution'].get('synth_failure_mode', 'keep') == 'zero'
                        and self.evaluator.design_name not in self.evaluator.ppa_eval.skip_list):
                    ind.correctness_score = 0.0

                offspring.append(ind)

                logger.debug(f"  {operator.name}: score={ind.correctness_score:.3f}")
            except Exception as e:
                logger.warning(f"  Offspring {i} failed: {e}")

        return offspring

    def _generate_offspring_parallel(self, generation: int, n: int, workers: int) -> list:
        """Parallel: pre-select operators/parents, execute concurrently, batch update."""
        # Phase 1: Pre-select operators, parents, and prompts (sequential, fast)
        tasks = []
        for i in range(n):
            operator = self.operator_selector.select()
            if operator.requires_two_parents:
                parents = list(self.population.select_two_parents())
            else:
                parents = [self.population.select_parent()]

            memory_text = ""
            if self.config.get('strategy_memory', {}).get('enabled', False):
                entries = self.memory.retrieve(operator.category)
                memory_text = self.memory.format_for_prompt(entries)

            prompt = operator.build_prompt(parents, self.spec,
                                           self.module_header, memory_text)
            tasks.append((i, operator, parents, prompt))

        # Phase 2: Execute LLM call + eval + repair in parallel
        results = []
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(self._produce_one_offspring, generation, operator, parents, prompt): (i, operator, parents)
                for i, operator, parents, prompt in tasks
            }
            for future in as_completed(futures):
                i, operator, parents = futures[future]
                try:
                    ind = future.result()
                    if ind:
                        results.append((operator, parents, ind))
                        logger.debug(f"  {operator.name}: score={ind.correctness_score:.3f}")
                except Exception as e:
                    logger.warning(f"  Offspring {i} failed: {e}")

        # Phase 3: Batch update memory/reward, then apply penalty (sequential)
        offspring = []
        for operator, parents, ind in results:
            # Record memory and reward BEFORE penalty (use true correctness)
            self.memory.record(ind, parents, operator.name)
            self.operator_selector.update_reward(operator, ind, parents)

            # Apply synth_failure_mode penalty (after recording)
            if (ind.ppa is None
                    and self.config['evolution'].get('synth_failure_mode', 'keep') == 'zero'
                    and self.evaluator.design_name not in self.evaluator.ppa_eval.skip_list):
                ind.correctness_score = 0.0

            offspring.append(ind)

        return offspring

    def _produce_one_offspring(self, generation: int, operator, parents: list, prompt: list):
        """LLM call + evaluate + repair for one offspring. Thread-safe."""
        response = self.llm.call(
            self.config['llm']['mutation_model'], prompt,
            temperature=self.config['llm']['temperature']['mutation'])
        thought, code = parse_llm_response(response['content'])

        if not code:
            return None

        ind = self.evaluator.evaluate(thought, code, generation=generation,
                                       parent_ids=[p.id for p in parents],
                                       operator=operator.name)

        # Unified repair
        has_synth_issue = ind.ppa is None and ind.synth_diagnosis
        has_func_issue = ind.correctness_score < 1.0 and ind.error_feedback
        if has_synth_issue or has_func_issue:
            ind = self._attempt_repair(ind, generation)

        # Penalty is deferred to Phase 3 (after memory.record) in parallel mode
        return ind

    def _attempt_repair(self, individual: Individual, generation: int) -> Individual:
        """Unified repair: fix synthesis errors and/or functional errors.

        Two modes:
        (1) Standard — loops `repair_attempts` with identical prompt (original behavior).
        (2) Near-miss (config-gated by near_miss_mode.enabled): when the individual
            sits at a purely functional near-miss [threshold, 1.0) with ppa already
            succeeded, runs `near_miss_mode.repair_attempts` iterations rotating a
            strategy hint (surgical fix -> re-read spec -> simplify) to diversify
            attempts instead of repeating the same fix pattern. RTLLM-safe: when
            enabled=False the near-miss branch is never taken.
        """
        from coevo.llm.prompt_templates import build_repair_prompt

        nm_cfg = self.config['evolution'].get('near_miss_mode', {}) or {}
        nm_enabled = nm_cfg.get('enabled', False)
        nm_threshold = nm_cfg.get('repair_threshold', 1.0)
        nm_attempts = nm_cfg.get('repair_attempts', 3)

        near_miss = (
            nm_enabled
            and nm_threshold < 1.0
            and individual.ppa is not None           # synth already OK
            and bool(individual.error_feedback)       # purely functional miss
            and nm_threshold <= individual.correctness_score < 1.0
        )

        if near_miss:
            hints = [
                "STRATEGY HINT: Apply minimal, surgical fixes — change only the specific "
                "lines that produce the failing samples; do not rewrite the architecture.",
                "STRATEGY HINT: Re-read the specification from scratch. The current code "
                "may have a subtle semantic mismatch (reset polarity, edge sensitivity, "
                "state encoding, or output convention). Consider a different interpretation.",
                "STRATEGY HINT: Simplify the state/control logic. Remove redundant flags, "
                "intermediate signals, or special cases that are not required by the spec.",
            ]
            n = min(nm_attempts, len(hints))
            for attempt in range(n):
                if individual.correctness_score >= 1.0:
                    break
                try:
                    prompt = build_repair_prompt(individual, self.spec, self.module_header)
                    if prompt and isinstance(prompt[-1], dict) and 'content' in prompt[-1]:
                        prompt[-1] = {
                            **prompt[-1],
                            'content': prompt[-1]['content'] + "\n\n" + hints[attempt],
                        }
                    response = self.llm.call(
                        self.config['llm']['mutation_model'], prompt,
                        temperature=self.config['llm']['temperature']['repair'])
                    thought, code = parse_llm_response(response['content'])
                    if code:
                        repaired = self.evaluator.evaluate(
                            thought, code, generation=generation,
                            parent_ids=[individual.id], operator="repair_nm")
                        improved = (
                            repaired.correctness_score > individual.correctness_score
                            or (repaired.correctness_score >= individual.correctness_score
                                and repaired.ppa is not None and individual.ppa is None)
                        )
                        if improved:
                            individual = repaired
                except Exception as e:
                    logger.debug(f"Near-miss repair attempt {attempt} failed: {e}")
            return individual

        # Standard repair (original code path, behavior unchanged)
        for attempt in range(self.config['evolution']['repair_attempts']):
            has_synth_issue = individual.ppa is None and individual.synth_diagnosis
            has_func_issue = individual.correctness_score < 1.0 and individual.error_feedback
            if not has_synth_issue and not has_func_issue:
                break
            try:
                prompt = build_repair_prompt(individual, self.spec, self.module_header)
                response = self.llm.call(
                    self.config['llm']['mutation_model'], prompt,
                    temperature=self.config['llm']['temperature']['repair'])
                thought, code = parse_llm_response(response['content'])
                if code:
                    repaired = self.evaluator.evaluate(thought, code, generation=generation,
                                                        parent_ids=[individual.id],
                                                        operator="repair")
                    # Accept if: better correctness, or same correctness + gained PPA
                    improved = (
                        repaired.correctness_score > individual.correctness_score
                        or (repaired.correctness_score >= individual.correctness_score
                            and repaired.ppa is not None and individual.ppa is None)
                    )
                    if improved:
                        individual = repaired
            except Exception as e:
                logger.debug(f"Repair attempt {attempt} failed: {e}")
        return individual

    def _compute_adaptive_gate(self, generation: int) -> float:
        """Primary: fixed annealing. Fallback: P25-based if no one passes primary."""
        cfg = self.config['evolution']['gate']
        max_gen = self.config['evolution']['max_generations']
        progress = generation / max_gen if max_gen > 0 else 0
        theta_primary = cfg['theta_min'] + (cfg['theta_max'] - cfg['theta_min']) * (
            progress ** cfg['annealing_exponent'])

        max_score = max((ind.correctness_score for ind in self.population.individuals), default=0)
        if max_score >= theta_primary:
            return theta_primary

        scores = sorted([ind.correctness_score for ind in self.population.individuals])
        percentile = cfg.get('fallback_percentile', 0.25)
        p_index = max(0, int(len(scores) * percentile))
        p25 = scores[p_index] if scores else 0.0
        return max(p25 - cfg['fallback_margin'], 0.0)

    def _attempt_formal_repair(self, offspring: list, generation: int) -> list:
        """Placeholder for formal repair. Currently disabled by default."""
        return offspring

    def _compile_results(self) -> dict:
        """Save results. Synthesize reference for PPA comparison."""
        design_result_dir = os.path.join(self.experiment_dir, self.design_name)
        ensure_dir(design_result_dir)

        ref_ppa = self.ref_ppa
        best = self.population.get_best_correct(self.best_metric)
        pareto = self.population.get_pareto_front(correct_only=True)

        # Re-evaluate best with original testbench (fresh, not cached from evolution)
        if best:
            best.original_tb_pass = self.evaluator.correctness_eval.evaluate_original_tb(
                best.code, self.design, self.evaluator.module_name)

        # Save best per PPA metric (5 files: best_area.v, best_delay.v, etc.)
        bests_per_metric = self.population.get_best_per_metric()
        for metric_name, ind in bests_per_metric.items():
            with open(os.path.join(design_result_dir, f"best_{metric_name}.v"), 'w') as f:
                f.write(ind.code)

        # Save global best (by configured metric)
        if best:
            with open(os.path.join(design_result_dir, "best_correct.v"), 'w') as f:
                f.write(best.code)

            # Save PPA comparison
            comparison = {
                'best_id': best.id,
                'best_metric': self.best_metric,
                'correctness': best.correctness_score,
                'best_ppa': best.ppa.__dict__ if best.ppa else None,
                'ref_ppa': ref_ppa.__dict__ if ref_ppa else None,
            }
            with open(os.path.join(design_result_dir, "ppa_comparison.json"), 'w') as f:
                json.dump(comparison, f, indent=2)

        # Save pareto front
        if pareto:
            pareto_dir = os.path.join(design_result_dir, "pareto")
            ensure_dir(pareto_dir)
            for ind in pareto:
                with open(os.path.join(pareto_dir, f"{ind.id}.v"), 'w') as f:
                    f.write(ind.code)

        # Save summary
        # Final pass uses original TB (RTLLM standard); enhanced TB is for evolution only
        summary = {
            'design': self.design_name,
            'pass': best is not None and best.original_tb_pass,
            'enhanced_score': best.correctness_score if best else 0,
            'original_tb_pass': best.original_tb_pass if best else False,
            'passed_checks': best.passed_checks if best else 0,
            'total_checks': best.total_checks if best else 0,
            'best_ppa': best.ppa.__dict__ if best and best.ppa else None,
            'ref_ppa': ref_ppa.__dict__ if ref_ppa else None,
            'pareto_count': len(pareto),
            'cost': self.llm.get_usage_summary()
        }
        with open(os.path.join(design_result_dir, "summary.json"), 'w') as f:
            json.dump(summary, f, indent=2)

        return summary
