# Tactical item models

- `carbine.glb`, `pistol.glb`, `shotgun.glb` are adaptations of LE6920, Glock 27 and R870 from the user's **Low Quality Weapon Pack** download. Its included BlendSwap license identifies blend 88429 and releases the pack as CC0. Source https://www.blendswap.com/blend/88429 . Original license is preserved in `WEAPON-PACK-LICENSE.html`. Changes include scale normalization, isolated exports and plain gunmetal material.
- `ak47.glb` uses the user's prepared AK-74 mesh, originally **AK-74 Pack (game asset)** by **Armored Wave**, CC-BY-4.0. Source https://sketchfab.com/3d-models/ak-74-pack-game-asset-29978f495f824173b44a3ba40cb8ebd8 . Reduced geometry, normalized scale and simplified wood/metal finishes. The catalog's compatibility ID is `ak47`; the display name is deliberately generic because the actual source is an AK-74.
- `medkit.glb` is derived from the user's `tactical_first_aid_kit.glb` download. Source attribution is recorded in `medical-source.json`, copied from original GLB metadata. Reduced geometry and texture resolution to 512px.
- `armor.glb` is a reduced derivative of `assets/provided/modern_tactical_vest__plate_carrier.glb`; its original source/author/license are recorded in `armor-source.json` from embedded metadata, and in the project's third-party credits.
- `knife.glb`, `backpack.glb` and `c4.glb` were authored for this project from mesh primitives with rounded geometry, separate material regions, and appropriately shaped components. These are reusable mesh assets, with no downloaded source material.

Kenney ammunition magazine and grenade source files and CC0 license remain in `assets/items/kenney`.

`smg.glb`, `battle_rifle.glb`, and `marksman.glb` are the MP5A4, Scar-H, and SVDs meshes from the same CC0 BlendSwap pack. The models were isolated, scaled and given a simple gunmetal material.
