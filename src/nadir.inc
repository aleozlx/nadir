; nadir.inc — shared seam/ABI knowledge for the M0 corpus.
;
; This file is the in-source echo of intent-map's key<->concept model (DESIGN §2.2):
; one logical concept, per-target detail selected by the build flag. Nothing here is
; a resolver — WIN64 is defined by the assembler invocation (`nasm -D WIN64`), and the
; %ifdef picks the hand-written realization. Der Schalter ersetzt den Compiler.
;
; Two targets at M0:
;   WIN64 defined   -> Windows x64, capabilities call through kernel32 (call ABI).
;   WIN64 undefined -> Linux x86-64, capabilities issue `syscall` directly.

%ifndef NADIR_INC
%define NADIR_INC

%ifdef WIN64
    ; ---- OS stratum: win64, capability dispatch through kernel32 -------------------
    ; We never issue `syscall` directly on Windows (numbers are private/unstable, §4);
    ; I/O goes through kernel32, which drags the Win64 call ABI back in.
    extern GetStdHandle
    extern WriteFile
    extern ExitProcess

    ; GetStdHandle nStdHandle argument. -11 == STD_OUTPUT_HANDLE (winbase.h),
    ; encoded here as its unsigned 32-bit two's-complement so `mov ecx, imm` is clean.
    %define STD_OUTPUT_HANDLE 0xFFFFFFF5   ; (DWORD)-11

    ; ABI stratum (§2.2): shadow space. The Win64 convention mandates 32 bytes of
    ; caller-allocated "home space" for the first four register args before *any*
    ; call. These macros bracket a call site. Keep rsp 16-aligned at the call.
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
