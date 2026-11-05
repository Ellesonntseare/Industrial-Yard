extends CharacterBody3D

var peer_id := 1
var yaw := 0.0
var pitch := 0.0
var hp := 100.0
var armor := 0.0
var ammo := 0
var magazine := 0
var medkits := 0
var grenades := 0
var backpack := false
var weapon := false
var score := 0
var phase := "helicopter"
var cooldown := 0.0
var reload_left := 0.0
var respawn_left := 0.0
var command := {"move": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "run": false, "jump": false}
var visual: Node3D
var canopy: MeshInstance3D
var target_position := Vector3.ZERO
var target_yaw := 0.0
var animator: AnimationPlayer
var crouched := false
var aim := false
var model_root: Node3D
var protection := 0.0
var body_collider: CollisionShape3D
var phase_clock := 0.0
var previous_phase := ""
var landed_from_air := false
var embedded_gun: MeshInstance3D

func _ready() -> void:
	floor_snap_length = 0.35
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	body_collider = collider
	visual = Node3D.new()
	add_child(visual)
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.33
	capsule.height = 1.8
	mesh.mesh = capsule
	mesh.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d39b47") if peer_id == 1 else Color("649eb8")
	mesh.material_override = mat
	visual.add_child(mesh)
	canopy = MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 2.2
	dome.height = 1.0
	canopy.mesh = dome
	canopy.position.y = 3.4
	canopy.material_override = mat
	add_child(canopy)
	canopy.visible = false
	install_parachute()
	install_model()

func install_parachute() -> void:
	var packed = load("res://assets/provided/army_parachute.glb") as PackedScene
	if not packed: return
	var model: Node3D = packed.instantiate()
	canopy.add_child(model)
	canopy.mesh = null
	canopy.position.y = 1.2
	var mesh_nodes = model.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty(): return
	var mesh: MeshInstance3D = mesh_nodes[0]
	var bounds: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
	var ratio := 4.6 / maxf(bounds.size.y, 0.01)
	model.scale = Vector3.ONE * ratio
	model.position.y = -bounds.position.y * ratio

func install_model() -> void:
	var packed = load("res://assets/provided/training_soldier.glb") as PackedScene
	if not packed: return
	model_root = packed.instantiate()
	visual.add_child(model_root)
	model_root.rotation.y = PI
	var bounds := AABB()
	var first := true
	for item in model_root.find_children("*", "MeshInstance3D", true, false):
		var material_name := ""
		if item.mesh.get_surface_count() > 0 and item.mesh.surface_get_material(0): material_name = item.mesh.surface_get_material(0).resource_name
		if "gun" in (String(item.name) + String(item.mesh.resource_name) + material_name).to_lower(): embedded_gun = item
		var box: AABB = model_root.global_transform.affine_inverse() * item.global_transform * item.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if bounds.size.y > 0.001:
		var ratio := 1.8 / bounds.size.y
		model_root.scale = Vector3.ONE * ratio
		model_root.position.y = -bounds.position.y * ratio
	var animators = model_root.find_children("*", "AnimationPlayer", true, false)
	if not animators.is_empty(): animator = animators[0]
	if animator: preload("res://sky_motion.gd").attach(model_root, animator)
	visual.position.y = 0.9
	model_root.position.y -= 0.9
	visual.get_child(0).visible = false
	animate()

func animate() -> void:
	if not animator: return
	var clip := "idleWgun" if weapon else "idleWithoutGun"
	if phase == "dead": clip = "death"
	elif phase == "helicopter": clip = "sky/SkyGlide"
	elif phase == "fall": clip = "sky/SkyFall"
	elif phase == "parachute": clip = "sky/SkyPull" if phase_clock < 0.55 else "sky/SkyGlide"
	elif phase == "ground" and landed_from_air and phase_clock < 0.35: clip = "sky/SkyLand"
	elif reload_left > 0.0: clip = "reload"
	elif cooldown > 0.01: clip = "rapidShooting" if velocity.length() < 0.5 else "runAndShooting"
	elif crouched: clip = "crouchWalk" if Vector2(velocity.x, velocity.z).length() > 0.3 else "crouch"
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		clip = "run" if Vector2(velocity.x, velocity.z).length() > 5.0 else "walk"
	if animator.has_animation(clip) and animator.current_animation != clip:
		var anim := animator.get_animation(clip)
		if not clip.begins_with("sky/"):
			anim.loop_mode = Animation.LOOP_NONE if clip in ["death", "reload", "jump"] else Animation.LOOP_LINEAR
		animator.play(clip, 0.14)

