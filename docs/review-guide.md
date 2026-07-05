# nadir review guide

What a reviewer — human or the Claude Code review action — should weigh when
reading a change to nadir. This is the *focus list*, not a substitute for
[CLAUDE.md](../CLAUDE.md) and [docs/DESIGN-nadir.md](DESIGN-nadir.md); read
those for the rationale. The standing rule from CLAUDE.md applies to reviewers
too: **a confident review can still be wrong — verify a finding against the
actual code before raising it.**

nadir is freestanding (no compiler, no CRT, no libc), arch-agnostic, and carries
two hand-written realizations of every concept (win64 `kernel32` / linux
`syscall`). The things most likely to break here are not the things a passing
test catches.

## 1. ABI correctness — walk the arithmetic, don't trust the exit code

The internal nadir-to-nadir convention (codified in
[src/nadir.inc](../src/nadir.inc)): args `rdi/rsi/rdx/rcx`, return `rax`,
callee-saved `rbx/rbp/r12–r15`, `rsp ≡ 0 (mod 16)` at **every** call, no shadow
space.

Inside the `cap_*` win64 bodies the Win64 ABI is in force, with two invariants a
green run does **not** verify — misalignment only faults when the callee happens
to touch the stack with an alignment-sensitive instruction:

- **16-byte stack alignment _at the call_.**
- **32 bytes of caller-allocated shadow space before _any_ call into Win64 code.**

For any changed call site or prologue/epilogue, do the `rsp mod 16` arithmetic by
hand — see [docs/asm-debugging-guide.md](asm-debugging-guide.md) for the method
and the three real M0 bugs it would have caught. Check that every callee-saved
register a routine clobbers is saved and restored, and that `_start` still
normalizes with `and rsp, -16`.

## 2. Realization divergence

A concept lives twice. When a change touches one realization, confirm the other
still expresses the *same logical behavior* — or, if they legitimately diverge
(win64 vs linux OS seam), that the divergence is intentional and confined to the
`cap_*` layer / OS entry, not leaking into the arch-agnostic core. Both target
legs run the *same* behavioral test ([DESIGN §6.2](DESIGN-nadir.md)); a change
that only makes one leg pass is incomplete.

## 3. Intent-map hygiene

Intent lives in the intent-map DB, not in comments (see CLAUDE.md). If a symbol's
behavior, contract, or ABI facts changed, its `docs/nadir.intent.db` binding
should keep pace:

- summary (glance tier) still accurate; detail (commit tier) reflects new
  per-target facts.
- New symbol → a new `allocate`d binding; retired symbol → `retire`, never
  hard-delete or renumber.

Do **not** gate review on the `.md` mirror: it's a safety net regenerated on
demand and drifts from the `.db` by design, so its sync state is not a review
signal for now. Making the intent surface reviewable is a separate pass, tracked
elsewhere.

## 4. Freestanding & build discipline

- No CRT / libc / compiler assumptions; both linkers stay `/nodefaultlib`, and
  `_start` remains nadir's.
- No new toolchain dependency slips in without a matching note in CLAUDE.md's
  Toolchain section and both CI legs
  ([ci-linux](../.github/workflows/ci-linux.yml),
  [ci-windows](../.github/workflows/ci-windows.yml)).
- Diffs stay reviewable: no reformatting of untouched code; `var/` scratch never
  committed.

## 5. Correctness, security, clarity

The ordinary pass — real bugs over style nits, security implications of any new
OS-facing surface, and whether the change reads like the surrounding code. Prefer
a few high-confidence findings over a long list of maybes.
