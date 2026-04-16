import tempfile
import os
import re
import logging
import shlex
from typing import List, Optional, Tuple

from coevo.utils.timeout import run_with_timeout

logger = logging.getLogger("coevo.correctness")


class CorrectnessEvaluator:
    def __init__(self, config: dict, adapter=None):
        self.iverilog = config['paths']['iverilog_binary']
        self.vvp = config['paths']['vvp_binary']
        self.timeout = config['evaluation']['correctness']['simulation_timeout']
        self.use_enhanced = config['evaluation']['correctness']['use_enhanced_testbench']
        self.use_original = config['evaluation']['correctness']['use_original_testbench']
        # Focused VE bucket feedback (default off -> original behavior preserved).
        ff_cfg = config['evaluation']['correctness'].get('focused_feedback', {}) or {}
        self.focused_feedback = ff_cfg.get('enabled', False)
        self.focused_top_k = ff_cfg.get('top_k', 2)
        # Cache of {tb_path: [(sig_name, width), ...] | None} — populated lazily
        # by _extract_tb_signals(). Only VE-style bucket TBs yield a non-None
        # entry; RTLLM TBs (no fg_ff_dut_v concat) deterministically cache None.
        self._tb_signal_cache: dict = {}
        if adapter is None:
            # Default to RTLLM for backward compatibility (preserves prior behavior).
            from coevo.datasets.rtllm import RTLLMAdapter
            adapter = RTLLMAdapter()
        self.adapter = adapter

    def evaluate(self, candidate_code: str, design, module_name: str) -> dict:
        """Run correctness evaluation. ``design`` is a DesignInfo.

        Returns a score dict with keys:
            score, passed, total, original_pass, error_feedback, compile_error
        """
        result = {
            'score': 0.0, 'passed': 0, 'total': 0,
            'original_pass': False, 'error_feedback': '', 'compile_error': ''
        }

        cand_ext = self.adapter.CODE_FILE_EXT or 'v'
        work_dir = self.adapter.get_design_working_dir(design)

        with tempfile.TemporaryDirectory() as tmp:
            cand_path = os.path.join(tmp, f"{module_name}.{cand_ext}")
            with open(cand_path, 'w') as f:
                f.write(candidate_code)

            # Enhanced testbench
            if self.use_enhanced:
                tb_enhanced = self.adapter.get_enhanced_tb_path(design)
                if tb_enhanced and os.path.exists(tb_enhanced):
                    sim_result, compile_stderr = self._run_simulation(
                        tb_enhanced, cand_path, tmp, "enhanced",
                        extra_files=None, cwd=work_dir)
                    if sim_result is None:
                        result['compile_error'] = "Compilation failed"
                        result['error_feedback'] = (
                            "[COMPILE ERROR]\n" + compile_stderr[:500]
                            if compile_stderr else "Compilation failed (no details)")
                        return result
                    parsed = self._parse_forge_output(
                        sim_result.stdout + sim_result.stderr,
                        tb_path=tb_enhanced)
                    result.update(parsed)

            # Original testbench (binary check)
            if self.use_original:
                tb_original = self.adapter.get_original_tb_path(design)
                if tb_original and os.path.exists(tb_original):
                    extra_files = self.adapter.get_original_tb_extra_files(design)
                    orig_result, _ = self._run_simulation(
                        tb_original, cand_path, tmp, "original",
                        extra_files=extra_files, cwd=work_dir)
                    if orig_result:
                        result['original_pass'] = self.adapter.check_original_tb_result(
                            orig_result.stdout)

        return result

    def _run_simulation(self, tb_path: str, cand_path: str, tmp_dir: str, tag: str,
                        extra_files: Optional[List[str]] = None,
                        cwd: Optional[str] = None):
        """Compile with iverilog, run with vvp.
        Return (CompletedProcess, "") on success, or (None, stderr) on compile failure."""
        tb_path = os.path.abspath(tb_path)
        cand_path = os.path.abspath(cand_path)
        sim_out = os.path.join(tmp_dir, f"sim_{tag}")

        # Assemble compile command with adapter-provided flags and extra files.
        parts = [self.iverilog]
        for flag in self.adapter.IVERILOG_FLAGS:
            parts.append(flag)
        parts += ["-o", shlex.quote(sim_out),
                  shlex.quote(tb_path), shlex.quote(cand_path)]
        if extra_files:
            for ef in extra_files:
                parts.append(shlex.quote(os.path.abspath(ef)))
        compile_cmd = " ".join(parts)

        comp = run_with_timeout(compile_cmd, timeout=30)
        if comp.returncode != 0:
            logger.debug(f"Compile failed ({tag}): {comp.stderr[:200]}")
            return None, comp.stderr or ""
        # Run vvp with cwd=design_dir so $readmemh etc. can find auxiliary files
        run_cwd = cwd or os.path.dirname(tb_path)
        result = run_with_timeout(f"{self.vvp} {shlex.quote(sim_out)}",
                                  timeout=self.timeout, cwd=run_cwd)
        return result, ""

    # ------------------------------------------------------------------
    # Helpers for VE-style focused_feedback: decode concatenated-port hex
    # into per-signal values. Strictly optional — any failure falls back
    # to the original raw-hex behavior. RTLLM is unaffected because Path A
    # returns before reaching the code paths that use these helpers.
    # ------------------------------------------------------------------
    def _extract_tb_signals(self, tb_path: str) -> Optional[List[Tuple[str, int]]]:
        """Parse an enhanced TB for the ``_dut`` signals in concatenation order.

        Returns a list of ``(name, width)`` or ``None`` if the TB doesn't
        follow the VE bucket-TB layout (e.g. RTLLM TBs don't have
        ``fg_ff_dut_v[fg_b] = { ... };``). Result is cached per path.
        """
        if tb_path is None:
            return None
        if tb_path in self._tb_signal_cache:
            return self._tb_signal_cache[tb_path]

        sig_order: Optional[List[Tuple[str, int]]] = None
        try:
            with open(tb_path) as f:
                text = f.read()
            # Authoritative order: pull names from the fg_ff_dut_v concat.
            mc = re.search(r'fg_ff_dut_v\[\s*fg_b\s*\]\s*=\s*\{([^}]+)\}', text)
            if mc:
                concat_names: List[str] = []
                for tok in mc.group(1).split(','):
                    tok = tok.strip()
                    if tok.endswith('_dut'):
                        concat_names.append(tok[:-4])
                parsed: List[Tuple[str, int]] = []
                for name in concat_names:
                    mw = re.search(
                        rf'\bwire\b(?:\s*\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s+'
                        rf'{re.escape(name)}_dut\b',
                        text)
                    if mw is None:
                        parsed = None  # type: ignore
                        break
                    if mw.group(1) is not None:
                        hi = int(mw.group(1)); lo = int(mw.group(2))
                        width = abs(hi - lo) + 1
                    else:
                        width = 1
                    parsed.append((name, width))
                if parsed:
                    sig_order = parsed
        except Exception as exc:
            logger.debug(f"_extract_tb_signals({tb_path}) failed: {exc}")
            sig_order = None

        self._tb_signal_cache[tb_path] = sig_order
        return sig_order

    def _decode_concat_hex(
        self,
        hex_str: str,
        signals: List[Tuple[str, int]],
    ) -> Optional[dict]:
        """Split a concatenated hex into per-signal ``0x..`` values.

        Signals are given in MSB-first order (matches Verilog concat
        semantics: ``{a,b,c}`` puts ``a`` at the highest bits). Returns
        ``{name: "0xFF"}`` or ``None`` on any failure.
        """
        try:
            val = int(hex_str, 16)
        except (ValueError, TypeError):
            return None
        total = sum(w for _, w in signals)
        if total <= 0:
            return None
        out: dict = {}
        bit_pos = total
        for name, width in signals:
            bit_pos -= width
            mask = (1 << width) - 1
            field = (val >> bit_pos) & mask
            hex_width = max(1, (width + 3) // 4)
            out[name] = f"0x{field:0{hex_width}x}"
        return out

    def _parse_forge_output(self, stdout: str, tb_path: Optional[str] = None) -> dict:
        """Parse [FORGE_RESULT] plus one of two feedback styles:

        * RTLLM style — per-check FAIL lines:
              [FORGE_CHECK N] FAIL: DUT ... GOLD ...
          (emitted by ``RTLLM/**/testbench_enhanced.v``).
        * VerilogEval style — bucket coverage + first-fail snapshots:
              [FORGE_BUCKET] A_reset=5/5 B_steady=50/50 ...
              [FORGE_FIRSTFAIL] bucket=G_pulse_edge cyc=62 in=1 dut=1 ref=0
              [FORGE_SCORE_WEIGHTED] 0.8167
          (emitted by ``coevo/tb_gen/template.py``).

        RTLLM path always wins when both are present (backwards compatible).
        """
        result = {'score': 0.0, 'passed': 0, 'total': 0, 'error_feedback': ''}

        if "TIMEOUT" in stdout:
            result['error_feedback'] = "Simulation timed out"
            return result

        # Parse FORGE_RESULT line (same for both styles; VE pre-scales to 10000)
        m = re.search(r'\[FORGE_RESULT\]\s+TOTAL=(\d+)\s+PASSED=(\d+)\s+FAILED=(\d+)', stdout)
        if m:
            result['total'] = int(m.group(1))
            result['passed'] = int(m.group(2))
            if result['total'] > 0:
                result['score'] = result['passed'] / result['total']

        # -------- Path A (RTLLM): per-check FAIL lines -------------------
        fail_lines = re.findall(r'\[FORGE_CHECK.*?\].*?FAIL.*', stdout)
        if fail_lines:
            result['error_feedback'] = "\n".join(fail_lines[:20])
            return result

        # -------- Path B (VerilogEval): bucket-scored feedback -----------
        fb_parts: list = []

        # Parse buckets into a structured list (preserves parse order).
        bucket_list: list = []  # (name, passed, total, miss)
        mb = re.search(r'\[FORGE_BUCKET\]\s+(.+)', stdout)
        if mb:
            for tok in mb.group(1).split():
                if "=" not in tok or "/" not in tok:
                    continue
                name, pt = tok.split("=", 1)
                try:
                    p_str, t_str = pt.split("/")
                    p, t = int(p_str), int(t_str)
                except ValueError:
                    continue
                if p < t:
                    bucket_list.append((name, p, t, t - p))

        # Parse first-fail lines; also index by bucket for pairing in focused mode.
        ff_lines = re.findall(r'\[FORGE_FIRSTFAIL\].*', stdout)
        ff_by_bucket: dict = {}
        for ln in ff_lines:
            mff = re.search(r'bucket=(\w+)', ln)
            if mff:
                ff_by_bucket.setdefault(mff.group(1), ln.strip())

        if self.focused_feedback and bucket_list:
            # Focused: keep only the top-K highest-miss-rate buckets + matching samples.
            sorted_buckets = sorted(bucket_list, key=lambda b: b[3] / b[2], reverse=True)
            top = sorted_buckets[:max(1, self.focused_top_k)]
            fb_parts.append(f"Top-{len(top)} highest-miss bucket(s):")

            signals = self._extract_tb_signals(tb_path) if tb_path else None
            per_sample_mismatch: List[set] = []  # set of signal names per decoded sample

            for name, p, t, miss in top:
                miss_pct = (100.0 * miss / t) if t else 0.0
                fb_parts.append(
                    f"  {name}: {p}/{t}  (miss {miss}, {miss_pct:.1f}% miss rate)")
                if name not in ff_by_bucket:
                    continue
                ff_line = ff_by_bucket[name]
                # Try per-signal decoding when we have a signal map.
                decoded_ok = False
                if signals:
                    dut_m = re.search(r'\bdut=([0-9a-fA-F]+)', ff_line)
                    ref_m = re.search(r'\bref=([0-9a-fA-F]+)', ff_line)
                    cyc_m = re.search(r'\bcyc=(\d+)', ff_line)
                    in_m = re.search(r'\bin=([0-9a-fA-F]+)', ff_line)
                    if dut_m and ref_m:
                        dut_dec = self._decode_concat_hex(dut_m.group(1), signals)
                        ref_dec = self._decode_concat_hex(ref_m.group(1), signals)
                        if dut_dec and ref_dec:
                            cyc_s = cyc_m.group(1) if cyc_m else "?"
                            in_s = f"0x{in_m.group(1)}" if in_m else "(n/a)"
                            fb_parts.append(f"    cyc={cyc_s}  in={in_s}")
                            dut_fields = "  ".join(
                                f"{n}={dut_dec[n]}" for n, _ in signals)
                            ref_fields = "  ".join(
                                f"{n}={ref_dec[n]}" for n, _ in signals)
                            fb_parts.append(f"    DUT: {dut_fields}")
                            fb_parts.append(f"    REF: {ref_fields}")
                            diff = [n for n, _ in signals
                                    if dut_dec[n] != ref_dec[n]]
                            if diff:
                                fb_parts.append(
                                    f"    Mismatching signal(s): {', '.join(diff)}")
                                per_sample_mismatch.append(set(diff))
                            decoded_ok = True
                if not decoded_ok:
                    # Fallback: keep the original raw line so nothing is lost.
                    fb_parts.append(f"    [sample] {ff_line}")

            # Symptom hint: if every decoded first-fail shares the same
            # mismatching signal(s), surface that so the LLM can zoom in.
            if len(per_sample_mismatch) >= 1:
                common = set.intersection(*per_sample_mismatch)
                if common:
                    fb_parts.append(
                        f"Symptom hint: every top-K first-fail mismatches on "
                        f"signal(s) {sorted(common)} while other outputs match "
                        f"at those cycles. Focus the fix on the logic driving "
                        f"{sorted(common)}.")
        else:
            # Original behavior: dump all miss buckets + up to 10 first-fail lines.
            if bucket_list:
                fb_parts.append("Per-bucket coverage (only buckets with misses):")
                for name, p, t, miss in bucket_list:
                    fb_parts.append(f"  {name}: {p}/{t}  (miss {miss})")
            if ff_lines:
                fb_parts.append("First failing cycle per bucket "
                                "(in/dut/ref are concatenated-port hex):")
                fb_parts.extend("  " + ln.strip() for ln in ff_lines[:10])

        msw = re.search(r'\[FORGE_SCORE_WEIGHTED\]\s+([\d.]+)', stdout)
        if msw:
            fb_parts.append(f"Weighted coverage score: {msw.group(1)}")

        if fb_parts:
            result['error_feedback'] = "\n".join(fb_parts)

        return result

    def evaluate_original_tb(self, candidate_code: str, design, module_name: str) -> bool:
        """Run original testbench only. Returns True if passed. ``design`` is a DesignInfo."""
        tb_original = self.adapter.get_original_tb_path(design)
        if not tb_original or not os.path.exists(tb_original):
            return False

        cand_ext = self.adapter.CODE_FILE_EXT or 'v'
        work_dir = self.adapter.get_design_working_dir(design)
        extra_files = self.adapter.get_original_tb_extra_files(design)

        with tempfile.TemporaryDirectory() as tmp:
            cand_path = os.path.join(tmp, f"{module_name}.{cand_ext}")
            with open(cand_path, 'w') as f:
                f.write(candidate_code)
            result, _ = self._run_simulation(
                tb_original, cand_path, tmp, "original_final",
                extra_files=extra_files, cwd=work_dir)
            if result:
                return self.adapter.check_original_tb_result(result.stdout)
        return False
