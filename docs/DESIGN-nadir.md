# nadir — design doc

*An autological, arch-agnostic asm convention and capability set. Canonical asm; intent
and instrumentation as out-of-band projections.*

Status: draft v0.3 · asm-canonical · companion to `intent-map`

---

## 1. Thesis

Conventional toolchains sever intent from artifact. Comments are discarded by the
assembler and rot independently of the code; source of truth and explanation diverge
monotonically. Literate programming inverted this by making prose canonical and
*tangling* code out — but that puts a transform between what the human reasons about
and what the machine executes.

**nadir keeps the `.asm` canonical and projects everything else onto it** — intent for
reading, instrumentation for testing. The artifact the assembler sees is byte-identical
to the artifact the agent reasons about. `intent-map` supplies the read-time
projection: opaque keys bound to out-of-band rationale, reconstituted on demand. Nothing
is generated or emitted; the asm is hand-written and canonical.

Three claims the rest defends:

1. **asm is the bijective layer.** Every higher language inserts a lossy semantic layer
   — the compiler *decides* register allocation, instruction selection, calling
   convention, none of which exist in your source to annotate. At asm the
   intent↔instruction map is one-to-one: one label, one rationale, one address.
   intent-map's opaque-key/out-of-band-meaning invariant only holds at full fidelity
   where nothing sits between symbol and silicon.

2. **The substrate is freestanding and finite.** No libc, no CRT, no linker-provided
   runtime. nadir owns entry and provides only the capabilities its own corpus touches.
   A libc is unbounded because it serves everyone; nadir serves *its* programs, so its
   closure is knowable and the artifact can be *finished*.

3. **Portability is a thin waist, resolved by build flag.** One intent, two hand-written
   realizations, `%ifdef`/flag selects. One source tree, two dependency-free binaries,
   zero runtime indirection.

---

## 2. Architecture — three strata

Portability does **not** live at NASM-syntax level. Win64 and SysV AMD64 are the same
ISA with different ABIs; `mov rcx, …` assembles identically, but whether RCX is arg1
(Win64) or arg4 (SysV) is a semantic fact NASM knows nothing about. Code stratifies by
how target-dependent each region is.

