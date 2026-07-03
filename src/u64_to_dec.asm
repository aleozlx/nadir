; u64_to_dec.asm — unsigned 64-bit integer to decimal ASCII (M1 helper).
;
; Almost portable-stratum (DESIGN §2.1): the divide loop is pure registers, no calls,
; no syscalls, identical on both targets. Only the *arg pickup* is ABI-stratum — the
; two-instruction %ifdef below is the whole divergence. The body clobbers only
; rax/rdx/r8/r9, which are volatile under BOTH conventions, so the shared loop
; violates neither callee-saved set.
;
; Contract (shared concept keys, per-target detail — DESIGN §2.2):
;   in : arg1 = value     (win64 rcx / linux rdi)
;        arg2 = buf_end   (win64 rdx / linux rsi) — one past where the last digit goes
;   out: rax = pointer to the first digit; digits occupy [rax, buf_end).
;   Caller owns the buffer and must size it for the worst case (20 digits for u64).
;   Digits are generated least-significant-first, walking backward from buf_end.

%include "nadir.inc"

global u64_to_dec

section .text
u64_to_dec:
%ifdef WIN64
    mov     rax, rcx            ; arg1 = value
    mov     r8,  rdx            ; arg2 = buf_end (write cursor)
%else
    mov     rax, rdi            ; arg1 = value
    mov     r8,  rsi            ; arg2 = buf_end (write cursor)
%endif
    mov     r9d, 10             ; divisor (zero-extends to r9)
.digit:
    xor     edx, edx            ; div takes rdx:rax; rdx must be 0
    div     r9                  ; rax = quotient, rdx = remainder
    add     dl, '0'
    dec     r8
    mov     [r8], dl            ; store digit, walking backward
    test    rax, rax
    jnz     .digit              ; loop runs at least once, so 0 renders as "0"
    mov     rax, r8             ; return pointer to first (most significant) digit
    ret                         ; @ret u64_to_dec
                                ; @end u64_to_dec
