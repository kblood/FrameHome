# Port status

Initial implementation, 2026-10-02. This file distinguishes build results from
actual headset behavior. No automated tests or interactive runtime checks have
been run for this task. Device authentication is pending.

## Build evidence

`tools/Setup-FrameHome.ps1 -Templates -Build` completed successfully with official
Godot 4.6.1. Downloaded editor and template archives matched pinned SHA-512 hashes.
All model imports and GDScript compilation completed without reported errors.
Both Linux ARM64 and Windows x86-64 release exports completed. The initial Frame
directory is approximately 71 MB, including its engine, PCK and notices. Build
logs remain in ignored `.tools/asset-import.log` and `build/export-*.log`.

These results establish buildability, not working interaction on a headset.

| Area | Implemented | Still needs device validation / limitation |
| --- | --- | --- |
| Room/models | Fifty GLBs, furnished starting room, Jolt bodies, masses, pinning | Appearance, lighting, contact stability and frame budget |
| Locomotion | Head-relative walk, simultaneous turn, smooth/snap and teleport | Direction, tracking, comfort and focus transitions |
| Grabbing | Near/ray grabs, controller-relative distance, authored hand poses | Physical bow/sword/controller alignment and reach |
| Grip authoring | Generic model selection, per-hand points, manual values, pose capture | Ergonomics on Frame; no automatic polygon reduction |
| UI | Ray click, explicit scrolling, search keyboard, movable/rotatable/resizable windows | Legibility, pointer behavior, embedded file dialog |
| Wall mounting | Front faces into room; pull away to detach | Reach and orientation at every wall |
| Steam | Local manifests, search, tool filtering, cover cache/download, URI launch | Device paths, artwork availability, launching and reopening |
| Cartridges | Covers/titles, console slot, monitor, virtual headset launch | Surface alignment and contacts with table/console |
| Bookshelf | Existing shelf shape, configuration button, twenty fixed slots | Slot/label orientation and stability while moving shelf |
| Toys | Bow draw/shoot/stick, paint colors/splats, inflate/float/pop balloons | Two-hand input, aim, sticking and practical performance |
| Persistence | Autosave, twenty undo snapshots, `.framehome` packages | Restart and importing on device; no `.qhome` conversion |
| Desktop | Mouse/keyboard navigation, grabs, UI and authoring | Separate from proof of headset behavior |

## Physics design

Room surfaces use collision layer 1, props layer 2, UI ray surfaces layer 4 and
balloons layer 8. Player movement collides with the room but deliberately passes
through furniture to avoid snagging. Props collide with the room and other props.
Windows have no physical collision mask and do not affect furniture.

Masses in kilograms include table 10, console 1.5, monitor 3, cartridge 0.15,
sword 1, bow 0.6 and arrow 0.025. A held prop is frozen with collisions disabled;
release checks overlap before restoring dynamic collision. The last clear pose
is retained as a fallback. Tables and shelves use compound shapes. Other props
mostly use boxes; imported models do not yet offer collision-shape authoring.

Arrows, paint and balloons use bounded swept queries/cosmetic attachment, not
large rigid-body stacks. UI is excluded. Cosmetic effects are not saved in room
packages. Pinned bookshelf cartridges follow the shelf; taking one removes its
assignment. The virtual headset is a console accessory visible after insertion.

## First paired-device session

Pending, not performed: launch with the ARM64 runtime; check both sticks together;
grab/reel/attach/release each tool; exercise suspend/resume; stack and insert
cartridges; inspect monitor and labels; open/close import; place and rotate wall
panels; author left/right grips; launch a Steam game and reopen FrameHome.
Measure CPU/GPU frame times and memory after repeated interactions. Record actual
observations before declaring headset feature parity.
