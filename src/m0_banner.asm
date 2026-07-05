; m0_banner.asm — M0 proof program (DESIGN §7.1, "prove the seam").
;
; A freestanding kernel: no CRT, no libc, nadir owns entry. It exercises the two
; mandatory capabilities and nothing else:
;     cap_write(banner, banner_len)   ; print a result
;     cap_exit(0)                     ; clean, explicit termination
;
; ONE body, both targets (DESIGN §2.2 v0.3): callers speak the nadir call convention
; (args rdi/rsi, no shadow space — that duty lives inside cap_* win64). The only
; per-target fact left is how the OS enters _start: the win64 loader arrives with
; rsp ≡ 8 (mod 16), linux with ≡ 0. `and rsp, -16` normalizes both to the
; convention's ≡ 0-at-call rule in one portable instruction. (On linux this discards
; the argc/argv block rsp pointed at — capture rsp first when a program needs args.)
; _start must never fall off the end — there is no runtime to return to.

%include "nadir.inc"

global _start
extern cap_write
extern cap_exit

section .data
banner:     db  "nadir M0: seam proven", 10   ; 10 = '\n'
banner_len: equ $ - banner

section .text
_start:
    and     rsp, -16                ; normalize entry: ≡8 (win64) / ≡0 (linux) → ≡0
    lea     rdi, [rel banner]       ; arg1 = buffer
    mov     rsi, banner_len         ; arg2 = length
    call    cap_write
    xor     edi, edi                ; arg1 = exit code 0
    call    cap_exit                ; does not return
    ; unreached — cap_exit terminates the process. No fall-through into the void.