func _process(delta: float) -> void:
	if embedded_gun: embedded_gun.visible = weapon and phase == "ground"
	if phase != previous_phase:
		landed_from_air = phase == "ground" and previous_phase in ["fall", "parachute"]
		phase_clock = 0
		previous_phase = phase
	phase_clock += delta
	var bank: float = clampf(command.get("move", Vector2.ZERO).x, -1, 1)
	visual.rotation.x = lerp_angle(visual.rotation.x, -PI * 0.5 if phase == "fall" else 0.0, 1 - exp(-8 * delta))
	visual.rotation.z = lerp_angle(visual.rotation.z, -bank * 0.18 if phase in ["fall", "parachute"] else 0.0, 1 - exp(-8 * delta))
	if phase == "parachute":
		var opening := clampf(phase_clock / 0.45, 0.08, 1)
		canopy.scale = Vector3(opening, opening, opening)
		canopy.rotation.z = visual.rotation.z * 0.5
	else: canopy.scale = Vector3.ONE
	animate()

func drop(at: Vector3) -> void:
	position = at
	target_position = at
	velocity = Vector3.ZERO
	hp = 100.0
	armor = 0.0
	weapon = false
	magazine = 0
	ammo = 0
	medkits = 0
	grenades = 0
	backpack = false
	phase = "helicopter"
	reload_left = 0.0
	cooldown = 0.0
	protection = 2.0
	visual.visible = true
	canopy.visible = false
	command["move"] = Vector2.ZERO
	reset_physics_interpolation()

func step(delta: float) -> void:
	protection = maxf(0.0, protection - delta)
	cooldown = maxf(0.0, cooldown - delta)
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left == 0.0:
			var rounds := mini(30 - magazine, ammo)
			magazine += rounds
			ammo -= rounds
	if phase == "dead":
		respawn_left -= delta
		return
	yaw = command.yaw
	pitch = command.pitch
	rotation.y = yaw
	var wants_crouch: bool = command.get("crouch", false)
	if wants_crouch or not crouched or not test_move(global_transform, Vector3.UP * 0.65):
		crouched = wants_crouch
	var capsule: CapsuleShape3D = body_collider.shape
	capsule.height = 1.2 if crouched else 1.8
	body_collider.position.y = capsule.height * 0.5
	aim = command.get("aim", false)
	canopy.visible = phase == "parachute"
	if phase == "helicopter":
		return
	var axis: Vector2 = command.move
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y).limit_length()
	var speed := 7.0 if command.run else 4.6
	if crouched: speed = 2.4
	if aim: speed = minf(speed, 3.0)
	if phase == "parachute": speed = 9.0
	if phase == "fall": speed = 6.0
	var acceleration := 26.0 if is_on_floor() else 10.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	velocity.y = maxf(velocity.y - (12.0 if phase == "fall" else 20.0) * delta, -7.0 if phase == "parachute" else -28.0)
	if phase == "ground" and is_on_floor() and command.jump:
		velocity.y = 6.0
	command.jump = false
	var landing_speed := velocity.y
	move_and_slide()
	if is_on_floor():
		if phase == "fall": hp -= maxf(0.0, -landing_speed - 12.0) * 5.0
		phase = "ground"
		canopy.visible = false
	visual.visible = hp > 0
	animate()

func pack() -> Dictionary:
	return {"p": position, "v": velocity, "y": yaw, "x": pitch, "hp": hp, "armor": armor, "ammo": ammo, "mag": magazine, "med": medkits, "gren": grenades, "bag": backpack, "gun": weapon, "score": score, "phase": phase, "respawn": respawn_left, "reload": reload_left, "crouch": crouched, "cooldown": cooldown, "protection": protection}

func unpack(s: Dictionary, local: bool) -> void:
	target_position = s.p
	target_yaw = s.y
	if local:
		var error := position.distance_to(s.p)
		if error > 3.0 or phase != s.phase:
			position = s.p
		elif error > 0.15:
			position = position.lerp(s.p, 0.2)
		velocity = s.v
	else:
		pitch = s.x
	hp = s.hp
	armor = s.armor
	ammo = s.ammo
	magazine = s.mag
	medkits = s.med
	grenades = s.gren
	backpack = s.bag
	weapon = s.gun
	score = s.score
	phase = s.phase
	respawn_left = s.respawn
	reload_left = s.reload
	crouched = s.crouch
	cooldown = s.cooldown
	protection = s.protection
	canopy.visible = phase == "parachute"
	visual.visible = phase != "dead"
	animate()
