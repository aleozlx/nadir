# asm debugging guide — Win64

Field notes on the Win64 (x64) calling convention, written from the bugs actually hit
building nadir's M0 kernel (`src/cap_write.asm`, `src/cap_exit.asm`, `src/m0_banner.asm`).
The three defects here all assembled, linked, and *ran* — the banner printed and the exit
code was 0 — yet every one was a latent ABI violation that would crash under a slightly
different callee, optimizer, or Windows version. That is the trap of this ABI: **wrong
stack discipline usually looks like it works.** Freestanding asm has no CRT prologue to
paper over it and no sanitizer to flag it, so the arithmetic below is the only check.

Companion to [DESIGN-nadir.md](DESIGN-nadir.md) §2.2 (ABI stratum). Linux/SysV has its own
failure modes; this file is Win64-only.

---

## The two invariants everything reduces to

Every Win64 bug we hit is a violation of one of these:

1. **16-byte alignment *at the call*.** `rsp` must be a multiple of 16 at the moment a
   `call` instruction executes. Because `call` pushes an 8-byte return address, a callee
   sees `rsp ≡ 8 (mod 16)` on entry. So the rule, stated two equivalent ways:
   - before you emit `call`, `rsp` must be `≡ 0 (mod 16)`;
   - on entry to any function, `rsp` is `≡ 8 (mod 16)`, and every `sub rsp, N` you do
     before your own calls has to land back on `≡ 0`.

2. **32 bytes of shadow space.** The caller must reserve 32 bytes ("home space") directly
   above the return address before *any* call — even when the callee takes fewer than four
   args, even when it reads its args only from registers. The callee owns those 32 bytes
   and may clobber them. You allocate them; the callee assumes them.

Both are the *caller's* responsibility. A callee cannot fix a caller that got these wrong.

### The alignment arithmetic (memorize this)

Track `rsp mod 16` as a single running number through your prologue. Only two operations
change it:

| operation            | effect on `rsp mod 16` |
|----------------------|------------------------|
| function entry       | starts at `8`          |
| `push` (8 bytes)     | flips `0 ↔ 8`          |
| `sub rsp, N`         | subtract `N mod 16`    |
| `call` (pushes ret)  | callee sees your value `− 8` |

The single most common mistake: **`sub rsp, 32` does not change alignment.** 32 is a
multiple of 16, so it homes the shadow space but leaves any pre-existing `+8` skew exactly
where it was. If you entered at `≡ 8` and your only adjustment is `sub rsp, 32`, you call
*misaligned*. The fix is almost always `sub rsp, 40` (32 shadow + 8 to realign), or an odd
number of `push`es before the `sub`.

---

## Bug 1 — the leaf that never aligned (`cap_exit`)

```asm
cap_exit:
    sub     rsp, 32        ; WRONG: homes shadow space but rsp stays ≡ 8
    call    ExitProcess
```

Trace: entry `≡ 8`; `sub rsp, 32` → `8 − 0 = 8`; `call` executes at `≡ 8`. Misaligned.

`ExitProcess` happens to tolerate it, which is exactly why this survived a run. A callee
that executes an aligned SSE move (`movaps`) against its stack — which the compiler is free
to emit anywhere — would `#GP` fault instead.

**Fix:** reserve 40, not 32.

```asm
cap_exit:
    sub     rsp, 40        ; 32 shadow + 8 realign  → rsp ≡ 0 at the call
    call    ExitProcess
```

Trace: `8 − 40 = −32 ≡ 0 (mod 16)`. Aligned. (`40 mod 16 = 8`, so it flips the parity and
homes the shadow — one instruction doing both jobs.)

**Lesson:** a function that never returns is *still* a caller. "It exits anyway" does not
excuse the shadow space or the alignment — the fault happens *inside the callee you called*,
before your process is gone.

---

## Bug 2 — the entry point that skipped its duties (`_start`)

```asm
_start:
    lea     rcx, [rel banner]
    mov     rdx, banner_len
    call    cap_write        ; WRONG: no shadow space, and rsp ≡ 8 → misaligned
    xor     ecx, ecx
    call    cap_exit
```

The OS loader enters `_start` *as if it were `call`ed*: `rsp ≡ 8 (mod 16)`, no shadow space
staged. So `_start` has the same obligations as any function — it was just skipping them
because "it's the entry point" feels special. It isn't.

**Fix:** stage the frame once and keep it. Because `cap_exit` never returns, the frame is
never unwound — one `sub` covers the whole kernel.

```asm
_start:
    sub     rsp, 40          ; 32 shadow + 8 realign, once, for the kernel's lifetime
    lea     rcx, [rel banner]
    mov     rdx, banner_len
    call    cap_write        ; rsp ≡ 0 at the call ✓
    xor     ecx, ecx
    call    cap_exit
```

Trace: entry `≡ 8`; `sub rsp, 40` → `≡ 0`; both `call`s fire at `≡ 0`. ✓ And note the
frame persists across `cap_write`'s return (it has a balanced epilogue), so the second call
is still aligned.

