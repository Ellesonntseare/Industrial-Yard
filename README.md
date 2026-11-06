# Industrial Yard 0.2.1 playtest

Use the 0.2.1 build on both devices for multiplayer. The Android APK can update the earlier playtest in place. Hold FIRE to shoot at the weapon's normal rate and lift your finger to stop. You can move and aim while holding it.

Two-player industrial-yard drop duel for Windows and 64-bit Android. Choose your character, Practice to learn the drop, or Host/Join to play with a friend.

## Playing with a friend

Use the same current version on both devices. For the simplest connection, put both devices on the same Wi-Fi. One player chooses Host; the other enters the host computer or phone's local network IP address and chooses Join. The game uses UDP port 27845. Allow the Windows game through the firewall on your private home network if Windows asks. You can mix PC and Android players. Automatic internet relay, friend invitations and voice chat are not implemented; internet joining requires a reachable host and network configuration.

## Included

- Soldier, Cyborg, Android, Casual Man and Ninja, selected from real portraits and saved between sessions. New models are reduced to about 12,500 triangles each.
- Carbine, AK rifle, pistol, pump shotgun, MP5 SMG, SCAR battle rifle, SVD marksman rifle and combat knife. Weapons can be picked up, switched and dropped on death. Each magazine keeps its rounds when switching.
- Actual mesh pickups for weapons, ammunition, medical supplies, armour, backpack, grenades and C4.
- Keycard armory with alarm, furnished weapon displays and collectible rewards.
- Magnetic C4: green valid / red invalid surface preview, placement on reachable surfaces, arming blink and owner detonation. It follows moving doors and checks cover for blast damage.
- Ice walls deploy ahead and block bullets and movement for 22 seconds. Shooting Practice starts with three walls and three C4 charges. The training bot fires slow pistol shots, deals up to five damage per hit and stops at 20 health.
- Grenade physics and blast flash, dust and debris; confirmed hit effects and directional damage feedback.
- Recorded firearm reports and mechanisms, recorded rotor, wind, cloth and landing sounds. Explosion reports use real agricultural cannon recordings. Sound references and licences are retained.
- Third-person default, rope release, freefall, visible parachute stage and low-altitude automatic deployment. Push forward under the canopy to dive faster and release to return to the slower glide.
- Both players always appear on the map. Saved Android controls include Run above Move, weapon switch, C4 placement and detonation.

## PC controls

| Input | Action |
|---|---|
| WASD / mouse | Move / look |
| Shift / Ctrl | Run / crouch |
| Space | Release rope, deploy parachute, jump |
| Left / right mouse | Fire or knife attack / aim |
| R / E | Reload / collect, cache, keycard or door |
| Q / 1-8 | Switch weapon / select slot |
| C / F / X | Toggle C4 preview / place / detonate your charges |
| I | Deploy ice wall |
| H / G | Heal / throw grenade |
| V | Change camera |
| M / Tab | Expand map / release mouse |
| F8 / Esc | Controls / menu |
| B | Bring training target nearby in Practice |
| F5 | Host rematch after a match ends |

On Android, use the on-screen buttons. ICE deploys bullet-blocking cover. C4 first enables the preview and the next tap places it; BOOM detonates armed charges. Controls settings let you move buttons and adjust size, opacity and camera sensitivity.

## Install

Windows: extract the whole PC ZIP and open IndustrialYard.exe. Keep IndustrialYard.pck beside it.
Android: open Industrial-Yard-Android.apk on a 64-bit Android 7.0+ phone. Permit installation from the app used to open this file if Android asks. This is a debug-signed playtest APK, not a Play Store release.

## Verification and remaining limits

Scripted checks pass for the full round, flight, fall safety, ground movement, training combat, 48 new-content checks, mobile control events, and two simultaneous local host/client processes including confirmed damage and directional feedback. The exported PC pack also passes its startup/content check. APK package and signature verification pass. These checks do not establish physical-phone frame rate or a complete match between two separate physical devices. New automatic character skinning still need animation polish. Live overhead rendering can cost performance; the HD map fallback remains available.

## Source

Open project.godot in Godot 4.7.2. Android needs matching debug export templates, JDK 17 and Android SDK/build tools configured in the editor. The export preset currently points at the local debug template used for this build; replace that path on another computer.

See THIRD-PARTY-CREDITS.md and the source/licence files under assets/ and audio/. Content retains its original licence. The supplied map's original source still needs confirmation before a commercial release.
