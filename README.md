# FrameHome

A personal Steam library room for **Steam Frame**, recreated from QuestHome as
an independent **Godot 4.6.1 / OpenXR / Jolt** application. Native Linux ARM64 is
the headset target; a Windows build provides a desktop authoring view.

**Initial port, now exercised on Steam Frame.** Twenty automated integration
checks passed on the device, with rendered captures reviewed. Physical controller
ergonomics, sustained performance while worn and game handoff still need manual
validation. See [device report](docs/DEVICE_CHECK_2026-10-02.md) and
[port status](docs/PORT_STATUS.md).

## Features

- Search installed Steam games and apps, hide common background tools, open a
  game directly or make a cartridge. Local cover art is preferred; public Steam
  artwork is downloaded when needed. Names remain visible without artwork.
- A furnished room with movable physical objects, pinning, saving and undo.
  Table, monitor, console, shelves, sword, bow and additional furniture are GLBs.
- Console cartridge slot, a cover/title monitor and a virtual headset used to
  launch the selected game. Twenty fixed bookshelf cartridge positions and a
  small configuration button on the shelf.
- Simultaneous headset-relative walking and turning, with smooth/snap turn and
  walk/teleport settings. Controller-relative distance grabs and hand attachment.
- Movable windows, stick rotation, wall attachment facing into the room and
  grab-to-resize corners. UI does not collide with furniture.
- In-app GLB/glTF import, a generic grip editor for built-in and imported models,
  left/right grip points, pose capture, imported model size and alternate meshes.
- A drawable bow with arrows that stick to room surfaces and move with hit
  objects, a paintball gun, and an inflator making colored floating balloons.
  Arrows and paintballs can pop balloons. Effects have bounded lifetimes/counts.
- Portable `.framehome` room packages containing settings and imported models.

## Set up on Windows

Run from this checkout in PowerShell:

```powershell
.\tools\Setup-FrameHome.ps1 -Templates -Build
```

This downloads official Godot 4.6.1 archives, verifies pinned SHA-512 checksums,
imports assets and exports both targets. The export-template download is about
1.25 GB; it stays in ignored `.tools/`. No Steamworks SDK, Meta SDK, API key,
Blender installation or copy of QuestHome is needed to build.

```powershell
# Open the project for editing
.\.tools\godot\Godot_v4.6.1-stable_win64.exe --editor --path .
# Rebuild either target
.\tools\Build-FrameHome.ps1 -Target Frame
.\tools\Build-FrameHome.ps1 -Target Windows
# Desktop mode without initializing the PC's VR runtime
.\build\windows\FrameHome.exe --xr-mode off -- --desktop
```

For a custom Steam installation, set `FRAMEHOME_STEAM_ROOT` to its directory
(the directory containing `steamapps`). Additional Steam libraries are read
from `libraryfolders.vdf`. Only games installed on the machine running FrameHome
are listed. Remote PC library discovery/streaming is not implemented.

## Install on Steam Frame

Follow [deployment instructions](docs/DEPLOYMENT.md). The prepared directory is
`build/frame`; select **Steam Linux Runtime 3.0 ARM64 (Sniper)** in SteamOS Devkit
Client. FrameHome runs as a separate library app. System Home replacement and
automatic startup are not configured.

## Controls

| Input | Action |
| --- | --- |
| Left stick | Walk relative to your headset, or aim/release teleport |
| Right stick | Smooth/snap turn while hands are free |
| Grip | Grab a nearby handhold or an object/window under the ray |
| Right stick up/down while holding | Push away / pull toward the controller; handheld objects attach at their grip |
| Right stick left/right while holding a window | Rotate the window |
| Grip a window's green corner | Resize by moving your hand |
| Trigger over UI | Click; drag a scrollbar to scroll |
| Hold stick click over UI + stick up/down | Scroll explicitly; that stick pauses locomotion |
| A on right / D-pad down on left | Change the held toy's color |
| Trigger with paintball gun | Fire |
| Trigger with inflator | Inflate; release to let the balloon float |
| Other hand's trigger near bow string | Hold, draw back and release an arrow |

If both hands hold objects, the right stick adjusts the right-hand object.
Walking remains available during grabs. Controller focus loss releases grabs;
grip/trigger must return to neutral before they reactivate.

Desktop: hold right mouse to look, WASD to walk and Q/E to turn. Left mouse
clicks UI; G grabs/drops; wheel changes held distance or scrolls UI. Esc releases
the mouse. Two-handed archery requires tracked controllers.

## Models and grip editing

In **Room**, add built-ins or choose **Import GLB / glTF**. Import packages external
buffers/textures into a private GLB. Select any object in Room, then open
**Grip editor**. Set whether it attaches to the hand; add grip points and edit
their position/orientation, or capture a tracked controller pose after a 3-second
delay. Changes apply the next time you grab that model.

Imported models have a default longest-side size and can use another imported,
pre-optimized mesh. Automatic polygon reduction is not implemented. Custom meshes
currently use a box collider. Blender generation scripts for the newest toys and
model variants are in `tools`; their output goes to ignored `build/`. Original
GLBs are already included and remain independently importable.

## Files and license

- `scripts/`: application, controllers, physics, UI, Steam catalog and toys.
- `assets/`: 50 portable GLBs, source provenance; about 8.5 MB of model data.
- `openxr_action_map.tres`: Frame profile plus fallback controller profiles.
- `tools/`: setup, export, deployment and Blender model generation.
- `docs/`: research, deployment and outstanding device validation.
- `.tools/`, `.godot/`, `build/`, `captures/`: ignored generated files.

Godot's extracted `assets/furniture/*_basecolor.png` textures are also ignored;
their pixels are embedded in the committed GLBs and regenerated during import.

Godot stores layouts, imports and downloaded covers in its per-user FrameHome
application-data directory, outside the checkout. `.framehome` is a new format;
QuestHome `.qhome` files are not directly compatible.

GPL-3.0-or-later; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
