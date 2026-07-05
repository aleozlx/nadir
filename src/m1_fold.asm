; m1_fold.asm — M1 proof kernel: the non-leaf, 4-arg ABI exercise (DESIGN §7.2).
;
; fold(a, b, c, d) = ((a*10 + b)*10 + c)*10 + d — a positional base-10 fold. The
; function is deliberately ASYMMETRIC: every permutation of the arguments yields a
; different result, so a misrouted arg register anywhere between _start and the seam
; changes the printed digits and fails the behavioral test. fold(6,7,8,9) = 6789 —
; the output literally spells the argument order.
;
; ONE body, both targets (DESIGN §2.2 v0.3): m1_fold speaks the nadir call
; convention — args rdi/rsi/rdx/rcx, result rax, no shadow space (that duty lives
; inside cap_* win64). What it still pins:
;   · the seam translation — cap_write receives nadir args on both targets and must
;     marshal them into kernel32/syscall correctly, twice, mid-computation.
;   · callee-saved discipline, both directions: m1_fold preserves r12–r15 for its
;     caller (push/pop), and *relies* on them to carry a..d and the result across
;     its three inner calls — if a capability clobbered them, the digits print wrong.
;
; Contract:
;   in : rdi, rsi, rdx, rcx = a, b, c, d
;   out: rax = fold value
;   effect: writes "nadir M1: fold(a,b,c,d) = <value>\n" to stdout via cap_write.
;   r12–r15 are the stash *because* they are convention callee-saved — and that set
;   is the win64∩sysv intersection, so even the OS boundaries preserve it for free.

%include "nadir.inc"

global m1_fold
extern cap_write
extern u64_to_dec

section .data
m1_prefix:      db  "nadir M1: fold(a,b,c,d) = "
m1_prefix_len:  equ $ - m1_prefix

section .bss
; Scratch for the rendered value: u64_to_dec fills digits backward ending at
; dec_buf+20; [dec_buf+20] holds the trailing newline. 20 digit slots cover the
; u64 worst case exactly.
dec_buf:        resb 21

section .text
; Alignment walk (docs/asm-debugging-guide.md; the convention keeps the Win64 rule
; on both targets): entry rsp ≡ 8 (mod 16); four pushes flip parity four times →
; still ≡ 8; sub 8 → ≡ 0 at every inner call. No shadow space — nadir callees don't
; assume home slots; the kernel32 shadow is allocated inside cap_write itself.
m1_fold:
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8              ; realign only, held across all three calls
    mov     r12, rdi            ; a → callee-saved: must survive cap_write below
    mov     r13, rsi            ; b
    mov     r14, rdx            ; c
    mov     r15, rcx            ; d

    ; --- cap_write(prefix, prefix_len) — clobbers every convention-volatile reg ---
    lea     rdi, [rel m1_prefix]
    mov     rsi, m1_prefix_len
    call    cap_write

    ; --- the fold: a..d survived the call only if callee-saved discipline held ---
    mov     rax, r12
    imul    rax, 10
    add     rax, r13
    imul    rax, 10
    add     rax, r14
    imul    rax, 10
    add     rax, r15            ; rax = fold(a,b,c,d)
    mov     r12, rax            ; result must survive two more calls

    ; --- render: digits backward ending at dec_buf+20, newline at [dec_buf+20] ---
    mov     byte [rel dec_buf+20], 10
    mov     rdi, rax            ; arg1 = value
    lea     rsi, [rel dec_buf+20]  ; arg2 = buf_end
    call    u64_to_dec          ; rax → first digit

    ; --- cap_write(first_digit, digits+newline) ---
    lea     rsi, [rel dec_buf+21]
    sub     rsi, rax            ; arg2 = length through the newline
    mov     rdi, rax            ; arg1 = buffer
    call    cap_write

    mov     rax, r12            ; return the fold value
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret                         ; @ret m1_fold
                                ; @end m1_fold
