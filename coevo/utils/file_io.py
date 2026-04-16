import os
import yaml


def load_yaml(path: str) -> dict:
    with open(expand_path(path)) as f:
        return yaml.safe_load(f)


def save_yaml(data: dict, path: str):
    p = expand_path(path)
    ensure_dir(os.path.dirname(p))
    with open(p, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def load_text(path: str) -> str:
    with open(expand_path(path)) as f:
        return f.read()


def write_temp_verilog(code: str, module_name: str, tmp_dir: str) -> str:
    path = os.path.join(tmp_dir, f"{module_name}.v")
    with open(path, 'w') as f:
        f.write(code)
    return path


def ensure_dir(path: str):
    os.makedirs(expand_path(path), exist_ok=True)


def expand_path(path: str) -> str:
    return os.path.expanduser(path)
