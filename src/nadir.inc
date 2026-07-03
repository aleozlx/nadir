; nadir.inc — shared seam/ABI knowledge for the corpus.
;
; This file is the in-source echo of intent-map's key<->concept model (DESIGN §2.2):
; one logical concept, per-target detail selected by the build flag. Nothing here is
; a resolver — WIN64 is defined by the assembler invocation (`nasm -D WIN64`), and the
; %ifdef picks the hand-written realization. Der Schalter ersetzt den Compiler.
;
; Two targets:
;   WIN64 defined   -> Windows x64, capabilities call through kernel32 (call ABI).
;   WIN64 undefined -> Linux x86-64, capabilities issue `syscall` directly.
;
; ---- The nadir call convention (DESIGN §2.2, v0.3) --------------------------------
; All nadir-to-nadir calls use ONE static convention on BOTH targets; the target ABI
; exists only inside cap_* realizations, which translate at the seam. Real registers,
; no macro skin — the source you read is the register file you get.
;
;   args         : rdi, rsi, rdx, rcx          (arg5+ undefined until a capability
;                                               needs it — pull-based)
;   return       : rax
;   callee-saved : rbx, rbp, r12–r15           (the win64∩sysv intersection, so both
;                                               OS boundaries preserve it for free)
;   volatile     : rax, rcx, rdx, rsi, rdi, r8–r11, all xmm   (the win64∪sysv union)
;   alignment    : rsp ≡ 0 (mod 16) at every call (needed transitively for kernel32;
;                  free on linux)
;   shadow space : none — it is a Win64 requirement for calling Win64 functions, so
;                  it lives inside cap_* win64 bodies, next to the calls that need it
;   red zone     : none
;
; The roles are SysV's (see docs/abi-lineage.md for why SysV picked them); the linux
; realizations therefore marshal almost nothing, and the win64 realizations own the
; translation. Code entered BY the OS (_start, future callbacks like WndProc) arrives
; in the target's convention and must normalize before touching nadir code.
; Eine Zunge im Haus, zwei Dolmetscher an der Tür.

%ifndef NADIR_INC
%define NADIR_INC

%ifdef WIN64
    ; ---- OS stratum: win64, capability dispatch through kernel32 -------------------
    ; We never issue `syscall` directly on Windows (numbers are private/unstable, §4);
    ; I/O goes through kernel32, which drags the Win64 call ABI back in — but only
    ; HERE, inside the seam. Callers speak the nadir convention above.
    extern GetStdHandle
    extern WriteFile
    extern ExitProcess

    ; GetStdHandle nStdHandle argument. -11 == STD_OUTPUT_HANDLE (winbase.h),
    ; encoded here as its unsigned 32-bit two's-complement so `mov ecx, imm` is clean.
    %define STD_OUTPUT_HANDLE 0xFFFFFFF5   ; (DWORD)-11

    ; Win64 call-ABI duty (§2.2): shadow space. The convention mandates 32 bytes of
    ; caller-allocated "home space" for the first four register args before *any*
    ; call into Win64 code. These macros bracket a kernel32 call site inside a
    ; capability realization. Keep rsp 16-aligned at the call.
    %macro SHADOW_ALLOC 0
        sub     rsp, 32
    %endmacro
    %macro SHADOW_FREE 0
        add     rsp, 32
    %endmacro

%else
    ; ---- OS stratum: linux x86-64, direct syscall ---------------------------------
    ; Convention (§4 caveat): number in RAX, args RDI/RSI/RDX/R10/R8/R9, `syscall`
    ; clobbers RCX and R11. arg4 is R10 (not RCX) because the insn steals RCX.
    %define SYS_write   1
    %define SYS_exit    60
    %define STDOUT_FD   1
%endif

%endif ; NADIR_INC
