extends SceneTree

var arena: Node3D
var checks := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	arena = load("res://battle.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.review_mode = true
	arena.shooting_practice()
	await physics_frame
	var player = arena.fighters[1]
	var bot = arena.fighters[arena.TRAINING_ID]
	await create_timer(4.1).timeout
	checks.bot_shoots_gently = player.hp >= 95 and player.hp < 100
	checks.bot_uses_ammo = bot.magazine < 12
	player.hp = 21
	await create_timer(2.7).timeout
	checks.bot_leaves_survival_health = player.hp == 20
	player.hp = 100
	arena.training_enabled = false
	bot.command.move = Vector2.ZERO
	player.position = arena.floor_at(arena.NORTH_ENTRY + Vector3(0, 0, 4))
	bot.position = arena.floor_at(arena.NORTH_ENTRY + Vector3(0, 0, 13))
	arena.look_yaw = PI
	arena.look_pitch = 0
	await physics_frame
	arena.request_action("place_ice")
	await physics_frame
	await physics_frame
	checks.ice_placed_by_game_input = arena.ice_walls.size() == 1 and player.ice_count == 2
	var look := Basis(Vector3.UP, PI)
	var hit: Dictionary = arena.trace_shot(player, look, false).hit
	checks.ice_intercepts_bullet = not arena.ice_walls.is_empty() and hit.get("collider") == arena.ice_walls.values()[0]
	var before: float = bot.hp
	player.cooldown = 0.0
	arena.shoot(1)
	checks.ice_prevents_damage = bot.hp == before
	var packed: Dictionary = arena.pack_ice_walls()
	arena.clear_ice_walls()
	arena.apply_ice_walls(packed)
	checks.ice_replica_has_collision = arena.ice_walls.size() == 1 and arena.ice_walls.values()[0].collision_layer == 2
	arena.clear_ice_walls()
	await physics_frame
	arena.request_action("place_c4")
	await physics_frame
	await physics_frame
	checks.c4_placed_with_level_aim = arena.charges.size() == 1 and player.c4_count == 2
	await create_timer(.82).timeout
	checks.c4_arms = not arena.charges.is_empty() and arena.charges.values()[0].armed
	arena.request_action("detonate_c4")
	checks.c4_detonates = arena.charges.is_empty()
	arena.set_physics_process(false)
	player.position.y = 100
	player.phase = "parachute"
	player.velocity = Vector3(0, -7, 0)
	player.command.move = Vector2(0, -1)
	for frame in range(65):
		await physics_frame
		player.step(1.0 / 60)
	checks.forward_dives_faster = player.velocity.y < -18 and Vector2(player.velocity.x, player.velocity.z).length() > 10 and player.canopy.visible
	player.command.move = Vector2.ZERO
	for frame in range(60):
		await physics_frame
		player.step(1.0 / 60)
	checks.release_returns_to_glide = is_equal_approx(player.velocity.y, -7.0)
	var passed := true
	for result in checks.values(): passed = passed and result
	print("COMBAT_PLAYTEST ", JSON.stringify({"passed": passed, "checks": checks}))
	root.remove_child(arena)
	arena.free()
	await process_frame
	quit(0 if passed else 1)
