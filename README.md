# Industrial Yard

Standalone Godot prototype for a two-player industrial-yard drop duel. PC first, Android later.

## Play

Open project.godot in Godot 4.7.2, let the assets import, and press F5. Main scene: battle.tscn.

- Practice: release the helicopter rope, deploy the parachute and explore. Practice has no storm damage.
- Shooting Practice: start on the ground with a rifle and moving, respawning training target that does not shoot back.
- Host/Join: direct two-player connection using the host address and UDP port 27845. Online invitations and automatic relay joining are not implemented.
- Modes: five-minute score match, first to ten eliminations, and practice.

## Controls

| Input | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift / Ctrl | Sprint / crouch |
| Space | Release rope, deploy parachute, jump on foot |
| Left / right mouse | Fire / aim |
| R / E | Reload / collect supplies, open cache or door |
| H / G | Heal / grenade |
| V | Camera switch; third person is default |
| B | Bring training target nearby in Practice |
| M / Tab | Expand map / release cursor |
| F8 / Esc | Control settings / menu |
| F5 | Host rematch after match ends |

The helicopter crosses the map with animated rotors and a swaying rope. Manual parachute deployment has a low-altitude automatic safeguard. The local minimap and expanded map show the yard. Touch controls and saved layouts are integrated, but physical Android testing remains outstanding.

## Status and limits

Unfinished prototype. Rifle combat, loot, armour, healing, grenades, safe zone, caches, respawns, training target and damage/airflow feedback are implemented. Some pickups still use temporary coloured geometry; final characters and sky animations need polish. Additional downloaded weapons are not all integrated. The planned throwable ice wall is not implemented.

Scripted full-round, drop-safety, training and same-computer two-process multiplayer checks have passed. This does not establish a complete manual two-computer match, reliable internet joining or phone performance. Real firearm recordings are connected; subjective sound approval remains open. Provisional sky audio is disabled by default.

Generated caches, logs, executable builds and test screenshots are excluded. Required source models and textures are included. The original Medieval Town and Rift Watch projects are not included.

## Third-party content

See THIRD-PARTY-CREDITS.md and licence/source records under audio/. Assets retain their respective creator licences. Some supplied model sources still need verification before public release; no blanket licence is granted for all repository contents.
