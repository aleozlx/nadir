# nadir GUI design

*An assembly-friendly GUI/tooling layer for nadir, preserving asm as canonical while
using a deliberately small C ABI waist for cross-platform interactive tools.*

Status: draft v0.1 · companion to `DESIGN-nadir.md`

---

## 1. Thesis

`DESIGN-nadir.md` treats GUI as the hard case because Windows and Linux do not share a
mechanism:

- Win32 is a call-based OS GUI API: windows, messages, callbacks, GDI, controls.
- Linux desktop GUI is a stack: Wayland/X11 protocol, compositor/window manager,
  toolkit, renderer, fonts, input, clipboard, packaging.

The original M2 goal, `open-window`, is still a good proof of the OS seam. But a blank
window does not help write assembly programs. nadir needs a second GUI track:

1. **Primitive GUI capability** for proving the seam remains honest.
2. **Tool GUI layer** for building useful assembly workbenches without turning nadir into
   GTK, Qt, libc, or a browser.

The proposed tool layer is:

```
nadir asm program
  -> tiny stable C ABI wrapper
    -> Dear ImGui
      -> backend row selected per target
```

This keeps the asm-facing API finite and mechanical while delegating fonts, input,
rendering, docking, widgets, DPI, and platform windows to a mature immediate-mode UI
library.

The claim: **Dear ImGui behind a narrow C ABI is the closest practical cross-platform
analog to Win32's assembly-friendliness**, not because it mimics native controls, but
because its programming model is "call functions every frame and read return values."
That maps cleanly to assembly.

---

## 2. Why Win32 feels friendly to asm

Win32 is not "assembly-native"; it is a C API. But a C API is close enough to assembly:

- exported DLL functions
- integer and pointer arguments
- structs with fixed layouts
- handles
- callbacks
- message IDs
- no required C runtime for small freestanding programs

A tiny NASM GUI can enter at its own PE entry point, reserve Win64 shadow space, call
`user32`/`gdi32`/`kernel32`, and exit via `ExitProcess`. The C runtime is optional
because the OS GUI API is already the public ABI surface.

This is not true of most Linux GUI programming. Linux syscalls are friendly to raw asm,
but the desktop ecosystem assumes shared libraries and libc:

```
GTK/Qt/SDL/GLFW/libwayland-client/libvulkan/libEGL
  -> libc and dynamic loader ecosystem
```

Raw Wayland can avoid libc only if nadir speaks the protocol itself over Unix sockets
and implements the buffer/event machinery directly. That is possible, but it is closer
to writing a mini toolkit than calling Win32.

---

## 3. Linux GUI layers, honestly placed

Wayland is not the Linux equivalent of Win32. It is narrower:

| Linux-side layer | Windows-side rough analog / role |
|---|---|
| Linux syscalls | `kernel32`/`ntdll` territory |
| Wayland/X11 protocol | part of the `user32`/DWM/window-manager boundary |
| GTK/Qt | standard controls, toolkit, app framework |
| Dear ImGui + backend | custom-rendered tool UI layer |

Wayland gives surfaces, buffers, input events, outputs, and protocol extensions. It does
not give buttons, menus, text boxes, GDI-style text drawing, standard file dialogs, or an
application framework.

GTK is attractive for a Linux-native wrapper because it is C ABI-first and LGPL, but it
brings GObject, signals, ownership rules, libc, and toolkit conventions. Qt is powerful
and portable, but the primary API is C++ and the licensing/module story is heavier.

Dear ImGui is not a native desktop toolkit. It is a custom-rendered immediate-mode UI
library. That limitation is also the opportunity: assembly does not need to manage a
retained object graph. It emits the UI each frame.

---

## 4. Two GUI tracks

### 4.1 `open-window` remains the seam proof

The original M2 proof should stay small:

