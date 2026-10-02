# Steam Frame device checks — 2026-10-02

## Device and deployment

SteamOS VR 0.3.0, build 20260922.6101926, Linux aarch64. SteamVR/OpenXR 2.17.10,
Godot 4.6.1, Vulkan Mobile renderer, Turnip Adreno 750. Developer-mode SSH login
was authorized by the user; the password was used in memory and was not saved
in source, logs or scripts.

Uploaded the native build to `/home/steamos/FrameHome`. Added a **FrameHome**
Non-Steam VR shortcut through the running Steam client. Local shortcut app ID
2756258923; game ID 11838041933626736640. Steam successfully launched the ordinary
app (without diagnostic flags), which initialized OpenXR and remained running
at the end of this task. This does not replace the system Home application.

## Automated checks performed on the headset

Final run began at 10:20:45 UTC and completed **20/20 checks**:

1. OpenXR initialized on the actual device.
2. Steam catalog contained 16 installed applications (including hidden tools).
3. Original furniture remained still during a two-second post-settle sample.
4. A dropped cartridge rested on the table: bottom 0.741949 m, tabletop 0.741998 m.
5. Cartridge insertion caused no measured displacement or velocity in the
   two-second post-settle sample.
6. The shelf configuration callback enabled placement and assigned a real app.
7. Synthetic right-stick pull attached the cartridge's grip to the controller
   transform, with measured grip-position error 0 m.
8. Synthetic push detached it and moved it away.
9. Synthetic walk and turn in the same frame produced both movement (0.013889 m)
   and the expected turn direction (-0.017778 radians).
10. Windows faced into the room at all four walls.
11. UI collision layers/masks excluded physical interactions with props.
12. Pulling a window into open space cleared its wall attachment.
13. Resizing changed its actual dimensions.
14. Search filtered the game list.
15. Model selection opened a non-native, embedded file dialog.
16. Importing a GLB produced a private, usable model package.
17. A swept arrow hit and stuck in a wall.
18. A paintball hit a surface and created a mark.
19. A released balloon floated upward.
20. A balloon could be popped and removed.

The tests call the real application operations with synthetic poses/input and
run the real physics/rendering world on the device. They do **not** constitute
manual trigger/grip/thumbstick testing: both controller tracking flags were
false throughout the recorded test startup. The room document is restored after
the run; temporary imported model data and captures stay outside Git.

## Visual review

Reviewed the actual headset application's desktop mirror plus offscreen views
rendered by its GPU: furnished room, monitor and console, cartridge artwork,
bookshelf slot/configuration icon and embedded file dialog. Labels were readable
in their texture captures, monitor content remained inside the display, and the
cartridge was above the tabletop. Artwork fitted without stretching; some Steam
apps only had landscape art, which is letterboxed. Hand/controller alignment and
stereo comfort still require wearing the headset.

The later Steam-launched X11 mirror capture was black. At that time the headset
log reported `Set displays off` and `StateStandby`; the app remained running and
the compositor recorded submissions. Visibility after waking/wearing the headset
has not been confirmed. The earlier direct-launch mirror and diagnostic GPU
captures did show the room, and are retained separately.

## Corrections from the session

- Check for fixture metadata before reading it when restoring/removing props;
  normal windows have no fixture metadata.
- Use the documented OpenXR focus signal and exit cleanly on instance loss/exit.
  Window-system focus now only controls desktop mode.
- Keep locomotion and manipulation calculations callable separately from
  physical input collection, allowing repeatable checks of the same logic.
- Hide FEX, Lepton and Proton tools from the ordinary game list.
- Disable shadows cast by floating UI surfaces and handles.
- Run editor import before export; fix a diagnostic-hook script type error that
  an export-only build had not caught.

One early run was interrupted when another VR application took the scene session.
SteamVR then killed FrameHome after its exit timeout. The exit signal handling
above was added; later diagnostic runs completed and exited normally.

## Performance and remaining limits

A later Steam-launched compositor snapshot recorded 6,707 submitted frames,
average application CPU time 1.52 ms and GPU time 3.30 ms, with 2 dropped and 9
reprojected frames. These are cumulative observations in the current device
state, **not** a sustained performance certification with the headset worn.
The diagnostic run reported 50 FPS at its final sample while also doing captures.

The Steam-launched normal application log contained no script errors. It did
report that disabling VSync was unavailable and fell back to enabled VSync.
Some direct diagnostic runs also logged an OpenXR creation retry and engine
shutdown messages about a spatial-extension signal/interaction-profile RIDs;
they subsequently initialized XR and completed. These remain engine/runtime
compatibility observations to investigate during worn-device performance work.

Still unverified: physical controller bindings and ergonomics, two-hand bow draw,
focus/suspend/resume while worn, launching another game through the virtual
headset, and sustained frame rate. No unrelated game was deliberately closed.

## Reproduce and locate evidence

Build using `tools/Build-FrameHome.ps1 -Target Frame`. Copy
`assets/furniture/sword.glb` to `~/FrameHome/qa/import-fixture.glb` on the device,
then run the app with:

```sh
./FrameHome.arm64 -- --device-check --evidence-dir=/home/steamos/FrameHome/qa
```

This opt-in test changes temporary scene objects, restores the prior room, writes
`report.json` plus PNG captures, then exits. Run it while the headset is available
for testing. Ordinary startup does not run diagnostics.

Local evidence is retained in ignored `captures/2026-10-02-frame/`; the final
results are `final-report.json` and `final-device-check-4.log`. The directory's
`manifest.json` records artifact hashes. Generated captures/runtime data are not
committed. The source harness is `qa/device_check.gd`.

Deployed PCK SHA-256:
`2455e70a22fe3f231d02d0817eed179609c8312b47f2766b5975798886ad8af6`.
