extends Node3D
## The arena calls try_interact on the host and includes pack_state in snapshots.
## Exclude the managed door from ordinary door interactions and door snapshots.
## Connect unlocked to spawn the room's weapon loot, once per round.

signal unlocked(peer_id: int)

const INTERACT_DISTANCE := 2.6
const ALARM_DURATION := 10.0
const ALARM_PATH := "res://audio/armory/fire_alarm_bell.wav"
static var alarm_stream: AudioStreamWAV

var configured_authority := false
var door
var keycard_owner := 0
var keycard_available := true
var is_unlocked := false
var alarm_left := 0.0
var card_position := Vector3.ZERO
var card_visual: Node3D
var reader: Node3D
var reader_label: Label3D
var reader_light: StandardMaterial3D
var alarm_player: AudioStreamPlayer3D
var sequence := 0
var last_received := -1
var door_motion: Tween
var visual_time := 0.0
var arena: Node3D
var initial_card_position := Vector3.ZERO

func setup(owner_arena: Node3D, managed_door: Node3D = null, keycard_position: Vector3 = Vector3.INF) -> void:
	arena = owner_arena
	if not managed_door:
		for candidate in arena.doors:
			if not candidate.find_children("*door_Soft_Wood*", "MeshInstance3D", true, false).is_empty():
				managed_door = candidate
				break
	assert(managed_door != null, "Armory needs an existing door or an explicitly supplied room door")
	if not keycard_position.is_finite():
		keycard_position = arena.floor_at(Vector3(-92, 0, -131)) + Vector3.UP * 0.3
	configure(managed_door, keycard_position, arena.authority)

func interact(peer_id: int) -> bool:
	return arena != null and arena.fighters.has(peer_id) and try_interact(peer_id, arena.fighters[peer_id])

func hint(peer_id: int) -> String:
	return hint_for(peer_id, arena.fighters[peer_id]) if arena != null and arena.fighters.has(peer_id) else ""

func reset() -> void:
	reset_round(initial_card_position)

func configure(managed_door: Node3D, keycard_position: Vector3, is_host: bool) -> void:
	assert(is_inside_tree() and managed_door.is_inside_tree())
	door = managed_door
	configured_authority = is_host
	card_position = keycard_position
	initial_card_position = keycard_position
	door.set_meta("locked_armory", true)
	build_visuals()
	set_door_state(false, true)
	refresh_visuals()

func build_visuals() -> void:
	card_visual = Node3D.new()
	add_child(card_visual)
	var card_material := StandardMaterial3D.new()
	card_material.albedo_color = Color("c6d0d5")
	card_material.metallic = 0.45
	card_material.roughness = 0.4
	var card := BoxMesh.new()
	card.size = Vector3(0.16, 0.008, 0.1)
	var card_mesh := MeshInstance3D.new()
	card_mesh.mesh = card
	card_mesh.material_override = card_material
	card_visual.add_child(card_mesh)
	var stripe := MeshInstance3D.new()
	var stripe_shape := BoxMesh.new()
	stripe_shape.size = Vector3(0.145, 0.001, 0.023)
	stripe.mesh = stripe_shape
	stripe.position = Vector3(0, 0.005, -0.022)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = Color("202a30")
	stripe.material_override = stripe_material
	card_visual.add_child(stripe)
	var chip := MeshInstance3D.new()
	var chip_shape := BoxMesh.new()
	chip_shape.size = Vector3(0.023, 0.001, 0.018)
	chip.mesh = chip_shape
	chip.position = Vector3(-0.045, 0.005, 0.018)
	var chip_material := StandardMaterial3D.new()
	chip_material.albedo_color = Color("ba9f58")
	chip_material.metallic = 0.8
	chip.material_override = chip_material
	card_visual.add_child(chip)
	var card_label := Label3D.new()
	card_label.text = "ARMORY KEYCARD"
	card_label.font_size = 28
	card_label.pixel_size = 0.002
	card_label.position.y = 0.18
	card_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card_visual.add_child(card_label)
	reader = Node3D.new()
	add_child(reader)
	reader.global_transform = door.get_closed_transform() * Transform3D(Basis.IDENTITY, Vector3(door.width + 0.14, 1.3, 0.15))
	reader_light = StandardMaterial3D.new()
	reader_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var reader_mesh := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.12, 0.22, 0.035)
	reader_mesh.mesh = plate
	reader_mesh.material_override = reader_light
	reader.add_child(reader_mesh)
	reader_label = Label3D.new()
	reader_label.font_size = 28
	reader_label.pixel_size = 0.002
	reader_label.position.y = 0.3
	reader_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reader.add_child(reader_label)
	alarm_player = AudioStreamPlayer3D.new()
	alarm_player.stream = get_alarm_stream()
	alarm_player.volume_db = -13.0
	alarm_player.unit_size = 12.0
	alarm_player.max_distance = 100.0
	reader.add_child(alarm_player)

func hint_for(peer_id: int, fighter: CharacterBody3D) -> String:
	if not can_interact(peer_id, fighter): return ""
	if keycard_available and fighter.global_position.distance_to(card_position) <= INTERACT_DISTANCE:
		return "TAKE ARMORY KEYCARD"
	if fighter.global_position.distance_to(door_center()) > INTERACT_DISTANCE: return ""
	if is_unlocked: return "ARMORY OPEN"
	return "UNLOCK ARMORY" if keycard_owner == peer_id else "ARMORY · KEYCARD REQUIRED"