| capability | win64 row | linux row |
|---|---|---|
| `open-window` | `RegisterClassExA` + `CreateWindowExA` | raw X11 over XWayland, or raw Wayland later |
| `blit` | GDI / DIB section | X11 `PutImage`, Wayland shm buffer, or explicit deferred row |
| `close-window` | `DestroyWindow` / `PostQuitMessage` | protocol close/disconnect |

This track answers: "Where does the OS seam actually live?" It is not expected to become
the main UI for nadir tools.

### 4.2 `nadir_ig` — nadir's Dear ImGui binding — becomes the usable tool layer

The tool layer exists for assembly workbenches:

- register views
- memory viewers
- disassembly views
- intent-map inspection
- test/instrumentation dashboards
- capability table viewers
- build/test controls
- trace/event logs

The asm-facing surface is a C ABI with plain integers, pointers, lengths, and callback
addresses. No templates, no C++ name mangling, no GObject, no varargs, no retained widget
handles unless a real tool forces them.

```
asm tool
  calls nadir_ig_* functions
nadir_ig.dll / libnadir_ig.so
  owns Dear ImGui context and backend
backend row
  win64: Win32 + D3D11, or Win32 + OpenGL
  linux: SDL2/SDL3 + OpenGL/Vulkan, GLFW + OpenGL/Vulkan, or Wayland/X11 backend
```

The first backend should be boring rather than pure. Boring is how the tool gets written.

---

## 5. The C ABI waist

The wrapper is a capability table for GUI tools, not a binding of all Dear ImGui.

**Naming.** In prose this layer is **nadir's Dear ImGui binding** (or wrapper); the
exported prefix is `nadir_ig_` — `nadir` claims the namespace outright, `ig` nods to
cimgui's established convention for C bindings of Dear ImGui. The prefix untangles from
legitimate ImGui symbols by construction: Dear ImGui core is C++ (all symbols
namespace-mangled), cimgui exports `ig*`, the official backends export `ImGui_Impl*`,
and none of them can claim a `nadir_`-prefixed C symbol. The artifact names
(`nadir_ig.dll`/`libnadir_ig.so`) are equally unambiguous next to the
`imgui.lib`/`libimgui.a` that vcpkg and distro packages ship for Dear ImGui itself —
the wrapper links Dear ImGui statically inside itself, so the upstream name never
appears on a nadir tool's link line.

G0 surface (M0/M1 are spent milestone names in the main roadmap; wrapper tiers are
named for the G-track steps that introduce them):

```c
int  nadir_ig_init(const char *title, int width, int height);
int  nadir_ig_begin_frame(void);
void nadir_ig_end_frame(void);
void nadir_ig_shutdown(void);

void nadir_ig_text(const char *text);
int  nadir_ig_button(const char *label);
```

(This is the six-function spike §10's G0 builds; the interaction primitives below —
`same_line`, `input_text`, `slider_i32` — arrive with the G2 workbench surface.)

G2 surface:

```c
int  nadir_ig_window_begin(const char *title, int *open);
void nadir_ig_window_end(void);
void nadir_ig_separator(void);
void nadir_ig_same_line(void);
int  nadir_ig_input_text(const char *label, char *buf, int buf_size);
int  nadir_ig_slider_i32(const char *label, int *value, int min, int max);
void nadir_ig_hex_u64(const char *label, unsigned long long value);
void nadir_ig_table_registers(const unsigned long long *regs, int count);
void nadir_ig_memory_view(const void *base, unsigned long long addr, int len);
```

Assembly call shape (win64 shown — `nadir_ig_*` is a plain C ABI, so calling it is a
*target-ABI* call with the full Win64 duties: shadow space and 16-byte alignment at
every call, per [asm-debugging-guide.md](asm-debugging-guide.md)):

