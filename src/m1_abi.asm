; m1_abi.asm — M1 proof program: entry that puts the calling convention on trial
; (DESIGN §7.2).
;
; _start calls m1_fold(6,7,8,9) and converts two convention facts into observable
; behavior:
;
;   1. return value — fold(6,7,8,9) must come back as 6789 in rax. exit code starts
;      as (rax - 6789): zero iff the round trip held.
;   2. callee-saved preservation — _start plants a canary in r12 before the call;
;      m1_fold uses r12 internally, so the canary survives only if m1_fold's
;      push/pop discipline is real. A dead canary forces exit code 99.
;
; ONE body, both targets (DESIGN §2.2 v0.3): the staging below is the nadir call
; convention, so there is nothing left to %ifdef — the per-target translation
; happens inside cap_*, and the behavioral test exercises it end to end. The only
; per-target entry fact (loader alignment) is normalized by `and rsp, -16`, as in
; m0_banner. The behavioral test asserts stdout AND exit 0, identical on both
; targets (the exit code is a *diff*, so linux's 8-bit truncation is moot). The
; arguments 6,7,8,9 make the fold spell the argument order: any misrouted register
; between here and the seam prints different digits and a nonzero diff.

%include "nadir.inc"

global _start
extern m1_fold
extern cap_exit

; Arbitrary recognizable bit pattern; only equality matters.
%define CANARY 0x00C0FFEE

section .text
_start:
    and     rsp, -16            ; normalize entry: ≡8 (win64) / ≡0 (linux) → ≡0
    mov     r12, CANARY         ; callee-saved canary: m1_fold must hand it back intact
    mov     edi, 6              ; arg1 = a
    mov     esi, 7              ; arg2 = b
    mov     edx, 8              ; arg3 = c
    mov     ecx, 9              ; arg4 = d
    call    m1_fold             ; prints the line; rax = fold value
    sub     rax, 6789           ; exit code = result − expected (0 iff correct)
    cmp     r12, CANARY
    je      .verdict
    mov     eax, 99             ; callee-saved violated: unmistakable exit code
.verdict:
    mov     edi, eax            ; arg1 = exit code
    call    cap_exit            ; does not return
    ; unreached — cap_exit terminates the process. No fall-through into the void.
