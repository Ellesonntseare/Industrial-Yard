extends Node3D
## Lightweight racks use the same weapon models as the loot catalog.
## reward_positions() returns world-space pickups for the host's unlock callback.

const DISPLAY_WEAPONS := ["carbine", "ak47", "pistol", "shotgun", "knife", "ak47"]
var pickup_slots: Array[Dictionary] = []
var weapon_catalog: Script
var loot_models: Script

func load_catalogs() -> void:
	weapon_catalog = load("res://weapons_catalog.gd") as Script
	loot_models = load("res://loot_models.gd") as Script
	assert(weapon_catalog != null and loot_models != null, "Armory furniture requires the weapon/loot catalogs")

func setup(arena: Node3D, armory: Node3D) -> void:
	var packed := load("res://assets/armory/armory_room.glb") as PackedScene
	assert(packed != null, "Armory interior must be imported before play")
	var room := packed.instantiate() as Node3D
	arena.add_child(room)
	room.global_transform = armory.door.get_closed_transform() * Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.84), Vector3(-1.0, 0.04, 3.55))
	clear_old_furniture(arena)
	clear_interior_collisions(arena, room)
	setup_imported_room(room)
	room.reparent(self, true)
	for part in room.find_children("*", "MeshInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.create_trimesh_collision()

func clear_old_furniture(arena: Node3D) -> void:
	var replaced_bounds: Array[AABB] = []
	for mesh in arena.get_node("Map").find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) not in ["DistrictChunk_379", "DistrictChunk_380", "DistrictChunk_381", "DistrictChunk_382", "DistrictChunk_414", "DistrictChunk_415", "DistrictChunk_416", "DistrictChunk_417", "DistrictChunk_418", "DistrictChunk_419", "DistrictChunk_561", "DistrictChunk_567"]: continue
		replaced_bounds.append(mesh.global_transform * mesh.get_aabb())
		mesh.hide()
	# Existing map props share a StaticBody, so disable only each matched prop shape.
	for collider in arena.get_node("Collision").find_children("*", "CollisionShape3D", true, false):
		var box: AABB = collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
		for removed in replaced_bounds:
			if box.get_center().distance_to(removed.get_center()) < 0.02 and box.size.distance_to(removed.size) < 0.03:
				collider.set_deferred("disabled", true)
				break

func clear_interior_collisions(arena: Node3D, room: Node3D) -> void:
	# Remove legacy rubble inside the replacement interior while retaining outer
	# hut walls, its roof, and the original ground underneath the new floor.
	var world_to_room := room.global_transform.affine_inverse()
	for collider in arena.get_node("Collision").find_children("*", "CollisionShape3D", true, false):
		if collider.disabled or not collider.shape is ConcavePolygonShape3D: continue
		var bounds: AABB = collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
		var room_bounds := room.global_transform * AABB(Vector3(-2.45, 0.12, -2.05), Vector3(4.9, 2.08, 4.1))
		if not bounds.intersects(room_bounds): continue
		var faces: PackedVector3Array = collider.shape.get_faces()
		var kept := PackedVector3Array()
		var transform: Transform3D = world_to_room * collider.global_transform
		for index in range(0, faces.size(), 3):
			var a := transform * faces[index]
			var b := transform * faces[index + 1]
			var c := transform * faces[index + 2]
			var center := (a + b + c) / 3.0
			var interior := absf(center.x) < 2.45 and absf(center.z) < 2.05 and maxf(a.y, maxf(b.y, c.y)) > 0.12 and maxf(a.y, maxf(b.y, c.y)) < 2.2
			if interior: continue
			kept.append_array(PackedVector3Array([faces[index], faces[index + 1], faces[index + 2]]))
		if kept.size() == faces.size(): continue
		var replacement := ConcavePolygonShape3D.new()
		replacement.backface_collision = collider.shape.backface_collision
		replacement.set_faces(kept)
		collider.set_deferred("shape", replacement)

func setup_imported_room(room: Node3D) -> void:
	# For the optimized user-provided Armory interior at its exported human scale.
	# It already contains cabinets and counters, so only add guns and ammunition.
	load_catalogs()
	global_transform = room.global_transform
	var display_board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(4.35, 1.15, 0.035)
	display_board.mesh = board_mesh
	display_board.position = Vector3(0, 1.72, -2.09)
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color("a4b1ac")
	board_material.metallic = 0.25
	board_material.roughness = 0.65
	display_board.material_override = board_material
	add_child(display_board)
	for index in range(4):
		var at := Vector3(-1.5 + index, 1.42, -2.02)
		var display := add_display(DISPLAY_WEAPONS[index], at, true)
		if display: display.rotation.y = PI * 0.5
		var second := add_display(DISPLAY_WEAPONS[index], at + Vector3.UP * 0.55, true)
		if second: second.rotation.y = PI * 0.5
		var label := Label3D.new()
		label.text = weapon_catalog.definition(DISPLAY_WEAPONS[index]).name
		label.font_size = 32
		label.pixel_size = 0.0016
		label.modulate = Color("15231f")
		label.outline_size = 0
		label.position = Vector3(at.x, 1.18, -2.015)
		add_child(label)
		pickup_slots.append({"kind": 0, "weapon_id": DISPLAY_WEAPONS[index], "position": to_global(Vector3(at.x, 0.78, -1.6))})
	add_display("pistol", Vector3(-1.2, 0.72, -1.3), false)
	add_display("knife", Vector3(1.2, 0.72, -1.3), false)
	var ammo := loot_models.create_loot(1, "carbine") as Node3D
	if ammo:
		add_child(ammo)
		ammo.position = Vector3(0, 0.58, 0.8)
	pickup_slots.append({"kind": 1, "weapon_id": "carbine", "position": to_global(Vector3(0, 0.65, 0.8))})
	pickup_slots.append({"kind": 3, "weapon_id": "carbine", "position": to_global(Vector3(1.45, 0.65, 0.7))})

func add_display(weapon_id: String, at: Vector3, on_rack: bool) -> Node3D:
	var model := weapon_catalog.create_world_model(weapon_id) as Node3D
	if not model: return null
	var mount := Node3D.new()
	add_child(mount)
	mount.position = at
	mount.add_child(model)
	var bounds := model_bounds(mount)
	if on_rack:
		if bounds.size.x >= maxf(bounds.size.y, bounds.size.z): model.rotate_y(PI * 0.5)
		elif bounds.size.y > bounds.size.z: model.rotate_x(PI * 0.5)
	else:
		if bounds.size.y >= maxf(bounds.size.x, bounds.size.z): model.rotate_z(PI * 0.5)
	bounds = model_bounds(mount)
	var desired_length := 0.38 if weapon_id in ["pistol", "knife"] else 0.82
	var ratio := desired_length / maxf(0.001, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	model.scale *= ratio
	model.position = model.position * ratio - bounds.get_center() * ratio
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = 40.0
	for animation in model.find_children("*", "AnimationPlayer", true, false): animation.stop()
	return mount

func model_bounds(mount: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in mount.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible or mesh.mesh == null: continue
		var box: AABB = mount.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func reward_positions() -> Array[Dictionary]:
	return pickup_slots.duplicate(true)
