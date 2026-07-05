# CLAUDE.md — working in nadir

Guidance for agents (and humans) working in this repo. Read this first, then
[docs/DESIGN-nadir.md](docs/DESIGN-nadir.md) for the full rationale.

## What nadir is

An autological, arch-agnostic asm convention. The `.asm` is **canonical**; intent
and instrumentation are out-of-band projections onto it (DESIGN §1). One logical
concept, two hand-written realizations (win64 `kernel32` / linux `syscall`),
selected by a build flag — no compiler, no CRT, no libc. nadir owns `_start`.

Current milestone: **M1 — "prove the ABI stratum"** (DESIGN §7.2), complete:
`m1_fold`, a non-leaf 4-arg kernel (arg3/arg4 divergence + callee-saved
discipline, both realizations), behaviorally pinned by an asymmetric fold and a
register canary; the `abi:*` concept keys document the correspondence. Next up:
**M2 — `open-window` round-trip** (DESIGN §7.3).

## The intent-map workflow (how documentation works here)

Intent lives in an **intent-map database** — a symbol→meaning store, one binding
per `<file>:<symbol>` label, with a two-tier body:

- **summary** — one line, the *glance* tier. What the thing is.
- **detail** — free-form, the *commit* tier. The full rationale, per-target facts.

This two-tier split is deliberate: **summary for quick scan, detail for deep
read.** Use the cheap tier until you need the expensive one.

The tool is a pinned submodule at [opt/intent-map](opt/intent-map) (see
"Toolchain" below). The canonical DB is tracked in `docs/` as a documentation
artifact: [docs/nadir.intent.db](docs/nadir.intent.db).

### Agents: use `recent` and `get`, not `view`

When walking labels, read the DB directly:

```sh
IMAP=opt/intent-map/intent-map.exe          # ".exe" on Windows; no suffix on linux
export INTENT_MAP_DB=docs/nadir.intent.db

$IMAP recent                                 # all bindings, newest first (glance tier)
$IMAP recent --limit 5                        # just the latest few
$IMAP get cap_write.asm:cap_write             # ONE label, full detail tier
$IMAP search shadow syscall                   # FTS recall over summary+detail (OR'd)
$IMAP index                                   # keyword -> count vocabulary
```

The summary/detail pair is *made for this*: scan `recent` (summaries) to orient,
then `get <label>` only for the entries you actually need to understand deeply.
Don't render whole files — pull the specific bindings.

### Humans: use `view`

`view` injects the intent as `;`-comments above each matching label in the real
source — the human-facing overlay. It is **not** for agents (it emits annotated
source, not the wire grammar).

```sh
cd src                                        # run from the file's directory
$IMAP view cap_write.asm --stdout             # intent overlaid onto the asm
```

**Label/path gotcha:** `view FILE` uses `FILE` as *both* the file to open *and*
the exact label-prefix to match. Our labels use bare filenames
(`cap_write.asm:cap_write`), so `view` must be run from `src/` with a bare
filename. Passing `src/cap_write.asm` opens the file but the prefix won't match
("no active entries").

### Editing intent

```sh
$IMAP allocate --label "<file>:<symbol>" --summary "..." --detail "..."   # new binding
$IMAP annotate <label> --summary "..." --detail "..."                     # edit prose
$IMAP retire <label>                                                       # soft-delete (tombstone)
```

Keys are allocated once and never renumbered, reused, or hard-deleted. After any
change, **re-run the backup** (below) and commit both the `.db` and its `.md`.

### Backup — guard against data loss

The DB is binary and git can't diff it. After changing intent, dump it to a
plaintext, git-diffable, re-loadable Markdown mirror:

```sh
python scripts/backup_intent_maps.py          # writes docs/<name>.intent.db.md
python scripts/backup_intent_maps.py --check   # CI/pre-commit: fail if mirror is stale
```

The script reads the SQLite `bindings` table **directly** (no dependency on the
tool binary), so it still works if the tool itself is what broke. Commit the
`.md` alongside the `.db`; the `.md` is the human-readable, tool-independent
safety net and doubles as a re-load source.