**Lesson:** the entry point is a normal function with a caller you can't see (the loader).
Alignment and shadow space are not optional there.

---

## Bug 3 — output slot aliased an input arg (`cap_write` / `WriteFile`)

The most insidious of the three, because the aliasing was *masked by the values involved*.

`WriteFile(hFile, lpBuffer, nBytes, lpNumberOfBytesWritten, lpOverlapped)` — five args.
Args 1–4 go in `rcx/rdx/r8/r9`; **arg 5 goes on the stack, just above the 32-byte shadow
space**, i.e. at `[rsp+32]` after you `sub rsp, 32` for the shadow. We also need a local
DWORD for arg 4 to point at (`lpNumberOfBytesWritten`).

```asm
    sub     rsp, 16          ; local DWORD at [rsp]
    ...
    lea     r9,  [rsp]       ; arg4 &written  → points at [rsp]
    sub     rsp, 32          ; SHADOW_ALLOC
    mov     qword [rsp+32], 0 ; arg5 lpOverlapped = NULL
    call    WriteFile
```

The bug: after `sub rsp, 32`, the address `[rsp+32]` *is* the old `[rsp]` — the exact slot
`r9` points at. So arg 4 (an **output** pointer WriteFile writes the byte count into) and
arg 5 (an **input** the caller sets to NULL) are the *same 8 bytes*. It ran only because
we wrote 0 there first (satisfying the NULL read), and WriteFile then overwrote it with the
count (which we read back) — a coincidence of ordering, not a correct layout.

**Fix:** give the output DWORD its own slot that the arg-5 write can't reach.

```asm
    sub     rsp, 16          ; [rsp+8] = &written DWORD, [rsp+0] = pad
    ...
    lea     r9,  [rsp+8]     ; arg4 &written  → [rsp+8]
    sub     rsp, 32          ; SHADOW_ALLOC → arg5 lands at [rsp+32] == old [rsp+0]
    mov     qword [rsp+32], 0 ; arg5 NULL, distinct slot from &written ✓
    call    WriteFile
```

Now `&written` is at old `[rsp+8]` and arg 5 is at old `[rsp+0]` — different slots.

**Two lessons here:**

- **Stacked args live at `[rsp + 32 + 8*(n−5)]` after `SHADOW_ALLOC`**, so `[rsp+32]` is
  arg 5, `[rsp+40]` is arg 6, etc. When you also park locals below the shadow space, do the
  arithmetic to confirm they don't collide with the stacked args *after* the `sub rsp, 32`.
  Draw the frame; don't eyeball it.
- **Honor the return contract on the error path.** `WriteFile` returns `BOOL` (0 = failure).
  The original blindly returned `[rsp]` regardless — on failure that's a stale/garbage
  count. Test the BOOL and return the failure sentinel (nadir's `cap_write` contract:
  negative on failure):

  ```asm
      test    eax, eax
      jz      .fail
      mov     eax, dword [rsp+8]   ; success: bytes written
      jmp     .done
  .fail:
      mov     eax, -1
  .done:
  ```

---

## kernel32, never `syscall` (the OS stratum reason)

nadir issues `syscall` directly on Linux but **never on Windows** — Windows syscall numbers
are private and unstable across builds. All Win64 I/O and process control go through
kernel32 (`GetStdHandle`, `WriteFile`, `ExitProcess`), which is a normal DLL call and so
drags the entire Win64 call ABI (alignment + shadow space) back into every capability. That
is *why* freestanding Win64 asm has to get the convention exactly right: you don't get to
avoid the ABI by going freestanding, because the OS boundary is a `call`, not a trap.

---

## Debugging checklist

When a freestanding Win64 binary crashes (or "works" but you don't trust it):

1. **Walk `rsp mod 16` from function entry to each `call`.** Entry = 8. Each `push` flips
   parity. Each `sub` subtracts `N mod 16`. It must read `0` at every `call`. This finds
   nearly all alignment bugs by inspection.
2. **Confirm 32 bytes of shadow space before every call** — including in leaf functions,
   including at `_start`, including in functions that never return.
3. **For 5+ argument calls, draw the frame after `SHADOW_ALLOC`.** Arg 5 is `[rsp+32]`,
   arg 6 `[rsp+40]`, … Make sure no local you pointed a register at aliases those slots.
4. **Check the callee's return type on the failure path.** A `BOOL`-returning API that
   failed must not have its "success" output slot read as if it were valid.
5. **`dumpbin /imports foo.exe`** — confirms the import surface (freestanding nadir should
   show *only* `KERNEL32.dll` with the expected thunks, no CRT).
6. **Remember "it ran" proves nothing about alignment.** Misalignment faults only when the
   callee happens to touch the stack with an alignment-sensitive instruction. Verify the
   arithmetic; don't trust the exit code.

### How these three were caught

Not by crashing — by code review (Gemini on PR #1), then confirmed by walking the
`rsp mod 16` arithmetic above before writing the fix. The build stayed green throughout;
the imports stayed kernel32-only; the tests kept passing. The review caught what the run
could not, which is the whole point of the checklist: **on this ABI, a passing run is not
evidence of correctness.**
