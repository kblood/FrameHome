# Platform decision — 2026-10-02

## Native OpenXR application

Valve supports stock Godot/OpenXR on Steam Frame as Android or Linux ARM64.
Its guide recommends Godot 4.6 beta 1 or newer for Frame controller bindings.
We pin stable 4.6.1 and export Linux ARM64, allowing local Steam-library access
without depending on Horizon OS services.
[Godot integration](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot)

The new application uses Godot's Mobile renderer, Jolt, authored simple physics
shapes and the portable models from QuestHome. Meta Spatial SDK/Kotlin UI and
Android package enumeration cannot be reused directly, so those components have
been recreated. A separate Git history makes development and licensing traceable.

## Input

The action map explicitly binds `/interaction_profiles/valve/frame_controller_valve`.
Valve documents grip/aim poses, squeeze, trigger, thumbstick and face-button
paths. Default Touch and other Godot profiles remain available for PC VR.
[Frame input](https://partner.steamgames.com/doc/steamhardware/steamframe/input)

Input ownership is implemented per operation: left locomotion and right turning
are read independently in the same physics frame. Grabbing consumes right-stick
manipulation, leaving left walking intact. Explicit UI scrolling requires stick
click. Focus loss clears held actions and requires grip/trigger neutral input.

## Delivery

Devkit Client pairs a host and uploads a local build. Valve documents the ARM64
Sniper runtime for this target. The deployment helper copies application files
only; device registration and runtime choice belong to Devkit Client.
[Loading games](https://partner.steamgames.com/doc/steamhardware/steamframe/loadgames)

SSH uses `steamos` and the documented `frame` hostname. Discovery succeeded;
authentication has not. Hardware validation must wait for pairing.
[Debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging)

## Deliberate limits of this first port

No Steam Home system replacement, Steamworks SDK dependency, cloud synchronization,
automatic return from another VR app, remote-PC library discovery or built-in mesh
decimation. Locally installed titles are read from Steam manifests and launched
using the Steam protocol. Cover downloads are best effort, with local caching.

Performance targets need measurements on Frame. Model reuse, capped projectiles,
simple collision shapes and a mobile renderer reduce costs, but do not establish
that the app meets the headset's frame budget.
