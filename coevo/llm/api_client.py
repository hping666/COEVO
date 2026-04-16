import os
import time
import threading
from openai import OpenAI


class LLMClient:
    def __init__(self, models_config: dict, llm_config: dict = None):
        self.models = models_config
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.total_cost = 0.0
        self.total_calls = 0
        self.per_model_usage = {}
        self._clients = {}                # Cache clients by api_key
        self._no_sampling_models = set()  # Models that don't support temperature
        self._lock = threading.Lock()     # Protects usage counters for parallel mode

        # Read default params from llm config
        cfg = llm_config or {}
        self.default_max_retries = cfg.get('max_retries', 3)
        self.default_retry_delay = cfg.get('retry_delay', 5)
        self.default_top_p = cfg.get('top_p', 0.95)

    def _get_client(self, model_name: str) -> OpenAI:
        """Cache OpenAI clients by api_key to reuse HTTP connections."""
        model_cfg = self.models[model_name]
        api_key = os.environ.get("OPENAI_API_KEY") or model_cfg.get('api_key_env', '')
        if api_key not in self._clients:
            self._clients[api_key] = OpenAI(api_key=api_key)
        return self._clients[api_key]

    @staticmethod
    def _is_codex_model(model_id: str) -> bool:
        return "codex" in model_id.lower()

    @staticmethod
    def _needs_max_completion_tokens(model_id: str) -> bool:
        """GPT-5 series requires max_completion_tokens instead of max_tokens."""
        return model_id.startswith("gpt-5") or model_id.startswith("o")

    def call(self, model_name: str, messages: list, temperature: float = 0.8,
             max_tokens: int = 8192, max_retries: int = None,
             retry_delay: int = None) -> dict:
        """Call the specified model. Auto-retry with exponential backoff."""
        max_retries = max_retries if max_retries is not None else self.default_max_retries
        retry_delay = retry_delay if retry_delay is not None else self.default_retry_delay

        model_cfg = self.models[model_name]
        model_id = model_cfg['model_id']
        client = self._get_client(model_name)
        max_tok = min(max_tokens, model_cfg.get('max_tokens', 16384))
        use_sampling = model_name not in self._no_sampling_models

        for attempt in range(max_retries):
            try:
                result = self._call_once(client, model_id, model_cfg, messages,
                                         temperature, max_tok, use_sampling)
                # Track usage (thread-safe)
                with self._lock:
                    self.total_input_tokens += result['usage']['input']
                    self.total_output_tokens += result['usage']['output']
                    self.total_cost += result['cost']
                    self.total_calls += 1

                    if model_name not in self.per_model_usage:
                        self.per_model_usage[model_name] = {
                            'input': 0, 'output': 0, 'cost': 0.0}
                    self.per_model_usage[model_name]['input'] += result['usage']['input']
                    self.per_model_usage[model_name]['output'] += result['usage']['output']
                    self.per_model_usage[model_name]['cost'] += result['cost']

                return result
            except Exception as e:
                err_msg = str(e).lower()
                # Sampling fallback: some models don't support temperature/top_p
                if use_sampling and ('temperature' in err_msg or 'top_p' in err_msg):
                    self._no_sampling_models.add(model_name)
                    use_sampling = False
                    continue  # Retry immediately, don't count as attempt
                if attempt < max_retries - 1:
                    time.sleep(retry_delay * (2 ** attempt))
                else:
                    raise

    def _call_once(self, client: OpenAI, model_id: str, model_cfg: dict,
                   messages: list, temperature: float, max_tok: int,
                   use_sampling: bool) -> dict:
        """Single API call. Handles Codex / GPT-5 / standard models."""
        sampling = dict(temperature=temperature, top_p=self.default_top_p) if use_sampling else {}

        if self._is_codex_model(model_id):
            # Codex models use responses API with instructions/input
            instructions = next(
                (m['content'] for m in messages if m['role'] == 'system'), "")
            user_input = next(
                (m['content'] for m in messages if m['role'] == 'user'), "")
            resp = client.responses.create(
                model=model_id, instructions=instructions,
                input=user_input, max_output_tokens=max_tok, **sampling)
            content = resp.output_text
            usage = {'input': resp.usage.input_tokens,
                     'output': resp.usage.output_tokens}
        else:
            # Standard chat completions API
            kwargs = dict(model=model_id, messages=messages, **sampling)
            if self._needs_max_completion_tokens(model_id):
                kwargs['max_completion_tokens'] = max_tok
            else:
                kwargs['max_tokens'] = max_tok
            resp = client.chat.completions.create(**kwargs)
            content = resp.choices[0].message.content
            usage = {'input': resp.usage.prompt_tokens,
                     'output': resp.usage.completion_tokens}

        cost = self._compute_cost(model_cfg, usage)
        return {'content': content, 'usage': usage, 'cost': cost}

    def _compute_cost(self, model_cfg: dict, usage: dict) -> float:
        in_cost = model_cfg.get('cost_per_1k_input', 0) * usage['input'] / 1000
        out_cost = model_cfg.get('cost_per_1k_output', 0) * usage['output'] / 1000
        return in_cost + out_cost

    def get_usage_summary(self) -> dict:
        return {
            'total_input_tokens': self.total_input_tokens,
            'total_output_tokens': self.total_output_tokens,
            'total_cost': self.total_cost,
            'total_calls': self.total_calls,
            'per_model': self.per_model_usage,
        }
