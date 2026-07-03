; m1_fold.asm — M1 proof kernel: the non-leaf, 4-arg ABI-stratum exercise (DESIGN §7.2).
;
; fold(a, b, c, d) = ((a*10 + b)*10 + c)*10 + d — a positional base-10 fold. The
; function is deliberately ASYMMETRIC: every permutation of the arguments yields a
; different result, so a swapped arg register in either realization changes the
; printed digits and fails the behavioral test. fold(6,7,8,9) = 6789 — the output
; literally spells the argument order.
;
; What M1 pins that M0 could not:
;   · arg3/arg4 — the registers where the conventions diverge most visibly
;     (win64 r8/r9 vs sysv rdx/rcx; sysv arg4 is rcx, which win64 uses for arg1).
;   · callee-saved preservation, both directions: m1_fold preserves r12–r15 for its
;     caller (push/pop), and *relies* on them to carry a..d and the result across
;     its own calls — if cap_write clobbered them, the digits print wrong.
;   · non-leaf frame discipline: prologue/epilogue bracketing three inner calls.
;
; Contract:
;   in : arg1..arg4 = a, b, c, d   (win64 rcx/rdx/r8/r9 · linux rdi/rsi/rdx/rcx)
;   out: rax = fold value (same register, both ABIs)
;   effect: writes "nadir M1: fold(a,b,c,d) = <value>\n" to stdout via cap_write.
;   r12–r15 are stash registers *because* they sit in the callee-saved intersection
;   of the two conventions — the one choice that reads identically in both bodies.

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
%ifdef WIN64
; ---- win64 realization ------------------------------------------------------------
; args arrive: rcx=a, rdx=b, r8=c, r9=d (Win64 arg1..arg4).
; Alignment walk (docs/asm-debugging-guide.md): entry rsp ≡ 8 (mod 16); four pushes
; flip parity four times → still ≡ 8; sub 40 (≡ 8 mod 16) → ≡ 0 at every inner call,
; with the 40 bytes doubling as the mandatory 32-byte shadow space.
m1_fold:
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40             ; 32 shadow + 8 realign, held across all three calls
    mov     r12, rcx            ; a → callee-saved: must survive cap_write below
    mov     r13, rdx            ; b
    mov     r14, r8             ; c
    mov     r15, r9             ; d

    ; --- cap_write(prefix, prefix_len) — clobbers every volatile register ---
    lea     rcx, [rel m1_prefix]
    mov     rdx, m1_prefix_len
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
    mov     rcx, rax            ; arg1 = value
    lea     rdx, [rel dec_buf+20]  ; arg2 = buf_end
    call    u64_to_dec          ; rax → first digit

    ; --- cap_write(first_digit, digits+newline) ---
    lea     rdx, [rel dec_buf+21]
    sub     rdx, rax            ; arg2 = length through the newline
    mov     rcx, rax            ; arg1 = buffer
    call    cap_write

    mov     rax, r12            ; return the fold value
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret                         ; @ret m1_fold
                                ; @end m1_fold

%else
; ---- linux realization ------------------------------------------------------------
; args arrive: rdi=a, rsi=b, rdx=c, rcx=d (SysV arg1..arg4 — note arg4 lands in rcx,
; the register win64 uses for arg1; this is the divergence M1 exists to pin).
; Alignment walk: SysV also requires rsp ≡ 0 (mod 16) at every call. Entry ≡ 8; four
; pushes → ≡ 8; sub 8 → ≡ 0 at the inner calls. No shadow space on this side.
m1_fold:
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8              ; realign only — SysV has no shadow space
    mov     r12, rdi            ; a → callee-saved: must survive cap_write below
    mov     r13, rsi            ; b
    mov     r14, rdx            ; c
    mov     r15, rcx            ; d

    ; --- cap_write(prefix, prefix_len) — syscall clobbers rcx/r11 + volatiles ---
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
%endif
