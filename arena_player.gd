extends CharacterBody3D

const WALK_SPEED := 5.6
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.6
const Characters := preload("res://characters_catalog.gd")
const Weapons := preload("res://weapons_catalog.gd")
const PARACHUTE := preload("res://assets/provided/army_parachute.glb")

class BodyMotion extends SkeletonModifier3D:
	const DURATION := 0.26
	var hips := -1
	var chest := -1
	var time_left := 0.0
	var world_axis := Vector3.ZERO
	var motion_angles := Vector3.ZERO
	var heading := 0.0

	func strike(normal: Vector3) -> void:
		world_axis = Vector3.UP.cross(-normal).normalized()
		time_left = DURATION if world_axis != Vector3.ZERO else 0.0

	func _process_modification_with_delta(delta: float) -> void:
		if time_left <= 0.0 and motion_angles.length_squared() <= 0.000001: return
		var rig := get_skeleton()
		var world_to_rig := rig.global_basis.orthonormalized().inverse()
		var body_to_rig := world_to_rig * Basis(Vector3.UP, heading)
		if motion_angles.length_squared() > 0.000001:
			rotate_joint(rig, hips, body_to_rig * (motion_angles * Vector3(0.35, -0.22, -0.42)))
			rotate_joint(rig, chest, body_to_rig * motion_angles)
		if time_left > 0.0:
			time_left = maxf(0.0, time_left - delta)
			var elapsed := DURATION - time_left
			var amount := smoothstep(0.0, 0.045, elapsed) * (1.0 - smoothstep(0.045, DURATION, elapsed))
			rotate_joint(rig, chest, world_to_rig * world_axis * (0.28 * amount))

	func rotate_joint(rig: Skeleton3D, joint: int, rig_rotation: Vector3) -> void:
		var amount := rig_rotation.length()
		if joint < 0 or amount < 0.0001: return
		var joint_basis := rig.get_bone_global_pose(joint).basis.orthonormalized()
		var axis := joint_basis.inverse() * (rig_rotation / amount)
		var rotation_offset := Quaternion(axis, amount)
		rig.set_bone_pose_rotation(joint, rig.get_bone_pose_rotation(joint) * rotation_offset)

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
var character_id := "soldier"
var weapon_id := "carbine"
var weapon_slots: Array[String] = []
var slot_magazines: Dictionary = {}
var magazine_capacity := 30
var c4_count := 0
var knife_owned := false
var held_root: BoneAttachment3D
var held_id := ""

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
var body_motion: BodyMotion
var visual_heading := 0.0

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
	model_root = Characters.scene_for(character_id).instantiate()
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
	else:
		animator = AnimationPlayer.new()
		model_root.add_child(animator)
		animator.root_node = NodePath("..")
	var motions := load("res://assets/characters/%s_motions.tres" % character_id) as AnimationLibrary
	if motions: animator.add_animation_library("", motions)

	if animator: preload("res://sky_motion.gd").attach(model_root, animator)
	var rigs := model_root.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		var rig := rigs[0] as Skeleton3D
		held_root = BoneAttachment3D.new()
		held_root.bone_name = "RightHand"
		rig.add_child(held_root)
		var motion := BodyMotion.new()
		for bone in range(rig.get_bone_count()):
			var bone_name := rig.get_bone_name(bone)
			if bone_name == "Hips" or bone_name.begins_with("Bind_Hips_"): motion.hips = bone
			elif bone_name == "Chest" or bone_name.begins_with("Bind_Spine1_"): motion.chest = bone
		if motion.chest >= 0:
			body_motion = motion
			rig.add_child(body_motion)
		else:
			motion.free()
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
		var was_strafing := animator.current_animation in ["strafeLeft", "strafeRight"]
		var sideways_threshold := 0.9 if was_strafing else 1.2
		if absf(local_velocity.x) > absf(local_velocity.z) * sideways_threshold:
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
	if body_motion and phase != "dead": body_motion.strike(normal)

func show_pose() -> bool:
	return phase != "dead" or previous_phase != "dead" or phase_clock < 1.25

