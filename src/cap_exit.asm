; cap_exit.asm — capability `exit` (DESIGN §4, mandatory).
;
; One concept, two hand-written realizations, flag-selected:
;   win64: ExitProcess(code)
;   linux: syscall exit(code)          ; exit_group would also do; exit is enough
;
; Contract — nadir call convention (nadir.inc; DESIGN §2.2), BOTH targets:
;   in : rdi = exit code
;   Does not return. No epilogue by design — the process is gone.

%include "nadir.inc"

global cap_exit

%ifdef WIN64
; ---- win64 realization ------------------------------------------------------------
; Seam translation: nadir arg1 (rdi) → Win64 arg1 (rcx), then the Win64 call duties.
; On entry rsp is 16-aligned+8 (the caller's `call` pushed the return address); a bare
; 32-byte shadow would leave the +8 skew, so reserve 32 shadow + 8 realignment = 40,
; which both aligns and homes the args (docs/asm-debugging-guide.md, bug 1).
section .text
cap_exit:
    mov     rcx, rdi            ; Win64 arg1 = nadir arg1 (exit code)
    sub     rsp, 40
    call    ExitProcess
    ; unreached
    hlt                         ; @ret cap_exit  (belt-and-suspenders trap if it returns)
                                ; @end cap_exit

%else
; ---- linux realization ------------------------------------------------------------
; nadir arg1 (rdi) is already the syscall's arg1 register — zero marshalling.
section .text
cap_exit:
    mov     rax, SYS_exit
    syscall                     ; does not return
    ; unreached
                                ; @end cap_exit
%endif
