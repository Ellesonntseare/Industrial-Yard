extends RefCounted

const WeaponsCatalog = preload("res://weapons_catalog.gd")
const ITEM_MODELS := {
	1: "res://assets/items/kenney/clip-large.glb",
	2: "res://assets/items/tactical/medkit.glb",
	3: "res://assets/items/tactical/armor.glb",
	4: "res://assets/items/kenney/grenade-a.glb",
	5: "res://assets/items/tactical/backpack.glb",
	6: "res://assets/items/tactical/c4.glb",
}
const ITEM_SIZES := {1: 0.24, 2: 0.3, 3: 0.6, 4: 0.2, 5: 0.5, 6: 0.3}

static func create_loot(kind: int, weapon_id: String = "carbine") -> Node3D:
	var root := Node3D.new()
	root.name = "LootModel"
	root.set_meta("kind", kind)
	root.set_meta("weapon_id", weapon_id)
	var model: Node3D
	if kind == 7:
		var pickup := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(.45, .58, .29)
		var frost := StandardMaterial3D.new()
		frost.albedo_color = Color("8fe9ff")
		frost.emission_enabled = true
		frost.emission = Color("236c89")
		pickup.mesh = mesh
		pickup.material_override = frost
		root.add_child(pickup)
		return root
	if kind == 0:
		model = WeaponsCatalog.create_world_model(weapon_id)
	elif ITEM_MODELS.has(kind):
		model = WeaponsCatalog.create_item_model(ITEM_MODELS[kind])
	if not model:
		root.free()
		return null
	root.add_child(model)
	var bounds := AABB()
	var first := true
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var transform := model.transform
		var ancestor: Node = part
		var local_transform := Transform3D.IDENTITY
		while ancestor != model:
			local_transform = ancestor.transform * local_transform
			ancestor = ancestor.get_parent()
		var box: AABB = transform * local_transform * part.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.visibility_range_end = 75.0
	if not first:
		var desired_size: float = 1.40 if kind == 0 else ITEM_SIZES[kind]
		if kind == 0 and weapon_id in ["pistol", "knife"]: desired_size = 0.64
		var ratio := desired_size / maxf(0.001, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
		model.scale *= ratio
		model.position = -bounds.get_center() * ratio
	return root
