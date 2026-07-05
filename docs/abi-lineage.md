# ABI lineage — why the registers differ

Why does Win64 pass arg1 in `rcx` while SysV uses `rdi`? Nothing in this file is
needed to assemble anything; it is the story that explains why the `abi:*`
correspondence in the intent DB must be *documented* rather than *derived*.
Companion to [DESIGN-nadir.md](DESIGN-nadir.md) §2.2 (the decision to keep two
hand-written realizations) and to the `abi:arg1`–`abi:arg4`, `abi:callee-saved`,
and `abi:syscall-args` bindings (the table itself).

The short answer: the AMD64 ISA fixes almost no calling convention — registers are
interchangeable to the hardware, and a convention is a pure software contract. Two
ecosystems standardized independently around 2001–2004, with different priorities
and different ancestries, and never had a reason to coordinate. The mapping is a
frozen historical accident. *Geschichte, nicht Geometrie.*

---

## The one hardware-forced fact: `syscall` clobbers `rcx` and `r11`

The single cell of the table the silicon actually dictates. The `syscall`
instruction hardwires saving the return `rip` into `rcx` and `rflags` into `r11` —
baked into the ISA by AMD. So any OS using it must route around `rcx` at the
kernel boundary, and both did, independently, with the same register:

- **Linux** makes it user-visible: syscall arg4 is `r10`, because the function
  convention's arg4 (`rcx`) is destroyed by the very instruction that enters the
  kernel.
- **Windows** hides it inside ntdll: every stub is `mov r10, rcx` /
  `mov eax, <number>` / `syscall`. Same substitution, made privately.

`r10` is the natural refuge in both cases: volatile under both conventions and an
argument register in neither function ABI.

Everything else in the table is convention, not physics.

---

## SysV AMD64 — tuned for throughput, by committee measurement

Drafted by the AMD64 psABI working group (AMD plus the GNU/Unix toolchain people)
alongside the port of gcc and glibc, roughly 2000–2003.

- **Six integer argument registers** (`rdi rsi rdx rcx r8 r9`): their spill
  studies said six was the sweet spot for minimizing stack traffic on real code.
- **`rdi`/`rsi` first is a small deliberate optimization:** the string
  instructions hardwire `rdi` = destination and `rsi` = source (`rep movs`,
  `rep stos`), so a `memcpy(dst, src, n)`-shaped function receives its arguments
  already in the registers the copy loop needs — zero shuffling for the hottest
  primitives in a Unix userland.
- **128-byte red zone:** leaf functions may use memory below `rsp` without
  adjusting it — another pure-throughput concession.
- **All xmm registers volatile:** vector-heavy leaf calls stay cheap; the caller
  pays for preservation only when it actually holds vector state.

---

## Win64 — tuned for uniformity and continuity

Microsoft's x64 convention is an evolution of 32-bit `__fastcall`, which passed
its first two arguments in `ecx`/`edx` — that is where `rcx`/`rdx`-first comes
from. The priorities were tooling and a single convention for all of Windows
(retiring the cdecl/stdcall/fastcall zoo), not peak call throughput.

- **Four register args + 32-byte shadow space:** every argument has a stack home
  slot at a fixed offset (`[rsp + 8n]` at entry), so after a trivial 4-register
  spill, varargs, `va_list`, a debugger walking a stopped stack, and the unwinder
  all see one complete, contiguous argument array. The shadow space every call
  pays for (see `abi:shadow-space` and
  [asm-debugging-guide.md](asm-debugging-guide.md)) is the purchase price of that
  uniformity.
- **`rsi`/`rdi` (and `xmm6`–`15`) callee-saved:** continuity with x86-32 Windows,
  where `esi`/`edi` were callee-saved — less porting pain for compiler backends
  and hand-written asm coming forward.
- **No red zone.**

---

## The collision map

The two conventions are not one register file with two sets of labels — the
*collision graph* differs, and the overlap in the middle is pure accident:

| register | win64 role | sysv/linux role | note |
|---|---|---|---|
| `rcx` | **arg1** | **arg4** | the worst cell: a body written to the wrong convention still assembles and runs |
| `rdx` | **arg2** | **arg3** | off-by-one overlap |
| `rdi` | callee-saved | **arg1** | |
| `rsi` | callee-saved | **arg2** | |
| `r8`  | **arg3** | arg5 (scratch for a ≤4-arg call) | |
| `r9`  | **arg4** | arg6 (scratch for a ≤4-arg call) | |
| `r10` | scratch | syscall arg4 | the hardware-forced row |
| `rax`, `r11` | return / scratch | return / scratch | shared — see `abi:return` |

Two intersections fall out of this table, and they are what nadir's shared code is
written against:

- **safe scratch while arguments are live, both ABIs:** `rax`, `r10`, `r11`
  (see `u64_to_dec`, whose shared loop body clobbers only both-volatile registers);
- **callee-saved on both ABIs:** `rbx`, `rbp`, `r12`–`r15`
  (see `m1_fold`, which stashes its arguments in `r12`–`r15` with zero `%ifdef` in
  the stash logic).

---

## What this means for nadir

Because the mapping is historical rather than derivable, no macro layer can turn
it into a syntax fact — a `%define arg1` skin makes the source *look* uniform
while the collision graph, the frame discipline, and the callee-saved sets still
diverge underneath, which is exactly where DESIGN §2.3 warns that arch-agnostic
layers rot. The convention is therefore *documented, not derived*: the `abi:*`
intent bindings carry the table, this file carries the story, and the two
hand-written realizations stay pinned to one contract by the behavioral tests
(DESIGN §6.2), not by shared source text. The descriptor table is documentation
you read, not codegen you trust.

The v0.3 resolution (DESIGN §2.2) is built directly on the two intersections
derived above: nadir-to-nadir calls use **one static internal convention** —
SysV's argument roles, the `rbx/rbp/r12–r15` callee-saved intersection, the
volatile union, uniform 16-byte alignment at calls — and the `cap_*` seam
realizations (per-target anyway) translate to kernel32 or `syscall`. One
convention in the house, real registers on the page, two interpreters at the
door. The collision graph still exists, but it now lives entirely inside the
seam bodies, where each is verified against a single target ABI.

## Further reading

- System V AMD64 psABI — the spec and its discussion archives
  (gitlab.com/x86-psABIs/x86-64-ABI).
- Microsoft, "x64 calling convention" (learn.microsoft.com).
- Raymond Chen, "The history of calling conventions, part 5: amd64" (2004) — the
  fastcall lineage and shadow-space rationale from inside Microsoft.