func _process(delta: float) -> void:
	if embedded_gun: embedded_gun.visible = false
	if held_root:
		held_root.visible = weapon and phase == "ground"
		if weapon_id != held_id:
			for child in held_root.get_children(): child.queue_free()
			var gun: Node3D = Weapons.create_world_model(weapon_id)
			held_root.add_child(gun)
			gun.rotation_degrees = Vector3(0,90,0)
			gun.scale = Vector3.ONE * 0.75
			held_id = weapon_id
	if phase != previous_phase:
		landed_from_air = phase == "ground" and previous_phase in ["fall", "parachute"]
		phase_clock = 0
		previous_phase = phase
	phase_clock += delta
	if phase == "ground":
		var turn_response := 24.0 if aim or cooldown > 0.01 else 13.0
		visual_heading = lerp_angle(visual_heading, rotation.y, 1.0 - exp(-turn_response * delta))
	else:
		visual_heading = rotation.y
	visual.rotation.y = angle_difference(rotation.y, visual_heading)
	var bank: float = clampf(command.get("move", Vector2.ZERO).x, -1, 1)
	var pitch_target := -PI * 0.5 if phase == "fall" else 0.0
	var bank_target := -bank * 0.18 if phase in ["fall", "parachute"] else 0.0
	if body_motion:
		var lean := Vector3.ZERO
		if phase == "ground":
			var travel := Basis(Vector3.UP, visual_heading).inverse() * Vector3(velocity.x, 0, velocity.z)
			var restraint := 0.45 if aim or crouched else 1.0
			lean.x = clampf(-travel.z / SPRINT_SPEED, -0.4, 1.0) * 0.13
			lean.y = clampf(angle_difference(visual_heading, rotation.y) * 0.35, -0.22, 0.22)
			lean.z = clampf(-travel.x / WALK_SPEED, -1.0, 1.0) * 0.12
			lean *= restraint
		body_motion.heading = visual_heading
		body_motion.motion_angles = body_motion.motion_angles.lerp(lean, 1.0 - exp(-10.0 * delta)) if phase == "ground" else Vector3.ZERO
		if phase == "dead": body_motion.time_left = 0.0
	visual.rotation.x = lerp_angle(visual.rotation.x, pitch_target, 1 - exp(-12 * delta))
	visual.rotation.z = lerp_angle(visual.rotation.z, bank_target, 1 - exp(-12 * delta))
	if phase == "dead": visual.visible = show_pose()
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
	weapon_id = "carbine"
	weapon_slots.clear()
	slot_magazines.clear()
	magazine_capacity = 30
	c4_count = 0
	knife_owned = false
	magazine = 0
	ammo = 0
	medkits = 0
	grenades = 0
	backpack = false
	phase = "helicopter"
	collision_layer = 1
	reload_left = 0.0
	cooldown = 0.0
	if body_motion:
		body_motion.time_left = 0.0
		body_motion.motion_angles = Vector3.ZERO
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
			var rounds := mini(magazine_capacity - magazine, ammo)
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
	return {"character": character_id, "weapon_id":weapon_id,"slots":weapon_slots,"slot_mags":slot_magazines,"mag_capacity":magazine_capacity,"c4":c4_count,"knife":knife_owned,"p": position, "v": velocity, "y": yaw, "x": pitch, "hp": hp, "armor": armor, "ammo": ammo, "mag": magazine, "med": medkits, "gren": grenades, "bag": backpack, "gun": weapon, "score": score, "phase": phase, "respawn": respawn_left, "reload": reload_left, "crouch": crouched, "aim": aim, "cooldown": cooldown, "protection": protection}

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
		aim = s.get("aim", false)
	set_character(s.get("character",character_id))
	weapon_id = s.get("weapon_id","carbine")
	weapon_slots.assign(s.get("slots",[]))
	slot_magazines = s.get("slot_mags",{})
	magazine_capacity = s.get("mag_capacity",30)
	c4_count = s.get("c4",0)
	knife_owned = s.get("knife",false)
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

func set_character(id: String) -> void:
	if not Characters.valid(id): id = "soldier"
	if character_id == id: return
	character_id = id
	if not is_node_ready():return
	if is_instance_valid(model_root):
		visual.remove_child(model_root)
		model_root.queue_free()
	animator = null
	body_motion = null
	held_root = null
	held_id = ""
	embedded_gun = null
	install_model()
