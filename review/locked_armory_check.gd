extends SceneTree

const Armory = preload("res://locked_armory.gd")
const Door = preload("res://door.gd")

class TestFighter extends CharacterBody3D:
	var phase := "ground"

var checks := {}
var world: Node3D

func _initialize() -> void:
	run.call_deferred()

func make_armory(is_host: bool):
	var door := Door.new()
	world.add_child(door)
	var armory := Armory.new()
	world.add_child(armory)
	armory.configure(door, Vector3(8, 0.5, 0), is_host)
	return armory

func wire_copy(host_armory) -> Dictionary:
	return bytes_to_var(var_to_bytes(host_armory.pack_state()))

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	world = Node3D.new()
	root.add_child(world)
	var host_armory = make_armory(true)
	var client_armory = make_armory(false)
	var player := TestFighter.new()
	root.add_child(player)
	var events := {"unlocks": 0}
	host_armory.unlocked.connect(func(_peer): events.unlocks += 1)
	await physics_frame
	await physics_frame
	var line := PhysicsRayQueryParameters3D.create(Vector3(0.6, 1, -2), Vector3(0.6, 1, 2))
	var closed_hit := world.get_world_3d().direct_space_state.intersect_ray(line)
	checks.closed_door_blocks_bullets = not closed_hit.is_empty()
	player.position = Vector3(30, 0, 0)
	checks.far_interaction_ignored = not host_armory.try_interact(1, player)
	player.position = Vector3(0, 0.5, 0)
	checks.locked_without_card = host_armory.try_interact(1, player) and not host_armory.is_unlocked and events.unlocks == 0
	checks.locked_hint = host_armory.hint_for(1, player).contains("KEYCARD REQUIRED")
	checks.client_cannot_unlock = not client_armory.try_interact(1, player)
	player.position = Vector3(8, 0.5, 0)
	player.phase = "dead"
	checks.dead_cannot_collect = not host_armory.try_interact(1, player)
	player.phase = "ground"
	checks.card_collected_once = host_armory.try_interact(1, player) and host_armory.keycard_owner == 1 and not host_armory.try_interact(2, player)
	var collected := wire_copy(host_armory)
	client_armory.apply_state(collected)
	checks.card_synced = client_armory.keycard_owner == 1 and not client_armory.card_visual.visible
	host_armory.release_keycard(2, Vector3(6, 0.5, 0))
	checks.wrong_player_cannot_drop = host_armory.keycard_owner == 1
	host_armory.release_keycard(1, Vector3(6, 0.5, 0))
	checks.card_recoverable = host_armory.keycard_available and host_armory.keycard_owner == 0 and host_armory.card_position == Vector3(6, 0.5, 0)
	player.position = Vector3(6, 0.5, 0)
	host_armory.try_interact(2, player)
	player.position = Vector3(0, 0.5, 0)
	host_armory.try_interact(1, player)
	checks.only_card_owner_unlocks = not host_armory.is_unlocked
	checks.unlock_hint = host_armory.hint_for(2, player) == "UNLOCK ARMORY"
	host_armory.try_interact(2, player)
	checks.unlock_alarm_and_reward = host_armory.is_unlocked and host_armory.alarm_player.playing and events.unlocks == 1
	host_armory._process(1.0)
	var remaining: float = host_armory.alarm_left
	host_armory.try_interact(2, player)
	host_armory.try_interact(1, player)
	checks.no_duplicate_rewards_or_alarm = events.unlocks == 1 and host_armory.alarm_left == remaining
	var opened := wire_copy(host_armory)
	client_armory.apply_state(opened)
	checks.open_and_alarm_synced = client_armory.is_unlocked and client_armory.door.is_open and client_armory.alarm_player.playing
	client_armory.apply_state(collected)
	checks.stale_snapshot_rejected = client_armory.is_unlocked and client_armory.keycard_owner == 0
	await create_timer(0.5).timeout
	checks.door_physically_opens = absf(host_armory.door.rotation.y - host_armory.door.closed_angle) > 1.5 and host_armory.door.collider.disabled
	# Other replicas occupy this fixture's origin, so exclude their door bodies from this ray.
	line.exclude = [client_armory.door.collider.get_parent().get_rid()]
	var open_hit := world.get_world_3d().direct_space_state.intersect_ray(line)
	checks.open_door_clears_entry = open_hit.is_empty()
	host_armory._process(20.0)
	checks.alarm_stops = host_armory.alarm_left == 0 and not host_armory.alarm_player.playing
	var late_join = make_armory(false)
	late_join.apply_state(wire_copy(host_armory))
	checks.late_join_no_old_alarm = late_join.is_unlocked and not late_join.alarm_player.playing
	host_armory.reset_round(Vector3(10, 0.5, 0))
	client_armory.apply_state(wire_copy(host_armory))
	await process_frame
	checks.rematch_relocks = not host_armory.is_unlocked and not client_armory.is_unlocked and host_armory.keycard_available and client_armory.card_visual.visible and not host_armory.door.collider.disabled
	player.position = Vector3(10, 0.5, 0)
	host_armory.try_interact(1, player)
	player.position = Vector3(0, 0.5, 0)
	host_armory.try_interact(1, player)
	checks.new_round_rewards_once = events.unlocks == 2
	host_armory.reset_round(Vector3(8, 0.5, 0))
	await create_timer(0.6).timeout
	checks.reset_cancels_opening_tween = host_armory.door.rotation.y == host_armory.door.closed_angle and not host_armory.door.collider.disabled
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	print("ARMORY_REVIEW ", JSON.stringify({"passed": passed, "checks": checks}))
	for node in root.get_children(): node.queue_free()
	await process_frame
	quit(0 if passed else 1)