```nasm
    sub rsp, 40                 ; 32B shadow space + 8 to realign, once for the loop

.frame:
    call nadir_ig_begin_frame
    test eax, eax
    jz .quit

    lea rcx, [rel hello]        ; win64 arg1; sysv passes rdi
    call nadir_ig_text

    lea rcx, [rel button]
    call nadir_ig_button
    test eax, eax
    jz .not_clicked
    ; handle click
.not_clicked:

    call nadir_ig_end_frame
    jmp .frame
```

This is intentionally closer to Win32's "message IDs and return values" than to GTK's
objects/signals or Qt's C++ object model.

**Convention seam, same rule as always.** A tool written in the nadir convention
(`DESIGN-nadir.md` §2.2) reaches `nadir_ig_*` the way portable code reaches any OS
facility: through a thin per-target seam that owns the marshalling. The asymmetry is
the familiar one — SysV C args are `rdi/rsi/rdx/rcx`, identical to the nadir convention
for the first four args, so the linux thunk is near-zero; the win64 thunk remaps to
`rcx/rdx/r8/r9` and homes shadow space, exactly as `cap_*` bodies already do. A tool may
instead be written directly against the target ABI (as above) and forgo the portable
stratum — legitimate for a single-target workbench, but then it is target code, not
nadir-convention code, and should say so.

---

## 6. Event model

Do not force a synthetic retained event system in G0.

Dear ImGui already provides the right inversion:

```
while running:
  begin frame
  emit widgets
  read immediate return values
  end frame
```

For assembly, this is simpler than callbacks:

- button click returns `1`
- checkbox mutates an integer/bool
- input writes into a caller-owned buffer
- selection returns an index

Callbacks are allowed only where unavoidable, such as host notifications or long-running
debugger events. The default is polling by return value because it keeps control flow in
the asm source.

---

## 7. Runtime and purity boundary

The `nadir_ig` wrapper is not freestanding nadir. It is a host tool layer.

That boundary must be explicit:

- Core nadir programs may remain CRT/libc-free.
- `nadir_ig` may link to Dear ImGui, a renderer backend, platform libraries, libc on Linux,
  and Windows import libraries on Windows.
- The wrapper itself is not part of the portable freestanding capability waist.
- The asm-facing ABI is part of nadir's tooling convention.

This preserves the original thesis: nadir owns its finite substrate, while tools may use
host affordances through a narrow adapter.

The concrete cost differs by target. On win64, importing from `nadir_ig.dll` is the same
PE import mechanism core nadir already uses for `kernel32` — no new machinery. On linux,
linking `libnadir_ig.so` brings in the dynamic loader, which core nadir binaries (static,
raw-syscall) have never touched. That asymmetry is the host-tool boundary made concrete:
a `nadir_ig` tool on linux is a host program by construction, not merely by policy.

The danger is waist creep by convenience. The wrapper must not become "all of ImGui."
Every exported function earns its place by a real assembly-tool need.

---

## 8. Backend choices

### 8.1 Win64

Preferred first row:

```
Win32 window + Dear ImGui + Direct3D 11
```

Why:

- stable and common Dear ImGui backend
- no CRT required for the asm caller
- C++ wrapper can absorb COM setup
- good enough for tools

Alternative:

```
Win32 window + Dear ImGui + OpenGL
```

This may be simpler conceptually, but modern WGL setup is its own historical cave.

### 8.2 Linux

Preferred first row:

```
SDL + Dear ImGui + OpenGL
```

or:

```
GLFW + Dear ImGui + OpenGL
```

Why:

- small enough
- proven Dear ImGui examples exist
- works across X11/Wayland depending on backend/platform support
- keeps raw Wayland out of the first useful tool

GTK is not the first `nadir_ig` backend because Dear ImGui already supplies widgets and
interaction. GTK remains a candidate for a separate native app wrapper if nadir later
needs OS-native dialogs, accessibility, or GNOME integration.

### 8.3 Raw Wayland

Raw Wayland is a research/backend row, not G0/G1:

```
syscalls -> Wayland socket -> wl_registry -> wl_compositor -> wl_shm
         -> xdg-shell -> shm buffers -> frame callbacks
```

