# nadir intent bindings — M0

The canonical `.asm` is the artifact; **intent is an out-of-band projection onto it**
(DESIGN §1, §6). This file is that projection captured in prose *now*, at M0, before
the `intent-map` DB is stood up (its C build needs a C compiler + libsqlite3/FTS5 —
deferred, pull-based, DESIGN §4/§9). The vendored tool lives at `var/intent-map/`.

Each binding below is written to `intent-map`'s model so loading is mechanical later:
a stable opaque **key** (`<file>:<symbol>`, the convention its `view` verb reads), a
one-line **summary** (glance tier), and free-form **detail** (commit tier). To load,
each entry becomes:

```sh
intent-map allocate --label "<key>" --summary "<summary>" --detail "<detail>"
```

The key is opaque; the meaning lives only in summary/detail, never in the key.

---

## Capability keys (the closed vocabulary — DESIGN §4)

These are the two **mandatory** M0 capabilities. Shared concept, per-target detail
(DESIGN §2.2) — the correspondence lives in the binding, not in a resolver.

### `cap_write.asm:cap_write`
**summary:** capability `write` — emit bytes to stdout; buffer+len in, bytes-written out.
**detail:** Mandatory capability (DESIGN §4). One concept, two hand-written realizations
selected by the `-D WIN64` build flag.
  · win64 → `GetStdHandle(STD_OUTPUT_HANDLE=-11)` then
    `WriteFile(h, buf, len, &written, NULL)`; drags the Win64 call ABI (shadow space,
    RCX/RDX/R8/R9, arg5 on stack). Never issues `syscall` directly (numbers private).
  · linux → `syscall write(STDOUT_FD=1, buf, len)`; number 1 in RAX, args RDI/RSI/RDX.
  Contract: arg1=buffer (rcx/rdi), arg2=byte count (rdx/rsi); returns bytes written in
  RAX. Written as a real function (own prologue/epilogue) so it can be promoted to a
  testable boundary (DESIGN §6.2).

### `cap_exit.asm:cap_exit`
**summary:** capability `exit` — terminate the process with a code; never returns.
**detail:** Mandatory capability (DESIGN §4). One concept, two realizations, flag-selected.
  · win64 → `ExitProcess(code)`, code in RCX (Win64 arg1).
  · linux → `syscall exit(code)` (number 60), code in RDI (SysV arg1).
  Contract: arg1=exit code. No epilogue by design — the process is gone. Together with
  `write`, this is the complete M0 seam: a freestanding kernel that prints and exits.

---

## Program keys

### `m0_banner.asm:_start`
**summary:** M0 proof kernel — prints a fixed banner via `write`, then `exit(0)`.
**detail:** DESIGN §7.1 "prove the seam." Freestanding entry (no CRT; nadir owns
`_start`). Calls `cap_write(banner, banner_len)` then `cap_exit(0)`. The only per-target
facts are which registers carry arg1/arg2 (ABI stratum §2.2) and that `_start` must not
fall off the end — there is no runtime to return to. Prints exactly
`nadir M0: seam proven\n` and exits 0. Round-trips the reconcile loop → freestanding
thesis holds.

### `m0_banner.asm:banner`
**summary:** the M0 result string — `"nadir M0: seam proven\n"`.
**detail:** `.data` bytes, 22 chars + newline. `banner_len` is `$ - banner` (NASM
assemble-time length). Not a capability; the payload the seam carries.

---

## ABI-stratum concept keys (DESIGN §2.2 — documentation of invariant knowledge)

These are *not* labels in the asm; they are the shared concept keys whose per-target
detail keeps the two realizations coherent. Load them as file-level notes or under a
synthetic `abi:` file so `view` groups them.

### `abi:arg1`
**summary:** logical first argument.
**detail:** win64 → `rcx`; sysv/linux → `rdi`.

### `abi:arg2`
**summary:** logical second argument.
**detail:** win64 → `rdx`; sysv/linux → `rsi`.

### `abi:shadow-space`
**summary:** Win64 caller-allocated home space for a call.
**detail:** win64 → `sub rsp, 32` before *any* call (mandatory 32-byte shadow space);
sysv/linux → none. Realized in `nadir.inc` as `SHADOW_ALLOC`/`SHADOW_FREE`.

### `abi:syscall-args`
**summary:** Linux syscall argument registers.
**detail:** number in RAX; args RDI, RSI, RDX, **R10**, R8, R9. The `syscall` insn
clobbers RCX (return addr) and R11 — R10 substitutes for arg4. Windows has no dual:
I/O goes *through* kernel32, not via direct `syscall` (numbers private/unstable).