The DB is canonical — there is no prose source file behind it (the old
`intent/nadir.intent.md` was retired once the DB became the store). The `.md`
mirror is a **safety net, generated on demand**, kept while we build confidence
in the tool through use; once the tool has proven durable, the mirrors can be
dropped or generated only at release. Regenerate before committing a DB change so
the mirror never lags the binary.

### Why the tool is pinned

A generated intent-map DB is only readable by a compatible tool version (schema +
wire grammar). Pinning intent-map as a submodule SHA keeps the tool↔data pairing
reproducible from a nadir checkout. `opt/` is versioned tooling; `var/` is
git-ignored scratch. Don't bump the submodule without re-checking the DB still
loads.

## Build & test

The build spine is **scons + a target flag** (DESIGN §8) — no CLI wrapper through
M2. `_start` is nadir's; both linkers run `/nodefaultlib` (no CRT).

```sh
git submodule update --init                   # fetch opt/intent-map at its pinned SHA
python -m SCons                               # host target (win64 on Windows, linux else)
python -m SCons target=linux                  # cross-author: assembles ELF; links where ld exists
python -m SCons -c                            # clean
python -m pytest tests -v                     # behavioral test: build, run, assert stdout + exit
```

Use `python -m SCons` (not bare `scons`) — the pip package installs the module,
not always a PATH entry. Both target legs run in CI
([ci-linux](.github/workflows/ci-linux.yml), [ci-windows](.github/workflows/ci-windows.yml)),
one workflow per target so each carries its own badge.

## Toolchain (this machine)

- **nasm** — assembler, both targets (`-f win64 -DWIN64` / `-f elf64`).
- **MSVC link.exe** — win64 linker, located via `vswhere` in the SConstruct.
  VS 2022 Build Tools, toolset under `VC\Tools\MSVC\<newest>\bin\Hostx64\x64`.
- **ld** — linux linker (only on linux hosts; Windows assembles ELF for syntax
  only, doesn't link/run it — that leg is closed by the ubuntu CI runner).
- **opt/intent-map** — the intent tool; build with its `build.ps1` (Windows,
  MSVC + vendored SQLite amalgamation) or `make` (linux, system libsqlite3).

## Calling conventions — read before touching asm

nadir-to-nadir calls use **one internal convention on both targets** (DESIGN
§2.2, codified in [src/nadir.inc](src/nadir.inc)): args `rdi/rsi/rdx/rcx`,
return `rax`, callee-saved `rbx/rbp/r12–r15`, `rsp ≡ 0 (mod 16)` at every call,
no shadow space. The target ABIs appear only inside `cap_*` realizations (which
translate at the seam) and at OS entries (`_start` normalizes with
`and rsp, -16`).

The Win64 convention — in force inside `cap_*` win64 bodies — has two invariants
that a passing run does **not** verify (misalignment faults only when the callee
happens to touch the stack with an alignment-sensitive instruction): 16-byte
stack alignment *at the call*, and 32 bytes of caller-allocated shadow space
before *any* call into Win64 code. The full lessons, with the `rsp mod 16`
arithmetic and the three real bugs from M0, are in
[docs/asm-debugging-guide.md](docs/asm-debugging-guide.md); the register history
is in [docs/abi-lineage.md](docs/abi-lineage.md). Walk the arithmetic; don't
trust the exit code.

## Conventions

- **Commits:** imperative subject; body explains *why*, not just what. Co-author
  trailer for agent work.
- **PR review:** verify bot/reviewer findings against the actual code before
  acting — reason through the claim, fix if real, reply with what changed (or why
  not), resolve the thread. A confident review can still be wrong.
- **Don't reformat untouched code**; keep diffs reviewable.
- **`var/` is scratch** (git-ignored). Generated artifacts that should be tracked
  (like the intent DB) go in `docs/`.

## Layout

```
src/               canonical asm — the artifact (nadir.inc + capabilities + kernel)
docs/              design doc, guides, and the tracked intent DB + its .md mirror
tests/             behavioral tests (build, run, assert observable behavior)
scripts/           tooling (intent-map backup/dump)
opt/intent-map     pinned submodule: the intent tool itself
var/               git-ignored scratch / generated working copies
SConstruct         build spine — target flag selects the realization
```
