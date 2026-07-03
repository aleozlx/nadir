; cap_write.asm — capability `write` (DESIGN §4, mandatory).
;
; One concept, two hand-written realizations, flag-selected:
;   win64: GetStdHandle(STD_OUTPUT_HANDLE) -> WriteFile(h, buf, len, &written, NULL)
;   linux: syscall write(STDOUT_FD, buf, len)
;
; Contract — nadir call convention (nadir.inc; DESIGN §2.2), BOTH targets:
;   in : rdi = buffer pointer, rsi = byte count
;   out: rax = bytes written (>=0) on success; negative on failure.
;   The seam translates: the win64 body marshals nadir args into the Win64 call ABI
;   (and owns its shadow-space/alignment duties); the linux body is already in SysV
;   roles so it marshals almost nothing. cap_write is a real function (own
;   prologue/epilogue) so it can later be promoted to a testable boundary.

%include "nadir.inc"

global cap_write

%ifdef WIN64
; ---- win64 realization ------------------------------------------------------------
; nadir args rdi/rsi are Win64 CALLEE-SAVED, so they survive the kernel32 calls
; untouched — the arg registers double as the stash, no push/pop dance needed.
; (Under the nadir convention rdi/rsi are volatile, so clobbering them is fine too.)
;
; Frame: one 24-byte reservation covers realignment and locals. Alignment walk
; (docs/asm-debugging-guide.md): entry rsp ≡ 8 (mod 16); sub 24 → ≡ 0; SHADOW_ALLOC
; is a 16-multiple so both kernel32 calls fire at ≡ 0.
section .text
cap_write:
    sub     rsp, 24             ; realign + locals: [rsp+8] = &written DWORD, [rsp+0] pad

    ; --- h = GetStdHandle(STD_OUTPUT_HANDLE) --- (preserves rdi/rsi)
    mov     ecx, STD_OUTPUT_HANDLE
    SHADOW_ALLOC
    call    GetStdHandle
    SHADOW_FREE
    ; rax = handle

    ; --- WriteFile(h, buf, len, &written, NULL) ---
    mov     rcx, rax            ; arg1 hFile        = handle
    mov     rdx, rdi            ; arg2 lpBuffer     = nadir arg1 (buf)
    mov     r8,  rsi            ; arg3 nNumberOfBytesToWrite = nadir arg2 (len)
    lea     r9,  [rsp+8]        ; arg4 lpNumberOfBytesWritten = &written
    SHADOW_ALLOC                ; 32B shadow; stacked arg5 sits just above at [rsp+32]
    mov     qword [rsp+32], 0   ; arg5 lpOverlapped = NULL — old [rsp+0], so it can't
                                ; alias the &written slot at old [rsp+8] (guide, bug 3)
    call    WriteFile
    SHADOW_FREE
    ; rax = BOOL: 0 == failure. Honor the contract (out: rax<0 on failure) instead of
    ; returning a stale/garbage byte count.
    test    eax, eax
    jz      .fail
    mov     eax, dword [rsp+8]  ; rax = written (zero-extended)
    jmp     .done
.fail:
    mov     eax, -1             ; contract: negative on failure
.done:
    add     rsp, 24
    ret                         ; @ret cap_write
                                ; @end cap_write

%else
; ---- linux realization ------------------------------------------------------------
; nadir args arrive in SysV roles already (rdi = buf, rsi = len); rearrange to the
; write syscall's fd/buf/len order.
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
