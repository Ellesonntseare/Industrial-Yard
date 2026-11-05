extends CharacterBody3D

const WALK_SPEED := 5.6
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.6
const SOLDIER := preload("res://assets/provided/training_soldier.glb")
const PARACHUTE := preload("res://assets/provided/army_parachute.glb")

class HitReaction extends SkeletonModifier3D:
	const DURATION := 0.26
	var chest := -1
	var time_left := 0.0
	var world_axis := Vector3.ZERO

	func strike(normal: Vector3) -> void:
		world_axis = Vector3.UP.cross(-normal).normalized()
		time_left = DURATION if world_axis != Vector3.ZERO else 0.0

	func _process_modification_with_delta(delta: float) -> void:
		if time_left <= 0.0: return
		time_left = maxf(0.0, time_left - delta)
		var elapsed := DURATION - time_left
		var amount := smoothstep(0.0, 0.045, elapsed) * (1.0 - smoothstep(0.045, DURATION, elapsed))
		var rig := get_skeleton()
		var chest_basis := rig.get_bone_global_pose(chest).basis.orthonormalized()
		var rig_axis := (rig.global_basis.inverse() * world_axis).normalized()
		var bone_axis := chest_basis.inverse() * rig_axis
		var kick := Quaternion(bone_axis, 0.28 * amount)
		rig.set_bone_pose_rotation(chest, rig.get_bone_pose_rotation(chest) * kick)

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
var hit_reaction: HitReaction

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
	var model: Node3D = PARACHUTE.instantiate()
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
	model_root = SOLDIER.instantiate()
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
	var rigs := model_root.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		var rig := rigs[0] as Skeleton3D
		for bone in range(rig.get_bone_count()):
			if not rig.get_bone_name(bone).begins_with("Bind_Spine1_"): continue
			hit_reaction = HitReaction.new()
			hit_reaction.chest = bone
			rig.add_child(hit_reaction)
			break
	visual.position.y = 0.9
	model_root.position.y -= 0.9
	visual.get_child(0).visible = false
	animate()

func animate() -> void:
	if not animator: return
	var local_velocity := global_basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var ground_speed := local_velocity.length()
	var playback_rate := 1.0
	var clip := "idleWgun" if weapon else "idleWithoutGun"
	if phase == "dead": clip = "death"
	elif phase == "helicopter": clip = "sky/SkyGlide"
	elif phase == "fall": clip = "sky/SkyFall"
	elif phase == "parachute": clip = "sky/SkyPull" if phase_clock < 0.55 else "sky/SkyGlide"
	elif phase == "ground" and landed_from_air and phase_clock < 0.35: clip = "sky/SkyLand"
	elif reload_left > 0.0: clip = "reload"
	elif cooldown > 0.01: clip = "rapidShooting" if ground_speed < 0.5 else "runAndShooting"
	elif crouched:
		clip = "crouchWalk" if ground_speed > 0.3 else "crouch"
		if clip == "crouchWalk": playback_rate = clampf(ground_speed / CROUCH_SPEED, 0.55, 1.2)
	elif ground_speed > 0.3:
		var stride_speed := WALK_SPEED
		if absf(local_velocity.x) > absf(local_velocity.z) * 1.15:
			clip = "strafeRight" if local_velocity.x > 0 else "strafeLeft"
		elif local_velocity.z > 0:
			clip = "backpaddle"
		elif ground_speed > 6.5:
			clip = "run"
			stride_speed = SPRINT_SPEED
		else:
			clip = "walk"
		playback_rate = clampf(ground_speed / stride_speed, 0.58, 1.35)
	animator.speed_scale = playback_rate
	if animator.has_animation(clip) and animator.current_animation != clip:
		var anim := animator.get_animation(clip)
		if not clip.begins_with("sky/"):
			anim.loop_mode = Animation.LOOP_NONE if clip in ["death", "reload", "jump"] else Animation.LOOP_LINEAR
		var blend_time := 0.18
		if clip in ["death", "rapidShooting", "runAndShooting"] or clip.begins_with("sky/"):
			blend_time = 0.06
		animator.play(clip, blend_time)

func react_to_hit(normal: Vector3) -> void:
	if hit_reaction and phase != "dead": hit_reaction.strike(normal)

func show_pose() -> bool:
	return phase != "dead" or previous_phase != "dead" or phase_clock < 1.25

func _process(delta: float) -> void:
	if embedded_gun: embedded_gun.visible = weapon and phase == "ground"
	if phase != previous_phase:
		landed_from_air = phase == "ground" and previous_phase in ["fall", "parachute"]
		phase_clock = 0
		previous_phase = phase
	phase_clock += delta
	var bank: float = clampf(command.get("move", Vector2.ZERO).x, -1, 1)
	var pitch_target := -PI * 0.5 if phase == "fall" else 0.0
	var bank_target := -bank * 0.18 if phase in ["fall", "parachute"] else 0.0
	if phase == "ground" and not crouched:
		var motion := global_basis.inverse() * Vector3(velocity.x, 0, velocity.z)
		pitch_target = clampf(-motion.z / SPRINT_SPEED, -0.5, 1.0) * 0.065
		bank_target = clampf(-motion.x / WALK_SPEED, -1.0, 1.0) * 0.08
	visual.rotation.x = lerp_angle(visual.rotation.x, pitch_target, 1 - exp(-12 * delta))
	visual.rotation.z = lerp_angle(visual.rotation.z, bank_target, 1 - exp(-12 * delta))
	if phase == "dead": visual.visible = show_pose()
	if phase == "dead" and hit_reaction: hit_reaction.time_left = 0.0
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
	collision_layer = 1
	reload_left = 0.0
	cooldown = 0.0
	if hit_reaction: hit_reaction.time_left = 0.0
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
	update_collider()
	aim = command.get("aim", false)
	canopy.visible = phase == "parachute"
	if phase == "helicopter":
		return
	var axis: Vector2 = command.move
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y).limit_length()
	var speed := SPRINT_SPEED if command.run else WALK_SPEED
	if crouched: speed = CROUCH_SPEED
	if aim: speed = minf(speed, 3.2)
	if phase == "ground" and axis.y > 0: speed *= 0.82
	if phase == "parachute": speed = 9.0
	if phase == "fall": speed = 6.0
	var acceleration := (32.0 if axis.length_squared() < 0.01 else 29.0) if is_on_floor() else 10.0
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
		yaw = s.y
		pitch = s.x
		velocity = s.v
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
	var alive_layer := 0 if phase == "dead" else 1
	if collision_layer != alive_layer: collision_layer = alive_layer
	respawn_left = s.respawn
	reload_left = s.reload
	crouched = s.crouch
	update_collider()
	cooldown = s.cooldown
	protection = s.protection
	canopy.visible = phase == "parachute"
	visual.visible = show_pose()
	animate()

func update_collider() -> void:
	var capsule: CapsuleShape3D = body_collider.shape
	var height := 1.2 if crouched else 1.8
	if capsule.height != height:
		capsule.height = height
		body_collider.position.y = height * 0.5