func can_interact(peer_id: int, fighter: CharacterBody3D) -> bool:
	return peer_id > 0 and is_instance_valid(door) and is_instance_valid(fighter) and fighter.get("phase") == "ground" and fighter.global_position.is_finite()

func is_host() -> bool:
	return bool(arena.authority) if is_instance_valid(arena) else configured_authority

func door_center() -> Vector3:
	return door.get_closed_transform() * Vector3(door.width * 0.5, 0.8, 0)

func try_interact(peer_id: int, fighter: CharacterBody3D) -> bool:
	if not is_host() or not can_interact(peer_id, fighter): return false
	if keycard_available and fighter.global_position.distance_to(card_position) <= INTERACT_DISTANCE:
		keycard_available = false
		keycard_owner = peer_id
		refresh_visuals()
		return true
	if fighter.global_position.distance_to(door_center()) > INTERACT_DISTANCE: return false
	if not is_unlocked and keycard_owner == peer_id:
		# Commit state before emitting so simultaneous/reentrant requests cannot reward twice.
		is_unlocked = true
		keycard_owner = 0
		alarm_left = ALARM_DURATION
		set_door_state(true)
		refresh_visuals()
		unlocked.emit(peer_id)
	# Consume attempts at the door even when locked, preventing the regular toggle path.
	return true

func release_keycard(peer_id: int, at: Vector3) -> void:
	if not is_host() or keycard_owner != peer_id or not at.is_finite(): return
	keycard_owner = 0
	keycard_available = true
	card_position = at
	refresh_visuals()

func reset_round(keycard_position: Vector3) -> void:
	if not is_host() or not keycard_position.is_finite(): return
	keycard_owner = 0
	keycard_available = true
	is_unlocked = false
	alarm_left = 0.0
	card_position = keycard_position
	set_door_state(false, true)
	refresh_visuals()

func pack_state() -> Dictionary:
	sequence += 1
	return {"seq": sequence, "owner": keycard_owner, "available": keycard_available,
		"open": is_unlocked, "alarm": alarm_left, "card": card_position}

func apply_state(state: Dictionary) -> void:
	if is_host() or not is_instance_valid(door): return
	if not state.get("seq") is int or state.seq <= last_received: return
	if not state.get("card") is Vector3 or not state.card.is_finite(): return
	if not state.get("owner") is int or not state.get("open") is bool or not state.get("available") is bool: return
	var alarm: float = float(state.get("alarm", 0.0))
	if not is_finite(alarm): return
	var was_unlocked := is_unlocked
	var first_snapshot := last_received < 0
	last_received = state.seq
	keycard_owner = state.owner
	keycard_available = state.available
	is_unlocked = state.open
	alarm_left = clampf(alarm, 0.0, ALARM_DURATION) if is_unlocked else 0.0
	card_position = state.card
	if first_snapshot or was_unlocked != is_unlocked:
		set_door_state(is_unlocked, first_snapshot or not is_unlocked)
	refresh_visuals()

func set_door_state(opened: bool, immediate: bool = false) -> void:
	if door_motion and door_motion.is_running(): door_motion.kill()
	if door.tween and door.tween.is_running(): door.tween.kill()
	door.is_open = opened
	var target: float = door.closed_angle + (door.open_angle if opened else 0.0)
	door.collider.set_deferred("disabled", opened)
	if immediate:
		door.rotation.y = target
	else:
		door_motion = create_tween()
		door_motion.tween_property(door, "rotation:y", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func refresh_visuals() -> void:
	card_visual.visible = keycard_available
	card_visual.global_position = card_position
	reader_label.text = "ARMORY OPEN" if is_unlocked else "ARMORY · KEYCARD"
	reader_light.albedo_color = Color("71dfad") if is_unlocked else Color("ef805e")
	if alarm_left > 0.0:
		if not alarm_player.playing: alarm_player.play()
	else:
		alarm_player.stop()

func _process(delta: float) -> void:
	if not is_instance_valid(reader): return
	visual_time += delta
	card_visual.rotation.y = visual_time * 0.65
	card_visual.global_position.y = card_position.y + sin(visual_time * 2.5) * 0.025
	if alarm_left <= 0.0: return
	alarm_left = maxf(0.0, alarm_left - delta)
	reader_light.albedo_color = Color("ff4433") if sin(visual_time * 12.0) > 0.0 else Color("552419")
	if alarm_left == 0.0: refresh_visuals()

static func get_alarm_stream() -> AudioStreamWAV:
	if alarm_stream: return alarm_stream
	# Keep a single shared recording. Raw WAV loading also supports the isolated pre-import check.
	var source: AudioStreamWAV
	if ResourceLoader.exists(ALARM_PATH): source = load(ALARM_PATH) as AudioStreamWAV
	if not source: source = AudioStreamWAV.load_from_file(ALARM_PATH)
	assert(source != null, "Missing recorded armory alarm")
	alarm_stream = source.duplicate() as AudioStreamWAV
	alarm_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	alarm_stream.loop_begin = 0
	alarm_stream.loop_end = alarm_stream.data.size() / 2
	return alarm_stream
