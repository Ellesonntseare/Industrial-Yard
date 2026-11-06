extends SceneTree

var arena: Node3D
var ui: Control
var checks := {}

func _initialize() -> void:
	call_deferred("run")

func touch(point: Vector2, finger: int, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = point
	event.pressed = down
	root.push_input(event, true)

func button(key: String, finger: int, down: bool = true) -> void:
	touch(ui.center(key) * ui.frame_scale, finger, down)

func drag(point: Vector2, relative: Vector2, finger: int) -> void:
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = point
	event.relative = relative
	root.push_input(event, true)

func run() -> void:
	arena = load("res://battle.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	ui = arena.mobile_hud
	ui.touch_layout = true
	ui.positions = ui.DEFAULTS.duplicate()
	arena.shooting_practice()
	arena.capture_game_pointer()
	checks.phone_keeps_pointer_visible = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	for frame in range(3): await process_frame
	for size in [Vector2i(1280, 800), Vector2i(2400, 1080), Vector2i(800, 450)]:
		root.size = size
		root.content_scale_size = size
		for frame in range(3): await process_frame
		var body = arena.fighters[1]
		body.position = arena.floor_at(arena.NORTH_ENTRY + Vector3(0, 0, 8))
		body.phase = "ground"
		body.cooldown = 0
		body.magazine = 30
		body.reload_left = 0
		body.ammo = 90
		body.hp = 100
		body.protection = 100
		var suffix := str(size.x)
		button("fire", 4)
		checks["press_starts_" + suffix] = ui.merge_controls(arena.controls()).fire
		# The mouse event Android creates for menus must not toggle gameplay twice.
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = ui.center("aim") * ui.frame_scale
		mouse.pressed = true
		root.push_input(mouse, true)
		checks["emulated_mouse_ignored_" + suffix] = not ui.aiming
		button("move", 1)
		drag((ui.center("move") + Vector2(0, -55)) * ui.frame_scale, Vector2(0, -55) * ui.frame_scale, 1)
		button("aim", 2)
		button("aim", 2, false)
		checks["move_aim_fire_together_" + suffix] = ui.movement.y < -.5 and ui.aiming and arena.controls().fire
		# Finger drift outside Shoot must not cancel an intentional long press.
		drag(ui.center("fire") * ui.frame_scale + Vector2(-150, -100), Vector2(-150, -100), 4)
		await create_timer(1.1).timeout
		checks["hold_fires_repeatedly_" + suffix] = body.magazine <= 24 and arena.controls().fire
		button("move", 1, false)
		checks["other_finger_release_keeps_firing_" + suffix] = arena.controls().fire
		button("fire", 4, false)
		var rounds: int = body.magazine
		await create_timer(.3).timeout
		checks["release_stops_firing_" + suffix] = not arena.controls().fire and body.magazine == rounds
		button("reload", 3)
		button("reload", 3, false)
		checks["reload_reaches_game_" + suffix] = body.reload_left > 0
		button("fire", 4)
		ui.set_settings(true)
		checks["settings_release_fire_" + suffix] = not arena.controls().fire
		button("fire", 4, false)
		ui.set_settings(false)
		ui.reset_inputs()
		for frame in range(2): await process_frame
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	print("PHONE_HOLD_REVIEW ", JSON.stringify({"passed": passed, "checks": checks}))
	var file := FileAccess.open("user://phone-hold-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks}, "  "))
	file.close()
	root.remove_child(arena)
	arena.free()
	await process_frame
	quit(0 if passed else 1)
