; m1_abi.asm — M1 proof program: entry that puts the ABI stratum on trial (DESIGN §7.2).
;
; _start calls m1_fold(6,7,8,9) and converts two ABI facts into observable behavior:
;
;   1. return value — fold(6,7,8,9) must come back as 6789 in rax (same register,
;      both ABIs). exit code starts as (rax - 6789): zero iff the round trip held.
;   2. callee-saved preservation — _start plants a canary in r12 before the call;
;      m1_fold uses r12 internally, so the canary survives only if m1_fold's
;      push/pop discipline is real. A dead canary forces exit code 99.
;
; The behavioral test asserts stdout AND exit 0 — identical expectations on both
; targets (linux truncates exit codes to 8 bits, so the *diff*, not the value, is
; the exit code). The arguments 6,7,8,9 make the fold spell the argument order:
; a swapped arg register prints different digits and a nonzero diff.

%include "nadir.inc"

global _start
extern m1_fold
extern cap_exit

; Arbitrary recognizable bit pattern; only equality matters.
%define CANARY 0x00C0FFEE

section .text
_start:
%ifdef WIN64
    ; Loader enters with rsp ≡ 8 (mod 16), as if `call`ed. One sub covers the whole
    ; kernel: 32 shadow + 8 realign, never unwound because cap_exit does not return.
    sub     rsp, 40
    mov     r12, CANARY         ; callee-saved canary: m1_fold must hand it back intact
    mov     ecx, 6              ; arg1 = a
    mov     edx, 7              ; arg2 = b
    mov     r8d, 8              ; arg3 = c
    mov     r9d, 9              ; arg4 = d
    call    m1_fold             ; prints the line; rax = fold value
    sub     rax, 6789           ; exit code = result − expected (0 iff correct)
    cmp     r12, CANARY
    je      .verdict
    mov     eax, 99             ; callee-saved violated: unmistakable exit code
.verdict:
    mov     ecx, eax            ; arg1 = exit code
    call    cap_exit            ; does not return
%else
    ; SysV process entry: rsp ≡ 0 (mod 16) at _start, so a bare call is aligned.
    mov     r12, CANARY         ; callee-saved canary: m1_fold must hand it back intact
    mov     edi, 6              ; arg1 = a
    mov     esi, 7              ; arg2 = b
    mov     edx, 8              ; arg3 = c
    mov     ecx, 9              ; arg4 = d  — rcx: win64's arg1 register; the divergence
    call    m1_fold             ; prints the line; rax = fold value
    sub     rax, 6789           ; exit code = result − expected (0 iff correct)
    cmp     r12, CANARY
    je      .verdict
    mov     eax, 99             ; callee-saved violated: unmistakable exit code
.verdict:
    mov     edi, eax            ; arg1 = exit code
    call    cap_exit            ; does not return
%endif
    ; unreached — cap_exit terminates the process. No fall-through into the void.