### 2.1 Portable stratum — everything above the seam
Code that speaks only the nadir call convention (§2.2): pure computation *and* any
non-leaf logic whose calls stay inside the corpus. One `.asm`, both targets, no flag.
(v0.2 limited this stratum to leaf logic — no calls — because callers had to know the
target's arg registers. The internal convention removed that limit; see §2.2.)

### 2.2 ABI stratum — one internal convention, translated at the seam
Win64 and SysV differ in convention: arg registers, mandatory shadow space, the
callee-saved set (SysV also saves RSI/RDI; Win64 also saves xmm6–15). nadir does **not**
resolve roles dynamically, and it does not skin two conventions under `%define` roles —
a macro layer makes the source *look* uniform while the collision graph, frame
discipline, and callee-saved sets still diverge underneath (see
[abi-lineage.md](abi-lineage.md) for the collision map). Instead, nadir-to-nadir calls
use **one static convention, real registers, both targets**, and the capability
realizations — already two hand-written bodies (§2.3) — translate at the seam:

| rule | choice | why |
|---|---|---|
| args | `rdi, rsi, rdx, rcx` (arg5+ pull-based) | SysV roles: syscall marshalling near-zero; lineage in [abi-lineage.md](abi-lineage.md) |
| return | `rax` | shared by both targets already |
| callee-saved | `rbx, rbp, r12–r15` | the win64∩sysv intersection — both OS boundaries preserve it for free |
| volatile | everything else, incl. all xmm | the win64∪sysv union |
| alignment | `rsp ≡ 0 (mod 16)` at every call | needed transitively for kernel32; free on linux |
| shadow space / red zone | none | Win64 duties live inside `cap_*` win64 bodies, next to the calls that need them |

The bijection thesis (§1) survives because the convention is *singular and literal*:
`mov rdi, rax` in the source is `mov rdi, rax` in the silicon, and a reader verifies
any body against one register-role map, not two. The target ABIs don't vanish — they
concentrate where they are irreducible: inside the seam (kernel32's rules, `syscall`'s
rules) and at OS→nadir entries (`_start` normalizes loader alignment; future callbacks
like `WndProc` are OS-stratum shims, §5.2). *Eine Zunge im Haus, zwei Dolmetscher an
der Tür.*

intent-map's job here is *documentation of invariant knowledge*, not codegen: the
concept `arg1` is one immutable key whose detail records "→ rcx on win64, rdi on sysv"
— facts consumed *inside* the seam translations. The `abi:nadir-call` binding records
the internal convention itself.

| concept key | win64 detail | sysv detail | nadir |
|---|---|---|---|
| `arg1` | `rcx` | `rdi` | `rdi` |
| `arg2` | `rdx` | `rsi` | `rsi` |
| `shadow-space` | `sub rsp, 32` before any call | *(none)* | inside `cap_*` win64 only |
| `callee-saved+` | `rsi, rdi, xmm6–15` | *(base only)* | *(base only)* |

**Shared concept keys, per-target detail** — truer to intent-map's key↔concept model
than splitting `f_win64:arg1` / `f_sysv:arg1`. The key *is* the logical argument; the
register facts are properties of it. The agent sees the correspondence.

**Lineage of this decision:** v0.2 kept two hand-written realizations of every non-leaf
function; M1 built exactly that, and the reconcile loop surfaced the better absorption
point — the diff belongs in the `cap_*` bodies, which are per-target anyway. The
two-realization discipline now applies where it is irreducible (the seam), and the
behavioral tests (§6.2) still pin both realizations to one contract.

### 2.3 OS stratum — capability dispatch (a seam, not a layer)
Irreducibly divergent: `WriteFile`+`kernel32` vs `write` syscall, PE vs ELF. Intent
names the *capability*; the flag picks a hand-written implementation:

```
stdout-write → { win64: WriteFile-via-kernel32, linux: syscall-write }
```

A lookup keyed by target, not a transform of it. The seam absorbs **both** kinds of
divergence: mechanism (WriteFile vs `syscall`) and convention (each `cap_*` body
receives nadir args and owns its target's call duties — marshalling, shadow space,
`rcx→r10`). Keep that seam mechanically distinct from the portable code above it —
conflating the strata is where arch-agnostic layers rot.

---

## 3. Portability model — flag-swap, not emission

**There is no emit-time resolver.** Both ABI/OS realizations are checked in and
hand-written; a build flag (`-D WIN64` / target preamble) selects. This matches the
actual working loop (author, reconcile) and honors the no-runtime-indirection thesis —
the same instinct applied uniformly: *the switch replaces the compiler.*
*Der Schalter ersetzt den Compiler.*

**The thin waist.** nadir's capability set is the waist of an hourglass (cf. POSIX, LLVM
IR, IP). N intents × M targets becomes N+M, not N×M — but only while the waist stays
narrow. Every capability widens it by M implementations. *Die Kunst liegt in der
Beschränkung.* Waist-creep toward libc is the primary failure mode.

---

## 4. Capability set — the closed vocabulary

Pull-based, never speculative. Capabilities/roles must be a **typed, closed enum** — if
free-text, agents can't reason mechanically and coherence reverts to per-target human
eyeballing.

| capability | status | win64 | linux (x86-64) |
|---|---|---|---|
| `exit` | mandatory | `ExitProcess` | `syscall 60` |
| `write` | mandatory | `WriteFile`+`GetStdHandle` | `syscall 1` |
| `read` | on-demand | `ReadFile` | `syscall 0` |
| `alloc` | on-demand | `VirtualAlloc` | `mmap` (`syscall 9`) |
| `open`/`close` | on-demand | `CreateFileA`/`CloseHandle` | `syscall 2`/`3` |
| `socket`/`connect` | on-demand (GUI) | *(n/a — GUI via user32)* | `syscall 41`/`42` |
| `spawn` | on-demand (self-host) | `CreateProcessA` | `fork`+`execve` (`syscall 57`/`59`) |
| `open-window` | GUI leaf | `user32` sequence | X11 bytes over socket |

