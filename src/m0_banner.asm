; m0_banner.asm — M0 proof program (DESIGN §7.1, "prove the seam").
;
; A freestanding kernel: no CRT, no libc, nadir owns entry. It exercises the two
; mandatory capabilities and nothing else:
;     cap_write(banner, banner_len)   ; print a result
;     cap_exit(0)                     ; clean, explicit termination
;
; Byte-identical source across intent and artifact — the assembler sees exactly what
; the agent reasons about. The only per-target facts are (a) which registers carry
; arg1/arg2 (ABI stratum, §2.2) and (b) that _start must never fall off the end
; (there is no runtime to return to).

%include "nadir.inc"

global _start
extern cap_write
extern cap_exit

section .data
banner:     db  "nadir M0: seam proven", 10   ; 10 = '\n'
banner_len: equ $ - banner

section .text
_start:
%ifdef WIN64
    ; --- win64: arg1=rcx, arg2=rdx (§2.2) ---
    ; The loader enters _start with rsp 16-aligned+8 (as if `call`ed). Win64 requires
    ; 32 bytes of shadow space and rsp 16-aligned at every call. Reserve 40 once
    ; (32 shadow + 8 realign) and keep it for the whole kernel — cap_exit never returns,
    ; so this frame is never unwound.
    sub     rsp, 40
    lea     rcx, [rel banner]       ; arg1 = buffer
    mov     rdx, banner_len         ; arg2 = length
    call    cap_write
    xor     ecx, ecx                ; arg1 = exit code 0
    call    cap_exit                ; does not return
%else
    ; --- linux: arg1=rdi, arg2=rsi (§2.2) ---
    lea     rdi, [rel banner]       ; arg1 = buffer
    mov     rsi, banner_len         ; arg2 = length
    call    cap_write
    xor     edi, edi                ; arg1 = exit code 0
    call    cap_exit                ; does not return
%endif
    ; unreached — cap_exit terminates the process. No fall-through into the void.
