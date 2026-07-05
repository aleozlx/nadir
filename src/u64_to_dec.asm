; u64_to_dec.asm — unsigned 64-bit integer to decimal ASCII (M1 helper).
;
; ONE body, both targets: pure computation in the nadir call convention (nadir.inc;
; DESIGN §2.1/§2.2 v0.3). The loop clobbers only rax/rdx/r8/r9 — inside the
; convention's volatile set — and preserves its callee-saved set by not touching it.
;
; Contract:
;   in : rdi = value
;        rsi = buf_end — one past where the last digit goes
;   out: rax = pointer to the first digit; digits occupy [rax, buf_end).
;   Caller owns the buffer and must size it for the worst case (20 digits for u64).
;   Digits are generated least-significant-first, walking backward from buf_end.

%include "nadir.inc"

global u64_to_dec

section .text
u64_to_dec:
    mov     rax, rdi            ; arg1 = value
    mov     r8,  rsi            ; arg2 = buf_end (write cursor)
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