It proves purity, but it delays the tool. Keep it as a later "can nadir own the full
Linux GUI primitive?" experiment.

---

## 9. Relationship to intent-map

The GUI tool layer should make intent visible without moving intent into comments.

Candidate views:

- source label list
- selected label's intent-map record
- capability references by label
- ABI role overlay (`arg1`, `shadow-space`, callee-saved)
- testability sentinels (`@ret`, `@end`)
- build target matrix
- behavioral test results by capability and target

The GUI is another projection over canonical asm and out-of-band metadata. It must not
become the source of truth.

---

## 10. Roadmap

The G-track is parallel to the main roadmap's M-track (`DESIGN-nadir.md` §7) and gates
nothing there: **M2 (`open-window`) remains the next milestone** and proceeds
independently. G5 revisits the M2 artifact for comparison; it does not defer or replace
it.

1. **G0 - C ABI spike.** Build `nadir_ig_init`, `begin_frame`, `text`, `button`,
   `end_frame`, `shutdown`. One NASM demo calls the wrapper and increments a counter.
2. **G1 - backend pair.** Win64 + D3D11 and Linux + SDL/OpenGL expose the same wrapper
   exports. Same asm-facing demo on both.
3. **G2 - assembly workbench primitives.** Add hex display, memory view, register table,
   log pane, and simple input buffer.
4. **G3 - intent-map browser.** Load `nadir.intent.db` or exported markdown/JSON and show
   label-to-intent projections beside source snippets.
5. **G4 - test dashboard.** Run existing behavioral tests externally and visualize
   capability/target status. The GUI may spawn the build/test command, but it does not
   replace `nadir test`.
6. **G5 - raw GUI seam proof.** Preserve original M2 `open-window` route as a separate
   artifact: Win32 direct vs X11/Wayland primitive. Compare what the tool layer hides.

---

## 11. Risks

- **Wrapper creep.** Exporting too much Dear ImGui recreates a large toolkit ABI. Keep the
  C surface tool-shaped and pull-based.
- **Backend lock-in.** D3D11/SDL/OpenGL are implementation rows, not concepts. The asm
  ABI must not leak backend handles in G0.
- **Native integration gap.** Dear ImGui is excellent for tools, weak for native desktop
  app conventions. That is acceptable for nadir's first GUI target.
- **Accessibility gap.** Custom-rendered UI is less accessible than native widgets. If
  nadir becomes more than a developer workbench, GTK/Qt/Avalonia may need a separate
  front-end track.
- **Linux packaging complexity.** SDL/OpenGL/Vulkan and graphics drivers vary by distro.
  Keep the first Linux target to Manjaro desktop mode and document package assumptions.
- **Purity confusion.** The `nadir_ig` wrapper is not proof that nadir's core is
  freestanding. It is a host tool adapter. Say that every time.

---

## Appendix - comparison table

| Candidate | Assembly friendliness | Cross-platform | Native look | libc/CRT coupling | Fit for nadir |
|---|---:|---:|---:|---:|---|
| Raw Win32 | high | Windows only | native | CRT optional | excellent seam row |
| Raw X11 | medium | Linux/BSD-ish | no toolkit | libc avoidable if raw socket | useful proof row |
| Raw Wayland | low initially | Linux/BSD-ish | no toolkit | libc avoidable if raw protocol | later research row |
| GTK | medium via C wrapper | mostly Linux-first | GNOME-native | libc expected | good native wrapper candidate |
| Qt | low direct, medium via wrapper | strong | KDE/native-ish | libc expected on Linux | powerful, heavier license/API |
| WPF/WinUI/Avalonia | low direct | varies | good | managed (WPF/Avalonia); native C++/WinRT for WinUI 3 | useful analogy, not nadir core |
| Dear ImGui | high via C wrapper | strong | custom tool UI | backend-dependent | best first tool layer |

