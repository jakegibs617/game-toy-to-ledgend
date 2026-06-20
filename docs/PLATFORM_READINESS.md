# Platform Readiness

Toy to Legend currently targets Godot 4.6+ and has been smoke-tested on
Windows with Godot 4.7 after the normal first-run import/cache pass.

## Current Desktop Targets

Supported development targets:

- macOS: original development platform.
- Windows: verified on June 20, 2026 with Godot 4.7 stable.

The project uses Godot-native paths (`res://` for project assets and
`user://` for saves/metrics), which is the right baseline for macOS and
Windows portability. Runtime code should continue to avoid absolute
platform paths such as `/Applications/...` or `C:\...`.

## Fresh Checkout Procedure

On a new machine, run one editor import/cache pass before relying on
headless tests. This rebuilds the global `class_name` cache and imports
GLB/font assets.

macOS:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --quit
SMOKE_TEST=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path .
```

Windows PowerShell:

```powershell
godot_console --headless --editor --path . --quit
$env:SMOKE_TEST = "1"; godot_console --headless --path .
```

Expected smoke-test result:

```text
SMOKE: OK
```

## Windows Verification Notes

Verified on June 20, 2026:

- Godot Engine 4.7 stable.
- First headless run without an import/cache pass failed on missing
  global script classes (`Player`, `PaintableWall`, `PatrolGuard`,
  `Hud`, etc.).
- Running `godot_console --headless --editor --path . --quit` rebuilt
  the global class cache and imported assets.
- The subsequent Windows headless smoke test completed with `SMOKE: OK`.

If the team wants clean-machine CI, the import/cache command should be
the first Godot step on every platform.

## Xbox Direction

Xbox is not just another desktop export. Godot console exports require
platform-holder approval and console-specific export templates or vendor
ports. The project should be prepared before that step:

- Keep game logic platform-neutral and data-driven.
- Treat controller as first-class input, not a secondary fallback.
- Avoid mouse-only modal flows.
- Keep save data in `user://` and test save/load under exported builds.
- Track performance budgets for CPU, GPU, memory, draw calls, and load
  times.
- Avoid runtime features that depend on local HTTP servers, shells, or
  desktop-only windows in the retail game path.

## Phone Direction

Mobile is feasible, but it is a design and UI target, not just an export
checkbox. Before committing to phone, plan for:

- Touch controls for movement, camera, interaction, painting, menus, and
  freehand drawing.
- Smaller-screen HUD layouts and modal text density.
- Performance tiers for lower-memory devices.
- Texture/mesh budgets and loading behavior.
- Battery/thermal testing.
- Save-path and permission behavior on Android/iOS.

The current keyboard, mouse, and controller bindings are a good desktop
base. Mobile should get a dedicated input layer instead of overloading
the desktop HUD.
