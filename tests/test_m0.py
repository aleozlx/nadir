"""M0 behavioral test — "prove the seam" (DESIGN §7.1, §6.2).

Black-box, in the spirit of intent-map's harness: build the freestanding binary via
the scons spine, run it, assert observable behavior (stdout + exit code). At M0 only
the win64 leg builds/runs on this machine; the linux leg slots in unchanged on
Manjaro/Deck once `ld` is present (DESIGN §6.2 "same test, both ABIs" — this file is
the seed of that harness, running one leg today).

Run:  python -m pytest tests/test_m0.py -v
"""
import os
import platform
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
BUILD = REPO / "build"

# The M0 result contract: exact bytes the seam must carry.
EXPECTED_STDOUT = b"nadir M0: seam proven\n"
EXPECTED_EXIT = 0


def _scons(*args):
    """Invoke scons via the Python module (no `scons` shim needed on PATH)."""
    cmd = [sys.executable, "-m", "SCons", "-C", str(REPO), *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def _target_for_host():
    return "win64" if platform.system() == "Windows" else "linux"


def _program_path(target):
    return BUILD / ("m0_banner.exe" if target == "win64" else "m0_banner")


@pytest.fixture(scope="module")
def built_program():
    """Build the M0 program for the host target; return its path (or skip)."""
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


def test_banner_stdout(built_program):
    """The kernel prints exactly the M0 result string to stdout."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.stdout == EXPECTED_STDOUT, (
        "stdout mismatch: %r != %r" % (res.stdout, EXPECTED_STDOUT)
    )


def test_exit_code(built_program):
    """The kernel exits cleanly with code 0 (the `exit` capability)."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.returncode == EXPECTED_EXIT, (
        "exit code %d != %d" % (res.returncode, EXPECTED_EXIT)
    )


def test_no_stderr(built_program):
    """A freestanding kernel writes nothing to stderr."""
    res = subprocess.run([str(built_program)], capture_output=True)
    assert res.stderr == b"", "unexpected stderr: %r" % res.stderr
