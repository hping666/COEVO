import subprocess
import os
import signal


def run_with_timeout(cmd: str, timeout: int, cwd: str = None) -> subprocess.CompletedProcess:
    """Run shell command with timeout. Kills entire process group on timeout
    to prevent orphaned child processes (e.g., vvp surviving after shell is killed)."""
    proc = subprocess.Popen(
        cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, cwd=cwd, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return subprocess.CompletedProcess(cmd, returncode=proc.returncode,
                                           stdout=stdout, stderr=stderr)
    except subprocess.TimeoutExpired:
        # Kill the entire process group (shell + all children like vvp)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            proc.kill()
        stdout, stderr = proc.communicate()
        return subprocess.CompletedProcess(cmd, returncode=-1,
                                           stdout=stdout or "",
                                           stderr=(stderr or "") + "\nTIMEOUT")
