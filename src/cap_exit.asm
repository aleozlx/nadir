; cap_exit.asm — capability `exit` (DESIGN §4, mandatory).
;
; One concept, two hand-written realizations, flag-selected:
;   win64: ExitProcess(code)
;   linux: syscall exit(code)          ; exit_group would also do; exit is enough at M0
;
; Contract:
;   in : arg1 = exit code   (win64 rcx / linux rdi)
;   Does not return. No epilogue by design — the process is gone.

%include "nadir.inc"

global cap_exit

%ifdef WIN64
; ---- win64 realization ------------------------------------------------------------
; arg arrives: rcx = code (Win64 arg1). ExitProcess never returns, so no shadow-space
; bookkeeping to unwind — we align rsp and call.
section .text
cap_exit:
    ; rcx already holds the code. Give the call its shadow space and go.
    SHADOW_ALLOC
    call    ExitProcess
    ; unreached
    hlt                         ; @ret cap_exit  (belt-and-suspenders trap if it returns)
                                ; @end cap_exit

%else
; ---- linux realization ------------------------------------------------------------
; arg arrives: rdi = code (SysV arg1) — already the syscall's arg1 register.
section .text
cap_exit:
    mov     rax, SYS_exit
    syscall                     ; does not return
    ; unreached
                                ; @end cap_exit
%endif