**2 mandatory, rest on-demand.** `exit`+`write` alone is a complete demonstrable program
on both OSes: a self-contained kernel that prints a result.

**Syscall-mechanism caveat.** The seam carries a *convention*, not just a name. Linux:
`syscall` insn, number in RAX, args RDI/RSI/RDX/**R10**/R8/R9 (the insn clobbers RCX
with the return address; R10 substitutes for arg4). Windows: never issue `syscall`
directly (numbers are private/unstable) — call *through* `kernel32`/`ntdll`, which drags
the Win64 call ABI (shadow space, RCX/RDX/R8/R9) back in the moment you do I/O.

---

## 5. GUI — the hard case

Win32 and Linux share **zero mechanism**:

- **Win32:** `call user32` — call-based, OS-owned message queue, `WndProc` callback.
  Library ABI. No Linux dual.
- **Linux/X11:** `socket`+`connect` to the display server, then `write` protocol bytes
  (handshake → `CreateWindow` → `MapWindow` → `PutImage`). Raw syscall + `write`
  generalized. No Windows dual.

Duals in *spirit* (produce a window), disjoint in *mechanism* — the OS-stratum
lookup-table in its purest form.

GUI splits into two tracks (full treatment in
[DESIGN-nadir-gui.md](DESIGN-nadir-gui.md)): the **primitive track** — this section:
`open-window`/`blit`/`close` as capabilities, the honest seam proof, M2 — and a
**host-tool track** (`asmgui`: Dear ImGui behind a narrow C ABI) for assembly
workbenches. The tool track lives *outside* the freestanding waist — it may link libc
and a renderer — and is tooling convention, not capability-table content. §5.1–5.2
below concern the primitive track only.

### 5.1 X11 over Wayland on the Linux side
Manjaro / Steam Deck default to Wayland. **Wayland-from-asm** needs `wl_registry`,
`wl_compositor`+`wl_shm`, `memfd_create`+`mmap`, xdg-shell handshake — ~5 protocol
objects and an shm dance before one pixel. **XWayland is the free escape hatch:** ships
on Manjaro-Wayland, and X11-protocol asm talks to it as if it were X11. Keeps
`open-window` pure `socket`/`connect`/`write` — no shm, no `mmap`. *Der Umweg über
XWayland ist der kürzere Weg.*

Caveat: Steam Deck **gaming mode** (pure Gamescope) has no XWayland → X11 client won't
connect. Fine for a dev toy (desktop mode has it); known edge.

