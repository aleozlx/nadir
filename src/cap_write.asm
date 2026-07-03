; cap_write.asm — capability `write` (DESIGN §4, mandatory).
;
; One concept, two hand-written realizations, flag-selected:
;   win64: GetStdHandle(STD_OUTPUT_HANDLE) -> WriteFile(h, buf, len, &written, NULL)
;   linux: syscall write(STDOUT_FD, buf, len)
;
; Contract (shared concept keys, per-target detail — DESIGN §2.2):
;   in : arg1 = buffer pointer   (win64 rcx / linux rdi)
;        arg2 = byte count        (win64 rdx / linux rsi)
;   out: rax  = bytes written (>=0) on success; negative/0 on failure.
;   The caller passes args in the *target's* arg1/arg2 registers; the body below is
;   written to that target's convention. cap_write is a real function (own
;   prologue/epilogue, ABI-clean) so it can later be promoted to a testable boundary.

%include "nadir.inc"

global cap_write

%ifdef WIN64
; ---- win64 realization ------------------------------------------------------------
; Local frame layout (below rbp): we need a 4-byte DWORD for lpNumberOfBytesWritten
; and a stack slot for WriteFile's 5th argument (lpOverlapped = NULL), plus 32 bytes
; of shadow space per call. We build one frame covering both calls.
;
; args arrive: rcx = buf, rdx = len  (Win64 arg1/arg2).
section .text
cap_write:
    push    rbp
    mov     rbp, rsp
    push    rsi                 ; callee-saved; we stash buf/len across GetStdHandle
    push    rdi
    ; Preserve incoming args across the GetStdHandle call (which clobbers rcx/rdx).
    mov     rsi, rcx            ; rsi = buf
    mov     rdi, rdx            ; rdi = len
    ; Reserve locals: 8 bytes for the "bytes written" DWORD (kept 8 for alignment).
    ; Frame must leave rsp 16-aligned at the inner call sites. After push rbp/rsi/rdi
    ; (3 pushes) rsp is 16-aligned; subtract a 16-multiple to stay aligned.
    sub     rsp, 16             ; [rsp+0] = lpNumberOfBytesWritten (DWORD)

    ; --- h = GetStdHandle(STD_OUTPUT_HANDLE) ---
    mov     ecx, STD_OUTPUT_HANDLE
    SHADOW_ALLOC
    call    GetStdHandle
    SHADOW_FREE
    ; rax = handle

    ; --- WriteFile(h, buf, len, &written, NULL) ---
    mov     rcx, rax            ; arg1 hFile        = handle
    mov     rdx, rsi            ; arg2 lpBuffer     = buf
    mov     r8,  rdi            ; arg3 nNumberOfBytesToWrite = len
    lea     r9,  [rsp]          ; arg4 lpNumberOfBytesWritten = &written
    SHADOW_ALLOC                ; 32B shadow; arg5 sits just above it at [rsp+32]
    mov     qword [rsp+32], 0   ; arg5 lpOverlapped = NULL
    call    WriteFile
    SHADOW_FREE
    ; rax = BOOL (nonzero on success). Return bytes actually written for the caller.
    mov     eax, dword [rsp]    ; rax = written (zero-extended)

    add     rsp, 16
    pop     rdi
    pop     rsi
    pop     rbp
    ret                         ; @ret cap_write
                                ; @end cap_write

%else
; ---- linux realization ------------------------------------------------------------
; args arrive: rdi = buf, rsi = len  (SysV arg1/arg2). Rearrange to the write syscall.
section .text
cap_write:
    mov     rdx, rsi            ; arg3 count = len
    mov     rsi, rdi            ; arg2 buf   = buf
    mov     rdi, STDOUT_FD      ; arg1 fd    = stdout
    mov     rax, SYS_write
    syscall                     ; rax = bytes written (or -errno)
    ret                         ; @ret cap_write
                                ; @end cap_write
%endif
