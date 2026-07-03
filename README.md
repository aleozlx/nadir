# nadir

[![linux](https://github.com/aleozlx/nadir/actions/workflows/ci-linux.yml/badge.svg?branch=main)](https://github.com/aleozlx/nadir/actions/workflows/ci-linux.yml)
[![windows](https://github.com/aleozlx/nadir/actions/workflows/ci-windows.yml/badge.svg?branch=main)](https://github.com/aleozlx/nadir/actions/workflows/ci-windows.yml)

An autological, arch-agnostic asm convention and capability set.

See [docs/DESIGN-nadir.md](docs/DESIGN-nadir.md) for the full design.

## M0 — "prove the seam"

The first milestone (DESIGN §7.1): the two mandatory capabilities `exit` + `write`,
each with **two hand-written realizations** (linux `syscall` / win64 `kernel32`)
selected by a build flag, assembled **freestanding** (no CRT/libc) into a self-contained
binary that prints a banner and exits 0.

```
src/
  nadir.inc        seam/ABI knowledge; %ifdef WIN64 vs linux
  cap_write.asm    capability `write`  (WriteFile+GetStdHandle | syscall 1)
  cap_exit.asm     capability `exit`   (ExitProcess           | syscall 60)
  m0_banner.asm    _start: cap_write(banner) -> cap_exit(0)
docs/              design doc, guides, and the tracked intent-map DB (+ .md mirror)
tests/test_m0.py   behavioral test: build, run, assert stdout + exit code
scripts/           tooling (intent-map DB backup/dump)
SConstruct         build spine — flag selects target (DESIGN §8)
opt/intent-map     pinned submodule: the intent-map tool itself (built in place)
```

`var/` stays git-ignored, reserved for generated/scratch artifacts.

### Build & run

Requires: `nasm`, `scons` (`pip install scons`), and a linker for your target
(win64: MSVC `link.exe` from VS Build Tools; linux: `ld`).

```sh
git submodule update --init    # fetch opt/intent-map at its pinned commit
scons                 # host target (win64 on Windows, linux elsewhere)
scons target=linux    # cross-author: assembles ELF; links where `ld` exists
scons -c              # clean

./build/m0_banner.exe            # win64  -> "nadir M0: seam proven", exit 0
./build/m0_banner                # linux

python -m pytest tests/test_m0.py -v   # behavioral test (seeds the M3a harness)
```

If `scons` is not on PATH, use `python -m SCons` (the pip package installs the module).

`opt/intent-map` is pinned rather than freely updated because a generated intent-map
database is only readable by a compatible tool version (schema + wire grammar) — pinning
the tool as a submodule SHA keeps that pairing reproducible from a nadir checkout.

### Verified (win64)

The linked exe imports **only** `KERNEL32.dll` (`WriteFile`, `ExitProcess`,
`GetStdHandle`) — no CRT — with a custom `_start` entry, ~2.5 KB. The linux leg
assembles to ELF64 and links with `ld` on Manjaro/Steam Deck.

Win64 stack-discipline lessons (alignment + shadow space) from building this kernel are
in [docs/asm-debugging-guide.md](docs/asm-debugging-guide.md).
