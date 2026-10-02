# FrameHome notices

FrameHome application source, project models and modeling scripts are licensed
under GPL-3.0-or-later. See LICENSE. This is an independent community project.
Steam, Steam Frame and SteamOS are Valve trademarks; this project is not a Valve product.

## QuestHome origin

The furniture, tools and material assets originate in Kbloot/kblood's
[QuestHome](https://github.com/kblood/QuestHome). Their snapshot and individual
SHA-256 hashes are recorded in `assets/provenance.json`. The snapshot includes
local art work newer than the recorded upstream HEAD; it is deliberately copied
into this repository rather than depending on that checkout or its history.
The application has been recreated in GDScript for Godot/OpenXR and SteamOS.

## Engine

Godot Engine 4.6.1 is distributed under the MIT license. See `licenses/GODOT.txt`
and `licenses/GODOT-THIRD-PARTY.txt` in source, or the corresponding files beside
the exported executable. These include engine component notices, including Jolt.
Source: https://github.com/godotengine/godot/tree/4.6.1-stable

## Artwork and imports

Steam game artwork is retrieved into the user's local cache at runtime and is
not included in this repository. It belongs to the respective rights holders.
Importing a model does not change its license. Check rights before distributing
room packages containing third-party models.