### 5.2 Where the wrapper stops — the primitive tier
Wrap at the primitive tier (`open-window`/`blit`/`close`); keep the **event loop per-OS
and explicit**. Note the convention boundary this creates: anything the OS calls *into*
(Win32's `WndProc` is the first) arrives in the *target's* convention and must shim
into the nadir convention (§2.2) before touching portable code — the same duty `_start`
already performs for loader entry. Those shims are OS-stratum code by definition. X11 is retained-connection + protocol stream + you drive the loop by
reading the socket; Win32 is call-based + OS-owned queue + `WndProc` callback — the
*shapes* differ, not just the calls. A synthetic uniform event model costs more than two
honest loops at our corpus size. The waist stays narrow; the leak stays outside it.

**Domain ceiling, stated honestly:** compute portably, I/O by capability, GUI by
disjoint-impl-under-one-intent, event loop *not* portable. Arch-agnosticism is not
uniform across the stack; pretending it is would be the lie that rots the design.

---

## 6. Coherence — three-tier tests + injected instrumentation

The `.asm` is canonical; intent is a *falsifiable projection* onto it. Checkers are
**behavioral tests of program functionality**, at coarser granularity than intents —
intents document *why* per-label; tests assert *what* per-capability/function. The
altitude mismatch is deliberate: most invariants are read-time knowledge, not runtime
observable.

### 6.1 Interleaved reconcile (today, human-as-fixpoint)
Brush program vs intent → confirm coherent → program → update intent if needed → repeat.
Works solo because *you* are the reconciler; the bottleneck is that it doesn't scale to
agent-swarm authoring. The tiers below mechanize the parts that can be.

### 6.2 Three test tiers
- **Behavioral tests** at capability/function boundaries — the bulk. *Same test, both
  ABIs*: run against win64 and linux binaries, assert identical observable behavior.
  This is where the two hand-written realizations get pinned to one contract — the flag
  swaps implementation, the test proves they didn't diverge in meaning. *Ein Test, zwei Backends.* Slots onto the existing `test_zero_runner.py`/pytest harness; only delta is
  loading PE vs ELF.
- **Promoted-label tests** — critical invariants deliberately refactored to sit at a
  call boundary (own prologue/epilogue, ABI-clean) so they're callable in isolation.
  Testability pressure doubles as a decomposition heuristic: labels worth testing get
  promoted to real functions. Few, high-value.
- **Static lint** — the thin net for ABI-hygiene invariants that crash *late* and
  unreliably under behavioral tests (missing shadow space, clobbered callee-saved).
  Grep-level, only the two or three that are trivially matchable and expensively
  debuggable. Full static ABI verification is compiler-team effort we don't fund.

### 6.3 Injected instrumentation — canonical asm stays clean
Test predicates, guarded epilogues, and shims are **injected at test-build time**, never
committed. The canonical `.asm` carries zero test scaffolding.

- **Mechanism:** a source-to-source pass reads canonical asm, and for each tagged span
  splices in a predicate-guarded epilogue / shim, then hands the ephemeral result to
  NASM. Instrumented build is assembled, tested, discarded. *Die Quelle bleibt rein, das Testbild ist flüchtig.*
- **Symmetry with intent-map:** "which labels are testable and their test contract" is
  *also* out-of-band metadata. Injection is a projection of the binding store onto a
  throwaway build, mirroring how the annotated view is a projection for reading.
- **Predicate is a global, not a reserved register.** A `.bss` byte (widening to a
  test-context struct `{enabled, expected, scratch}` for promoted labels) guards the
  test-only `ret`. Speed is irrelevant in test; a global is *addressable*, so the
  harness sets it across the call boundary (a register can't be). No register starvation,
  no branch-aware stripper, no production residue — injection is additive-then-discarded,
  the direction that can't leave orphans.
- **Reentrancy caveat:** a global predicate is shared mutable state; fine for the serial
  pytest harness, but must go thread-local / per-context-pointer if tests ever drive two
  threads through instrumented labels.

### 6.4 The splice anchor — sentinel comments as style
Injection needs an unambiguous span, and multiple exits mean positional inference
("label to next label / first `ret`") fails on early returns. nadir adopts **paired
sentinel comments as a coding-style rule** — `IF … END IF` for asm.

**Canonical source carries only markers — bare `ret`s, no guard:**

```nasm
my_label:
    …
    ret                     ; @ret my_label   ← tagged exit, still a plain ret
.alt:
    …
    ret                     ; @ret my_label   ← second exit, same span
                            ; @end my_label   ← span boundary (also reads as a close)
```

**The injector, at test-build time, wraps each tagged exit with the guard** (which never
touches the committed file):

```nasm
    ; injected around each @ret:
    cmp byte [test_pred], 0
    jz  .real_ret_N
    <shim: record result / signal harness>
.real_ret_N:
    ret
```

So the source reads as clean control flow the agent parses once; the predicate check is
additive-then-discarded. The marker stays, the check comes and goes. *Der Marker bleibt,
die Prüfung kommt und geht.*

- **Paired sentinels beat inference:** `@end` bounds the span; each `@ret` marks an exit
  the injector wraps. Handles multiple endings by construction — exactly positional
  matching's blind spot. *Klammern schlagen Raten.*
- **Declarative, not heuristic:** the anchor is *stated in the text*, so it survives
  macro-generated labels and never depends on `^\s*<symbol>:` matching. *Der Anker steht im Text, nicht in der Heuristik.*
- **Pays for itself twice:** `@end` is documentation a reader wants anyway (the closing
  brace asm lacks) *and* the mechanical splice point. Resolves the purity tension —
  it's structure, not scaffolding.
- **Testability made visible:** a label with sentinels is *declared* a test target; a
  bare label opts out. Promotion becomes a syntactic act, keeping the pull-based
  discipline legible.
- **Cost:** manual sentinel placement, but only on *promoted* labels; the untested bulk
  stays bare. Placing the sentinel *is* the testability contract made in-source.

---

## 7. Roadmap

1. **M0 — prove the seam.** `exit`+`write` at capability level; two hand-written rows
   (`linux: syscall` / `win64: kernel32`), flag-selected. A compute kernel printing a
   result on Manjaro/Deck and Windows. Round-trips the reconcile loop → freestanding
   thesis holds.
2. **M1 — prove the ABI stratum.** One non-leaf kernel, 4+ args, callee-saved
   preservation, both realizations; shared concept keys documenting the correspondence.
   *(Built as specified in v0.2 — two hand-written kernel bodies — then revised: the
   experience surfaced the internal call convention (§2.2), the seam absorbed the
   ABI, and the kernel collapsed to one body. The behavioral tests pinned the
   refactor: same stdout, same exit codes, both targets.)*
3. **M2 — `open-window` round-trip.** Blank window, no events: Win32
   (`RegisterClass`+`CreateWindowEx`) vs X11 (`socket`+handshake+`CreateWindow`+
   `MapWindow` via XWayland) under one intent. Locates where portability should stop.
   *(The host-tool GUI track G0–G5 in [DESIGN-nadir-gui.md](DESIGN-nadir-gui.md) runs
   parallel to this roadmap and gates nothing here.)*
4. **M3a — behavioral tests.** Same test, both ABIs, on the existing
   `test_zero_runner.py`/pytest harness; only delta is loading PE vs ELF. Gates on
   nothing heavier — do this before building any injector.
5. **M3b — injection + instrumentation.** Sentinel convention on promoted labels; the
   injector + global-predicate guard; thin lint for shadow-space / callee-saved. The
   real lift, deferred until M3a proves the harness. **The injector is itself a nadir
   program** — search-replace over asm text (`read` file → scan for `@ret`/`@end` →
   `write` spliced output), needing only `read`/`write`/`open`/`exit`, all already on the
   table. The tool that instruments the corpus is authored in the corpus.
6. **M3c — self-host.** The injector instruments its *own* `@ret`/`@end` spans and passes
   its own behavioral test. Closes the loop: a freestanding substrate whose tooling is
   written in itself — the finished-artifact property made concrete. *Der Ouroboros in
   Assembler.*
7. **M4+ — widen the table, pull-based.** `read`/`alloc`/`open` as real programs demand.
   Never speculatively.

---

## 8. Tooling & bootstrap

**No CLI through M2 — scons + build flag is the spine.** `nasm -D WIN64 …` + linker,
wrapped in SConstruct; target selection is a flag, not a program. nadir is a
*convention + capability table + intent-map DB*, not a binary. Don't build tooling
surface before a transform forces it — that's waist-creep in tooling instead of
capabilities. *Weniger Oberfläche, weniger Pflege.*

**One verb at M3b — `nadir test`.** The sole place a flag can't reach is the injection
pass: read canonical asm, splice guards at `@ret`/`@end`, assemble the ephemeral build,
run, discard. That's a real transform, so it earns a verb — and only it does. Build,
link, target-select stay scons + flag.

**The verb's implementation is a nadir program.** `nadir test`'s injector is
search-replace over asm text — the honest minimum transform, no AST, no parser, just
literal-sentinel matching and buffered `write`. It needs only `read`/`write`/`open`/
`exit`, already on the table, so it *is* M0's proof program with a purpose: writing it
exercises exactly the primitives the roadmap builds anyway. Self-hosting (M3c) is then
not aspirational — the first real program already closes the loop.

**`nadir build` — second verb, thin orchestration.** Shells out to `nasm` + linker,
owns the flag matrix (`-D WIN64` vs SysV, `/subsystem:windows` vs ELF entry), selects
target rows. Adds one capability — `spawn` (`CreateProcessA` / `fork`+`execve`) — which
nadir reaches inevitably once it drives anything, so it's a "when," not a cost. With
`build` + `test` + the corpus beneath, all three are authored in the corpus: nadir
builds itself, tests itself, builds others. *Der Compiler, der sich selbst kocht.*

**Bootstrap order — external toolchain first, self-host one rung at a time.** scons +
hand-run `nasm` boots the earliest programs. `nadir test` lands first (file I/O only,
gates on nothing heavier), proving the inject loop. `nadir build` follows when `spawn` is
ready. Each verb self-hosts a single rung while the external toolchain still carries the
rest — never the whole trinity at once. *Man kocht nicht die ganze Suppe auf einmal.*

**Boundary: `nadir build` must not become make.** Its charm is that the corpus is small
enough that "build" is a flag table plus two spawns. Dependency graphs, incremental
rebuilds, parallelism — that's scons's job, and scons already exists. Keep `nadir build`
the self-hosting *demonstrator*; let scons drive anything with fan-out. *Die Grenze ist
der Reiz.*

---

## 9. Open questions & risks

- **Waist creep (primary).** Keep capabilities single-digit. Litmus: can nadir ever say
  "done" for its corpus? Trending toward "never" means the waist is leaking toward libc.
- **Closed-vocabulary discipline.** Roles/capabilities stay a typed enum the tooling
  exhaustively handles; free-text at the ABI/OS strata kills mechanical coherence.
- **Injection anchor hardening.** Sentinel comments (`@end`/`@ret`) resolve the textual-
  match fragility for now. Structural anchoring only if the corpus ever outgrows the
  convention — pull-based. *Erst wenn's kracht, wird gehärtet.*
- **Shim ABI discipline.** The injected shim must be *more* ABI-disciplined than the code
  under test — a shim that clobbers a callee-saved reg masks or invents bugs. One
  reusable, audited shim macro, not hand-rolled per label.
- **nadir-call convention gaps.** arg5+, xmm/vector args, and varargs are undefined
  until a capability needs them — extend pull-based, and record each extension in the
  `abi:nadir-call` binding. Interop with externally-called code (OS callbacks) always
  goes through an OS-stratum shim, never by bending the internal convention.
- **GUI event-model leak.** Per-OS loops are right at toy scale; revisit only if a real
  program needs uniform event handling across both targets.
- **intent-map recall gap.** FTS5 keyword OR-matching misses semantic recall
  (`"controls coolant flow"` vs query `thermal management`). A `sqlite-vec` sidecar
  closes it additively without touching the wire grammar — *after* the checker, not
  before.
- **Steam Deck gaming-mode X gap.** No XWayland in pure Gamescope; document as a known
  edge, not a bug.

---

## Appendix — lineage

nadir is not a new POSIX; it is the **thin-waist pattern re-derived from scratch at
CPU-asm granularity** — a layer compilers already ate and nobody re-grounds by hand. The
public analog is **LLVM**: one IR lowered to many backends (x86, ARM, RISC-V) through
target-specific descriptors (`TableGen`) that resolve abstract operations to concrete
instructions. nadir is that shape stripped to its skeleton — intent-map as the annotation
layer, the ISA as the target language, the build flag as the selector, every bone
visible. Where LLVM hides the lowering behind a compiler, nadir keeps it hand-authored
and legible; the descriptor table is *documentation you read*, not codegen you trust.
*Von Grund auf neu*, and the rediscovery is the point.
