# Steam Frame deployment

## Pair the development PC

1. On Frame, enable **Settings → System → Developer Mode**.
2. Open **Settings → Developer → Pair new host**.
3. Run **SteamOS Devkit Client** on the PC, choose the Frame under Devkits and
   select Register. Confirm the pairing prompt in the headset.

This is Valve's documented flow. Use a trusted local network. See
[Valve's loading guide](https://partner.steamgames.com/doc/steamhardware/steamframe/loadgames).

## Upload the build

Build with `tools/Setup-FrameHome.ps1 -Templates -Build`, then in Devkit Client:

- Name: `FrameHome`
- Local directory: the absolute path to `build/frame`
- Start command: `./launch-framehome.sh`
- Runtime: **Steam Linux Runtime 3.0 ARM64 (Sniper)**

Keep the executable, PCK and license files together. Upload/register through the
client; the app should appear under the device's Non-Steam / Devkit games.
Launch it there to use the headset's OpenXR runtime.

For an already paired SSH host, `tools/Deploy-FrameHome.ps1 -Device frame`
can copy the build into `~/FrameHome`. `-IdentityFile` selects a paired key.
The host key must already be known to OpenSSH. This copy helper does not create
a Steam shortcut, start the app or configure the runtime. Prefer Devkit Client
for first installation; use SSH copying only when maintaining an existing setup.

## Initial device discovery, 2026-10-02

The development session resolved `frame` / `frame.local` to a private LAN address
and reached SSH on port 22. Login as `steamos` failed with
`Permission denied (publickey,password)`. No device files were uploaded, and no
headset application was started or closed. Pairing remains required.

## Game launch

FrameHome uses `steam://rungameid/<numeric-id>` for locally installed Steam apps.
After requesting launch it saves and exits, releasing its OpenXR session for
the selected game. Reopen FrameHome from the library to return. Successful URI
dispatch does not prove the selected game launched; validate this on device.

This build does not list remote PC-only installations or register streamed games.
Steam handles any platform compatibility of the selected locally installed game.

## User data

Default Linux path: `~/.local/share/godot/app_userdata/FrameHome/` (subject to
Steam runtime/XDG environment). Windows: `%APPDATA%/Godot/app_userdata/FrameHome/`.
The app writes `home.json`, `imports/` and `covers/` there. Export a `.framehome`
package through Room for a portable copy of the room and imported models.
