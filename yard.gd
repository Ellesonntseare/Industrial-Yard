extends Node3D

const Door = preload("res://door.gd")
const NORTH_ENTRY = Vector3(0, 0.1, -147.9)
const WALK_SPEED = 4.0
const RUN_SPEED = 7.0

var player: CharacterBody3D
var camera: Camera3D
var doors: Array[Node3D] = []
var prompt: Label
var spawn_point = NORTH_ENTRY

func _ready() -> void:
	build_doors()
	build_player()
	build_hud()
	if "--review-yard" in OS.get_cmdline_user_args():
		review.call_deferred()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func build_doors() -> void:
	var leaves: Dictionary = {}
	for mesh: MeshInstance3D in $Map.find_children("*", "MeshInstance3D", true, false):
		leaves[String(mesh.name)] = mesh
	for marker in $Collision.get_children():
		if not marker.has_meta("door_size"):
			continue
		var size: Vector3 = marker.get_meta("door_size")
		var door = Door.new()
		door.name = "Door_%02d" % (doors.size() + 1)
		door.width = size.x
		door.height = size.y
		door.depth = size.z
		door.transform = marker.transform
		$Collision.add_child(door)
		doors.append(door)
		var leaf: MeshInstance3D = leaves.get(String(marker.name))
		if leaf:
			leaf.reparent(door, true)
		marker.queue_free()

func build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.floor_snap_length = 0.3
	player.rotation.y = PI
	add_child(player)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 0.9
	player.add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.64
	camera.far = 650
	player.add_child(camera)
	camera.make_current()
	player.position = spawn_point
	snap_spawn.call_deferred()

func snap_spawn() -> void:
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(NORTH_ENTRY + Vector3.UP * 8, NORTH_ENTRY - Vector3.UP * 8)
	query.exclude = [player.get_rid()]
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not floor_hit.is_empty():
		spawn_point = floor_hit.position + Vector3.UP * 0.08
	player.position = spawn_point

func build_hud() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var hint := Label.new()
	hint.text = "INDUSTRIAL YARD   ·   WASD Move   Shift Run   Space Jump   E Door   R Reset   Esc Mouse"
	hint.position = Vector2(20, 16)
	hint.add_theme_constant_override("outline_size", 6)
	overlay.add_child(hint)
	prompt = Label.new()
	prompt.position = Vector2(20, 46)
	prompt.add_theme_constant_override("outline_size", 6)
	overlay.add_child(prompt)

func nearby_door() -> Node3D:
	var best: Node3D
	var gap := 2.6
	for door in doors:
		var position: Vector3 = door.to_global(Vector3(door.width * 0.5, 0, 0))
		var distance := player.global_position.distance_to(position)
		if distance < gap:
			best = door
			gap = distance
	return best

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * 0.002)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.002, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_E:
				var door := nearby_door()
				if door:
					door.toggle(player.global_position)
			KEY_R:
				reset_player()

func reset_player() -> void:
	player.position = spawn_point
	player.velocity = Vector3.ZERO
	player.rotation.y = PI
	camera.rotation.x = 0
	player.reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.x = int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		input.y = int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	var direction := player.basis * Vector3(input.x, 0, input.y).normalized()
	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if not player.is_on_floor():
		player.velocity.y -= 9.8 * delta
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE):
		player.velocity.y = 4.7
	player.move_and_slide()
	if player.position.y < -12:
		reset_player()
	var door := nearby_door()
	prompt.text = ("E  Close door" if door.is_open else "E  Open door") if door else ""

func review() -> void:
	for frame in range(24):
		await get_tree().physics_frame
	var meshes := $Map.find_children("*", "MeshInstance3D", true, false).size()
	var grounded := player.is_on_floor()
	var starting_position := player.position
	var traveled := 0.0
	set_physics_process(false)
	for frame in range(120):
		await get_tree().physics_frame
		player.velocity = Vector3(0, -1, WALK_SPEED)
		player.move_and_slide()
	traveled = player.position.z - starting_position.z
	var door_check: bool = doors.size() == 10
	for door in doors:
		door_check = door.toggle(Vector3.INF) and door.is_open and door_check
	await get_tree().create_timer(0.5).timeout
	var passed := grounded and traveled > 4.0 and door_check and meshes > 100
	print("YARD_REVIEW meshes=", meshes, " grounded=", grounded, " walked_m=", traveled, " working_doors=", doors.size(), " passed=", passed)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://yard-preview.png")
	get_tree().quit(0 if passed else 1)
