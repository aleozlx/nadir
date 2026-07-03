"""M1 behavioral test — "prove the ABI stratum" (DESIGN §7.2, §6.2).

Black-box, same shape as test_m0: build via the scons spine, run, assert observable
behavior. What the observables pin here:

  stdout   — fold(6,7,8,9) folds the args positionally (a*1000+b*100+c*10+d), so the
             printed digits "6789" spell the argument order; any swapped arg register
             in either realization prints different digits. The digits also prove the
             a..d values survived a cap_write call in callee-saved registers.
  exit code — _start exits with (rax − 6789), or 99 if its r12 canary died inside
             m1_fold. 0 therefore asserts the return-value register AND m1_fold's
             callee-saved push/pop discipline. Same expectation both ABIs (the diff
             is 0, so linux's 8-bit truncation is moot).

Run:  python -m pytest tests/test_m1.py -v
"""
import platform
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / "build"

# The M1 result contract: exact bytes + the verdict exit code.
EXPECTED_STDOUT = b"nadir M1: fold(a,b,c,d) = 6789\n"
EXPECTED_EXIT = 0


def _scons(*args):
    """Invoke scons via the Python module (no `scons` shim needed on PATH)."""
    cmd = [sys.executable, "-m", "SCons", "-C", str(REPO), *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def _target_for_host():
    return "win64" if platform.system() == "Windows" else "linux"


def _program_path(target):
    return BUILD / ("m1_abi.exe" if target == "win64" else "m1_abi")


@pytest.fixture(scope="module")
def built_program():
    """Build the M1 program for the host target; return its path (or skip)."""
    target = _target_for_host()
    res = _scons("target=%s" % target)
    if res.returncode != 0:
        pytest.fail(
            "scons build failed for target=%s\n--- stdout ---\n%s\n--- stderr ---\n%s"
            % (target, res.stdout, res.stderr)
        )
    prog = _program_path(target)
    if not prog.exists():
        # linux-without-ld path assembles objects only; nothing to run here.
        pytest.skip(
            "no runnable binary for target=%s on this host (assembled objects only)"
            % target
        )
    return prog


def test_fold_stdout(built_program):
    """The kernel prints the fold line; '6789' spells the argument order."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.stdout == EXPECTED_STDOUT, (
        "stdout mismatch: %r != %r" % (res.stdout, EXPECTED_STDOUT)
    )


def test_abi_verdict_exit_code(built_program):
    """Exit 0 == return value correct and callee-saved canary intact (99 = canary died)."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.returncode == EXPECTED_EXIT, (
        "exit code %d != %d (99 means m1_fold clobbered a callee-saved register; "
        "any other nonzero is rax − 6789)" % (res.returncode, EXPECTED_EXIT)
    )


def test_no_stderr(built_program):
    """A freestanding kernel writes nothing to stderr."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.stderr == b"", "unexpected stderr: %r" % res.stderr
