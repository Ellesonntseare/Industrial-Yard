extends SceneTree

class ArenaFixture extends "res://yard.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

func _initialize() -> void:
	run.call_deferred()

func walk(body: CharacterBody3D, point: Vector3) -> bool:
	for frame in range(180):
		await physics_frame
		var difference := point - body.position
		difference.y = 0
		if difference.length() < 0.045: return true
		body.velocity = difference.normalized() * 2.5 + Vector3.DOWN
		body.move_and_slide()
	print("BLOCKED target=", point, " current=", body.position)
	for index in range(body.get_slide_collision_count()):
		var contact := body.get_slide_collision(index)
		print("CONTACT ", contact.get_position(), " ", contact.get_normal(), " ", contact.get_collider())
		var owner := contact.get_collider_shape() as CollisionShape3D
		print("OBSTACLE ", owner.get_path(), " ", owner.shape.get_class(), " ", owner.global_transform * owner.shape.get_debug_mesh().get_aabb())
	return false

func run() -> void:
	var arena := ArenaFixture.new()
	root.add_child(arena)
	var map = load("res://downloaded/neighbour_town/industrial_town.glb").instantiate()
	map.name = "Map"
	arena.add_child(map)
	var collision = load("res://downloaded/neighbour_town/collision.scn").instantiate()
	collision.name = "Collision"
	arena.add_child(collision)
	arena.build_doors()
	var door
	for candidate in arena.doors:
		if not candidate.find_children("*door_Soft_Wood*", "MeshInstance3D", true, false).is_empty(): door = candidate
	var armory = load("res://locked_armory.gd").new()
	arena.add_child(armory)
	armory.configure(door, Vector3(-92, 0.4, -131), true)
	var furniture = load("res://armory_furnishings.gd").new()
	arena.add_child(furniture)
	furniture.setup(arena, armory)
	var player := CharacterBody3D.new()
	arena.add_child(player)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	player.add_child(shape)
	var door_frame: Transform3D = door.get_closed_transform()
	player.position = door_frame * Vector3(0.59, 0.1, -1)
	await physics_frame
	await physics_frame
	var checks := {}
	checks.armory_gun_pickups = furniture.reward_positions().filter(func(item): return item.kind == 0).size() == 4
	checks.armory_displays_exist = furniture.find_children("*", "MeshInstance3D", true, false).size() >= 8
	var catalog = load("res://weapons_catalog.gd")
	var loot_factory = load("res://loot_models.gd")
	checks.all_weapons_load = true
	for id in catalog.ids():
		var model: Node3D = catalog.create_world_model(id)
		checks.all_weapons_load = checks.all_weapons_load and model != null
		if model: model.free()
	checks.all_loot_models_load = true
	for kind in range(7):
		var model: Node3D = loot_factory.create_loot(kind, "shotgun")
		checks.all_loot_models_load = checks.all_loot_models_load and model != null
		if model: model.free()
	checks.closed_door_blocks_player = player.test_move(player.global_transform, door_frame.basis * Vector3(0, 0, 2))
	armory.set_door_state(true, true)
	await physics_frame
	checks.entry_accessible = await walk(player, door_frame * Vector3(0.59, 0.1, 0.7))
	checks.vestibule_clear = await walk(player, door_frame * Vector3(-1.0, 0.1, 1.0))
	checks.room_accessible = await walk(player, door_frame * Vector3(-1.0, 0.1, 2.0))
	checks.case_side_accessible = await walk(player, door_frame * Vector3(-2.0, 0.1, 2.0))
	checks.case_approach = await walk(player, door_frame * Vector3(-2.0, 0.1, 3.0))
	checks.clear_case_on_exit = await walk(player, door_frame * Vector3(-2.0, 0.1, 2.0))
	checks.exit_accessible = await walk(player, door_frame * Vector3(-1, 0.1, 1.0))
	checks.door_approach_clear = await walk(player, door_frame * Vector3(0.59, 0.1, 0.7))
	checks.back_through_door = await walk(player, door_frame * Vector3(0.59, 0.1, -1))
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	print("ARMORY_ROOM_ACCESS ", JSON.stringify({"passed": passed, "checks": checks, "position": str(player.position)}))
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1100, 750)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("90a9be")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.9
		arena.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, -20, 0)
		arena.add_child(sun)
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.global_position = door_frame * Vector3(-1.0, 1.65, 2.0)
		camera.look_at(door_frame * Vector3(-1.0, 1.15, 5.0))
		camera.make_current()
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://review/armory-in-hut.png")
	quit(0 if passed else 1)
