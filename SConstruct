# SConstruct — nadir build spine (DESIGN §8).
#
# "scons + build flag is the spine — no CLI through M2." Target selection is a flag,
# not a program:  `scons target=win64`  /  `scons target=linux`.
# scons wires: nasm (assemble, -D WIN64 on win64) then the target's linker
# (link.exe /nodefaultlib on win64; ld on linux). No CRT on either side — nadir owns
# _start. The two hand-written realizations live in one source tree; the flag picks.
#
# Usage:
#   scons                 # target defaults to the host (win64 on Windows)
#   scons target=linux    # cross-author: assembles ELF objs to validate syntax;
#                         # links only where `ld` exists (Manjaro/Deck), not on Windows.
#   scons -c              # clean

import os
import platform
import subprocess

# ---------------------------------------------------------------------------------
# Target selection (the flag that replaces the compiler).
# ---------------------------------------------------------------------------------
default_target = "win64" if platform.system() == "Windows" else "linux"
target = ARGUMENTS.get("target", default_target)
if target not in ("win64", "linux"):
    print("error: target must be 'win64' or 'linux' (got %r)" % target)
    Exit(2)

SRC = "src"
BUILD = "build"

# The corpus, one program per milestone. Every program links the mandatory
# capabilities (DESIGN §4) plus its own units; the unit named after the program
# provides _start.
CAPS = ["cap_write", "cap_exit"]
PROGRAMS = {
    "m0_banner": ["m0_banner"],                      # M0: prove the seam
    "m1_abi": ["m1_abi", "m1_fold", "u64_to_dec"],   # M1: prove the ABI stratum
}


# ---------------------------------------------------------------------------------
# Toolchain discovery. nasm and (on win64) the MSVC linker + SDK libs are located
# lazily; failures are reported with actionable messages rather than a stack trace.
# ---------------------------------------------------------------------------------
def find_on_path_or(name, candidates):
    """Return `name` if resolvable via PATH, else the first existing candidate path."""
    from shutil import which
    hit = which(name)
    if hit:
        return hit
    for c in candidates:
        if c and os.path.exists(c):
            return c
    return None


def find_nasm():
    candidates = [
        os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "NASM", "nasm.exe"),
        os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "NASM", "nasm.exe"),
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "bin", "NASM", "nasm.exe"),
    ]
    return find_on_path_or("nasm", candidates)


def _vswhere():
    """Locate an MSVC install via vswhere; return its installationPath or None."""
    pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    vsw = os.path.join(pf86, "Microsoft Visual Studio", "Installer", "vswhere.exe")
    if not os.path.exists(vsw):
        return None
    try:
        out = subprocess.check_output(
            [vsw, "-latest", "-products", "*",
             "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
             "-property", "installationPath"],
            text=True,
        ).strip()
        return out or None
    except Exception:
        return None


def _version_key(path):
    """Sort key that orders dotted version dir names numerically, not lexically.

    Plain string sort misorders versions of unequal digit-width (e.g. "10.0.9999.0"
    would sort *after* "10.0.10240.0" because '9' > '1'). Split each name into digit /
    non-digit runs and compare digit runs as ints so 10240 > 9999.
    """
    import re
    return [int(t) if t.isdigit() else t
            for t in re.split(r"(\d+)", os.path.basename(path))]


def _newest_subdir(path):
    if not os.path.isdir(path):
        return None
    subs = [os.path.join(path, d) for d in os.listdir(path)]
    subs = [d for d in subs if os.path.isdir(d)]
    return sorted(subs, key=_version_key)[-1] if subs else None


def find_msvc_link():
    """Return (link_exe, [lib_dirs]) for x64, or (None, [])."""
    install = _vswhere()
    link_exe = None
    lib_dirs = []
    if install:
        msvc_root = os.path.join(install, "VC", "Tools", "MSVC")
        ver_dir = _newest_subdir(msvc_root)
        if ver_dir:
            cand = os.path.join(ver_dir, "bin", "Hostx64", "x64", "link.exe")
            if os.path.exists(cand):
                link_exe = cand
    # Windows SDK libs (kernel32.lib lives here, under um\x64).
    pf86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    sdk_lib = os.path.join(pf86, "Windows Kits", "10", "Lib")
    sdk_ver = _newest_subdir(sdk_lib)
    if sdk_ver:
        for leaf in ("um", "ucrt"):
            d = os.path.join(sdk_ver, leaf, "x64")
            if os.path.isdir(d):
                lib_dirs.append(d)
    # MSVC's own libs (needed if we ever pull ucrt; harmless to include when present).
    if install:
        ver_dir = _newest_subdir(os.path.join(install, "VC", "Tools", "MSVC"))
        if ver_dir:
            d = os.path.join(ver_dir, "lib", "x64")
            if os.path.isdir(d):
                lib_dirs.append(d)
    return link_exe, lib_dirs


nasm = find_nasm()
if not nasm:
    print("error: nasm not found. Install it (winget install NASM.NASM) or add it to PATH.")
    Exit(2)

env = Environment(ENV=os.environ)
VariantDir(BUILD, SRC, duplicate=0)


# ---------------------------------------------------------------------------------
# Assemble: one object per unit. NASM include path points at src/ for nadir.inc.
# ---------------------------------------------------------------------------------
if target == "win64":
    obj_ext = ".obj"
    nasm_fmt = "win64"
    nasm_def = "-DWIN64"
else:
    obj_ext = ".o"
    nasm_fmt = "elf64"
    nasm_def = ""

all_units = list(CAPS)
for prog_units in PROGRAMS.values():
    for u in prog_units:
        if u not in all_units:
            all_units.append(u)

obj_of = {}
for unit in all_units:
    src = os.path.join(SRC, unit + ".asm")
    obj = os.path.join(BUILD, unit + obj_ext)
    # Every interpolated path is quoted, so space-bearing toolchain paths
    # (e.g. "Program Files") are shell-safe. `%s` on nasm_def is "" on linux.
    cmd = '"%s" -f %s %s -I"%s/" -o "$TARGET" "$SOURCE"' % (nasm, nasm_fmt, nasm_def, SRC)
    obj_of[unit] = env.Command(obj, src, cmd)[0]


def program_objs(prog):
    """The link set for one program: mandatory capabilities + its own units."""
    return [obj_of[u] for u in CAPS + PROGRAMS[prog]]


# ---------------------------------------------------------------------------------
# Link: the one place the two OSes diverge in tooling.
#   win64: MSVC link.exe, freestanding — /nodefaultlib, /entry:_start, kernel32.lib.
#   linux: ld, _start is the default entry, no libc.
# The win64 link block is deliberately isolated so GoLink (or lld-link) can be swapped
# in as a one-block change if MSVC is unavailable.
# ---------------------------------------------------------------------------------
if target == "win64":
    link_exe, lib_dirs = find_msvc_link()
    if not link_exe:
        print("error: MSVC link.exe not found. Install VS Build Tools with the")
        print("       'VC.Tools.x86.x64' workload, or swap the win64 link block for GoLink.")
        Exit(2)
    # Every path interpolated below is quoted, so space-bearing SDK/MSVC paths are safe.
    libpaths = " ".join('/LIBPATH:"%s"' % d for d in lib_dirs)
    programs = []
    for prog in PROGRAMS:
        out = os.path.join(BUILD, prog + ".exe")
        prog_objs = program_objs(prog)
        obj_args = " ".join('"%s"' % str(o) for o in prog_objs)
        link_cmd = (
            '"%s" /nologo /subsystem:console /entry:_start /nodefaultlib '
            '%s kernel32.lib /out:"$TARGET" %s'
        ) % (link_exe, libpaths, obj_args)
        programs.append(env.Command(out, prog_objs, link_cmd)[0])
    Default(programs)
else:
    # linux: link with ld if present (Manjaro/Deck); otherwise assembling the objs is
    # still useful as a syntax check and we skip the link step cleanly.
    from shutil import which
    ld = which("ld")
    if ld:
        programs = []
        for prog in PROGRAMS:
            out = os.path.join(BUILD, prog)
            prog_objs = program_objs(prog)
            obj_args = " ".join('"%s"' % str(o) for o in prog_objs)
            # -z noexecstack: nasm objects carry no .note.GNU-stack section; declare
            # the stack non-executable explicitly rather than let ld infer (and warn).
            link_cmd = '"%s" -z noexecstack -o "$TARGET" %s' % (ld, obj_args)
            programs.append(env.Command(out, prog_objs, link_cmd)[0])
        Default(programs)
    else:
        print("note: target=linux but no `ld` on this host — assembling ELF objects only")
        print("      (syntax check). Link on Manjaro/Deck where ld exists.")
        Default(list(obj_of.values()))
