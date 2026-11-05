extends "res://yard.gd"

const Fighter = preload("res://arena_player.gd")
const Radar = preload("res://yard_radar.gd")
const CARBINE := preload("res://assets/provided/fps_animated_carbine.glb")
const VEST := preload("res://assets/provided/modern_tactical_vest__plate_carrier.glb")
const RIFLE_AUDIO := {
	"ar15_close_01_responsive.wav": preload("res://audio/rifle/ar15_close_01_responsive.wav"),
	"ar15_close_02_responsive.wav": preload("res://audio/rifle/ar15_close_02_responsive.wav"),
	"ar15_close_01.wav": preload("res://audio/rifle/ar15_close_01.wav"),
	"ar15_close_02.wav": preload("res://audio/rifle/ar15_close_02.wav"),
	"ar15_mid_01.wav": preload("res://audio/rifle/ar15_mid_01.wav"),
	"ar15_mid_02.wav": preload("res://audio/rifle/ar15_mid_02.wav"),
	"ar15_magazine_out.wav": preload("res://audio/rifle/ar15_magazine_out.wav"),
	"ar15_magazine_in.wav": preload("res://audio/rifle/ar15_magazine_in.wav"),
	"ar15_bolt_release.wav": preload("res://audio/rifle/ar15_bolt_release.wav"),
}
const PORT := 27845
const KINDS := ["RIFLE", "AMMO", "MEDKIT", "ARMOUR", "GRENADE", "BACKPACK"]
var fighters: Dictionary = {}
var loot: Dictionary = {}
var loot_nodes: Dictionary = {}
var active := false
var authority := true
var local_id := 1
var clock := 0.0
var mode := 0
var zone_center := Vector3.ZERO
var zone_radius := 145.0
var zone_start := 145.0
var arena_bounds := AABB(Vector3(-150, 0, -150), Vector3(300, 40, 300))
var menu: PanelContainer
var menu_box: VBoxContainer
var address: LineEdit
var mode_select: OptionButton
var status: Label
var feed: Label
var radar: Control
var third_person := true
var look_yaw := PI
var look_pitch := 0.0
var snapshot_timer := 0.0
var input_timer := 0.0
var zone_timer := 0.0
var end_text := ""
var loot_serial := 0
var tone: AudioStreamPlayer
var minimap_texture: Texture2D
var viewmodel: Node3D
var recoil := 0.0
var fx_nodes: Array[Dictionary] = []
var throwables: Array[Dictionary] = []
var review_mode := false
var aircraft: Node3D
var sky_audio: Node
var loot_dirty := false
var use_preview_sky_audio := false
var zone_wall: MeshInstance3D
var outside_tint: ColorRect
var gun_animator: AnimationPlayer
var gun_previous_time := 6.0
var shot_index := 0
var crates: Array[Node3D] = []
var grenade_serial := 0
var remote_grenades: Dictionary = {}
var hit_flash := 0.0
var frame_samples: Array[float] = []
var measure_frames := false
var frame_hitches: Array[Dictionary] = []
var mobile_hud: Control
var combat_effects: CanvasLayer
var flight_time := 0.0
var main_rotor: Node3D
var tail_rotor: Node3D
var suspension_lines: Dictionary = {}
const TRAINING_ID := 900001
var training_enabled := false
var training_anchor := Vector3.ZERO
var training_goal := Vector3.ZERO
var training_timer := 0.0
var target_scan := 0.0
var target_under_aim := false
var reticle_scale := 1.0

func _ready() -> void:
	build_doors()
	find_bounds()
	build_interface()
	build_aircraft()
	build_zone()
	combat_effects = preload("res://combat_effects.gd").new()
	add_child(combat_effects)
	combat_effects.setup(self)
	build_crates.call_deferred()
	var environment: Environment = $WorldEnvironment.environment
	environment.sky = Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6f9bbf")
	sky_material.sky_horizon_color = Color("b7c9d4")
	environment.sky.sky_material = sky_material
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	sky_audio = preload("res://sky_audio.gd").new()
	add_child(sky_audio)
	multiplayer.peer_connected.connect(peer_joined)
	multiplayer.peer_disconnected.connect(peer_left)
	multiplayer.connected_to_server.connect(connected)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(server_left)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.get_name() != "headless" and not radar.hd_map: bake_map.call_deferred()
	var args := OS.get_cmdline_user_args()
	if "--arena-review" in args:
		review_mode = true
		practice()
		arena_review.call_deferred()
	elif "--test-host" in args:
		review_mode = true
		host_game()
		connection_review.call_deferred()
	elif "--test-client" in args:
		review_mode = true
		address.text = "127.0.0.1"
		join_game()
		connection_review.call_deferred()
	elif "--capture-arena" in args:
		review_mode = true
		practice()
		capture_arena.call_deferred()
	elif "--round-review" in args:
		review_mode = true
		measure_frames = DisplayServer.get_name() != "headless"
		practice()
		round_review.call_deferred()
	elif "--capture-menu" in args:
		capture_menu.call_deferred()
	elif "--flight-review" in args:
		review_mode = true
		practice()
		flight_review.call_deferred()
	elif "--bot-review" in args:
		review_mode = true
		practice()
		bot_review.call_deferred()
	elif "--shooting-practice" in args:
		shooting_practice.call_deferred()
	elif "--safety-review" in args:
		review_mode = true
		practice()
		safety_review.call_deferred()
	elif "--portable-review" in args:
		review_mode = true
		practice()
		portable_review.call_deferred()

func build_aircraft() -> void:
	aircraft = Node3D.new()
	add_child(aircraft)
	aircraft.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	update_flight(0)
	var packed = load("res://assets/provided/sa342m_gazelle.glb") as PackedScene
	if not packed: return
	var model: Node3D = packed.instantiate()
	aircraft.add_child(model)
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ratio := 10.0 / maxf(bounds.size.x, bounds.size.z)
	model.scale = Vector3.ONE * ratio
	model.position = Vector3.ZERO
	var rotor_mesh := model.find_child("Object_78", true, false) as MeshInstance3D
	if rotor_mesh:
		main_rotor = Node3D.new()
		model.add_child(main_rotor)
		main_rotor.global_position = model.to_global(Vector3(0, 2.3, 0))
		rotor_mesh.reparent(main_rotor, true)
	var tail_mesh := model.find_child("Object_44", true, false) as MeshInstance3D
	if tail_mesh:
		tail_rotor = Node3D.new()
		model.add_child(tail_rotor)
		tail_rotor.global_position = model.to_global(Vector3(0.126, 1.086, -8.433))
		tail_mesh.reparent(tail_rotor, true)

func build_zone() -> void:
	zone_wall = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1
	cylinder.bottom_radius = 1
	cylinder.height = 1
	cylinder.radial_segments = 128
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	zone_wall.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.12, 0.7, 0.95, 0.12)
	zone_wall.material_override = material
	zone_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone_wall.position = zone_center + Vector3.UP * 30
	add_child(zone_wall)

func build_crates() -> void:
	await get_tree().physics_frame
	var spots := [NORTH_ENTRY + Vector3(7, 0, 17), NORTH_ENTRY + Vector3(-7, 0, 29)]
	for x in [-0.25, 0.0, 0.25]:
		for z in [-0.22, 0.22]: spots.append(zone_center + Vector3(arena_bounds.size.x * x, 0, arena_bounds.size.z * z))
	for at in spots:
		var point := floor_at(at)
		if not point.is_finite(): continue
		var crate = preload("res://loot_crate.gd").new()
		crate.position = point - Vector3.UP * 0.37
		add_child(crate)
		crates.append(crate)

func find_bounds() -> void:
	var first := true
	for mesh in $Map.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		arena_bounds = box if first else arena_bounds.merge(box)
		first = false
	zone_center = arena_bounds.get_center()
	zone_center.y = 0
	zone_start = maxf(arena_bounds.size.x, arena_bounds.size.z) * 0.55
	zone_radius = zone_start
	for crate in crates: crate.set_open(false)
	print("ARENA_BOUNDS ", arena_bounds)

func build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	outside_tint = ColorRect.new()
	outside_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outside_tint.color = Color(0.4, 0.03, 0.03, 0.15)
	outside_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outside_tint.hide()
	layer.add_child(outside_tint)
	feed = Label.new()
	feed.position = Vector2(22, 195)
	feed.add_theme_constant_override("outline_size", 5)
	layer.add_child(feed)
	var aim_widget := preload("res://aim_ring.gd").new()
	aim_widget.arena = self
	layer.add_child(aim_widget)
	radar = Radar.new()
	radar.arena = self
	layer.add_child(radar)
	mobile_hud = preload("res://mobile_hud.gd").new()
	mobile_hud.setup(self)
	layer.add_child(mobile_hud)
	menu = PanelContainer.new()
	menu.position = Vector2(32, 32)
	menu.custom_minimum_size = Vector2(420, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.065, 0.10, 0.97)
	panel_style.border_color = Color("43d9ea")
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(20)
	menu.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(menu)
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	menu.add_child(menu_box)
	var title := Label.new()
	title.text = "INDUSTRIAL YARD / DROP DUEL"
	title.add_theme_font_size_override("font_size", 24)
	menu_box.add_child(title)
	var description := Label.new()
	description.text = "Jump. Find supplies. Hunt your opponent.\nTwo players · One yard · Respawns · Safe zone"
	menu_box.add_child(description)
	mode_select = OptionButton.new()
	for text in ["Score match / 5 minutes", "First to 10 eliminations", "Practice / no score limit"]: mode_select.add_item(text)
	menu_box.add_child(mode_select)
	add_button("PRACTICE", practice)
	add_button("SHOOTING PRACTICE · TRAINING ROBOT", shooting_practice)
	add_button("HOST TWO-PLAYER MATCH", host_game)
	address = LineEdit.new()
	address.placeholder_text = "Host computer's IP address"
	address.text = "127.0.0.1"
	menu_box.add_child(address)
	add_button("JOIN HOST", join_game)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 370
	status.text = "Same Wi-Fi: enter the host computer's address to join.\nOnline invitations are not available yet."
	menu_box.add_child(status)
	add_button("RESUME", resume_game)
	add_button("QUIT", func(): get_tree().quit())
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.position = NORTH_ENTRY + Vector3(0, 1.7, 0)
	cam.rotation.y = PI
	add_child(cam)
	cam.make_current()
	camera = cam
	build_viewmodel()

func build_viewmodel() -> void:
	viewmodel = CARBINE.instantiate()
	camera.add_child(viewmodel)
	viewmodel.scale = Vector3.ONE * 0.35
	viewmodel.position = Vector3(0.12, -0.38, -0.48)
	viewmodel.rotation.y = PI
	var animators = viewmodel.find_children("*", "AnimationPlayer", true, false)
	if not animators.is_empty():
		gun_animator = animators[0]
		gun_animator.play("allanims")
		gun_animator.seek(6.0, true)
		gun_animator.pause()
	for mesh in viewmodel.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewmodel.hide()

func add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	menu_box.add_child(button)

func clear_round() -> void:
	training_enabled = false
	if viewmodel: viewmodel.hide()
	if zone_wall: zone_wall.hide()
	outside_tint.hide()
	for crate in crates: crate.set_open(false)
	for body in fighters.values(): body.free()
	fighters.clear()
	for node in loot_nodes.values(): node.free()
	loot.clear()
	loot_nodes.clear()
	for item in throwables: if is_instance_valid(item.node): item.node.queue_free()
	throwables.clear()
	for grenade in remote_grenades.values(): grenade.node.queue_free()
	remote_grenades.clear()
	for fx in fx_nodes: if is_instance_valid(fx.node): fx.node.queue_free()
	fx_nodes.clear()
	clock = 0.0
	flight_time = 0
	update_flight(0)
	for line in suspension_lines.values(): line.queue_free()
	suspension_lines.clear()
	zone_timer = 0.0
	end_text = ""
	zone_radius = zone_start
	for door in doors:
		if door.is_open: door.toggle(Vector3.INF)

func disconnect_session() -> void:
	active = false
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	clear_round()

func practice() -> void:
	disconnect_session()
	authority = true
	local_id = 1
	mode = 2
	start_round()
	training_enabled = not review_mode
	message("Practice: ride the rope across the yard. Space to release, Space again to deploy.")

func shooting_practice() -> void:
	practice()
	training_enabled = true
	var body = fighters[local_id]
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
	body.velocity = Vector3.ZERO
	body.phase = "ground"
	body.weapon = true
	body.magazine = 30
	body.ammo = 240
	look_yaw = PI
	look_pitch = 0
	body.reset_physics_interpolation()
	place_training_robot()
	message("Training robot ahead. Practise shooting; it will respawn. B: bring robot nearby.")

func place_training_robot() -> void:
	if not fighters.has(local_id): return
	var player_body = fighters[local_id]
	var ahead := Basis(Vector3.UP, look_yaw) * Vector3.FORWARD
	var spot: Vector3 = floor_at(player_body.position + ahead * 8)
	if not spot.is_finite(): return
	if not fighters.has(TRAINING_ID):
		spawn_fighter(TRAINING_ID)
		var tag := Label3D.new()
		tag.name = "TrainingTag"
		tag.text = "TRAINING ROBOT"
		tag.font_size = 32
		tag.pixel_size = 0.003
		tag.position.y = 2.1
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		fighters[TRAINING_ID].add_child(tag)
	var bot = fighters[TRAINING_ID]
	bot.drop(spot)
	bot.phase = "ground"
	bot.protection = 0
	bot.weapon = false
	var tag := bot.get_node("TrainingTag") as Label3D
	tag.text = "TRAINING ROBOT"
	bot.reset_physics_interpolation()
	training_anchor = spot
	training_goal = spot
	training_timer = 1.2

func update_training(delta: float) -> void:
	if not training_enabled or not fighters.has(TRAINING_ID): return
	var bot = fighters[TRAINING_ID]
	if bot.phase == "dead": return
	training_timer -= delta
	if training_timer <= 0 or bot.position.distance_to(training_goal) < 0.5:
		training_timer = 2.5
		var side := Vector3.RIGHT if sin(clock * 0.7) > 0 else Vector3.LEFT
		var next := floor_at(training_anchor + side * 2.5)
		if next.is_finite() and absf(next.y - training_anchor.y) < 1: training_goal = next
	var direction: Vector3 = training_goal - bot.position
	direction.y = 0
	var heading := atan2(-direction.x, -direction.z) if direction.length() > 0.3 else 0.0
	bot.command = {"move": Vector2(0, -0.4) if direction.length() > 0.4 else Vector2.ZERO, "yaw": heading, "pitch": 0.0, "run": false, "jump": false, "fire": false}
	var tag := bot.get_node_or_null("TrainingTag") as Label3D
	if tag: tag.text = "TRAINING ROBOT · %s HP" % ceili(bot.hp)

func host_game() -> void:
	disconnect_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 1)
	if error != OK:
		status.text = "Could not host on port %s (error %s)." % [PORT, error]
		return
	multiplayer.multiplayer_peer = peer
	authority = true
	local_id = 1
	mode = mode_select.selected
	start_round()
	message("Room open. Your friend can join using: %s" % ", ".join(local_addresses()))
	status.text = feed.text

func local_addresses() -> PackedStringArray:
	var ips := PackedStringArray()
	for ip in IP.get_local_addresses():
		if "." in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): ips.append(ip)
	return ips

func join_game() -> void:
	if address.text.strip_edges().is_empty():
		status.text = "Enter the host computer's IP address."
		return
	disconnect_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.text.strip_edges(), PORT)
	if error != OK:
		status.text = "Could not start connection (error %s)." % error
		return
	authority = false
	multiplayer.multiplayer_peer = peer
	status.text = "Connecting…"

func connected() -> void:
	local_id = multiplayer.get_unique_id()
	active = true
	menu.hide()
	if not review_mode: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	message("Connected. Space to jump, then Space to deploy your parachute.")

func connection_failed() -> void:
	status.text = "Connection failed. Check the host address, Wi-Fi and host firewall."
	menu.show()

func server_left() -> void:
	active = false
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "The host disconnected. You can reconnect or practise."

func peer_joined(id: int) -> void:
	if not authority: return
	spawn_fighter(id)
	receive_loot.rpc_id(id, loot)
	message("Your opponent joined the yard.")
	send_snapshot()

func peer_left(id: int) -> void:
	if fighters.has(id):
		fighters[id].queue_free()
		fighters.erase(id)
	message("Your opponent disconnected. You can continue practising.")

func start_round() -> void:
	active = true
	spawn_fighter(1)
	seed_loot()
	menu.hide()
	if not review_mode: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func spawn_fighter(id: int) -> void:
	var body = Fighter.new()
	body.peer_id = id
	if not authority and id != local_id: body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.name = "Fighter_%s" % id
	add_child(body)
	fighters[id] = body
	body.drop(drop_position(id))
	body.yaw = PI

func drop_position(id: int) -> Vector3:
	var offset := -1.2 if id == 1 else 1.2
	return aircraft.to_global(Vector3(offset, -7.0, 0))

func floor_at(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, arena_bounds.end.y + 10, point.z), Vector3(point.x, arena_bounds.position.y - 10, point.z))
	query.collision_mask = 1
	var excluded: Array[RID] = []
	for fighter in fighters.values(): excluded.append(fighter.get_rid())
	query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position + Vector3.UP * 0.4 if not hit.is_empty() else Vector3.INF

func seed_loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 53417
	for i in range(54):
		var p := zone_center + Vector3(rng.randf_range(-arena_bounds.size.x * 0.4, arena_bounds.size.x * 0.4), 0, rng.randf_range(-arena_bounds.size.z * 0.4, arena_bounds.size.z * 0.4))
		p = floor_at(p)
		if p.is_finite(): add_loot(i % KINDS.size(), p)
	# A reliable nearby supply route also serves movement and pickup tests.
	for i in range(6):
		var p := floor_at(NORTH_ENTRY + Vector3(0, 0, 4 + i * 2))
		if p.is_finite(): add_loot(i, p)

func add_loot(kind: int, at: Vector3) -> int:
	loot_dirty = true
	loot_serial += 1
	loot[loot_serial] = {"kind": kind, "p": at, "ready": 0.0}
	make_loot_visual(loot_serial)
	return loot_serial

func make_loot_visual(id: int) -> void:
	var node := Node3D.new()
	node.position = loot[id].p
	add_child(node)
	loot_nodes[id] = node
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.25, 0.35)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = [Color("ffbd59"), Color("e5cf84"), Color("55e4b5"), Color("76a3ff"), Color("df8072"), Color("b98cf3")][loot[id].kind]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.4
	mesh.material_override = mat
	node.add_child(mesh)
	if loot[id].kind in [0, 3]:
		var packed := CARBINE if loot[id].kind == 0 else VEST
		if packed:
			var model: Node3D = packed.instantiate()
			node.add_child(model)
			var box_bounds := AABB()
			var first := true
			for part in model.find_children("*", "MeshInstance3D", true, false):
				var resource_label: String = String(part.name) + String(part.mesh.resource_name)
				if part.mesh.get_surface_count() > 0 and part.mesh.surface_get_material(0): resource_label += part.mesh.surface_get_material(0).resource_name
				if loot[id].kind == 0 and "arm" in resource_label.to_lower():
					part.hide()
					continue
				var part_bounds: AABB = model.global_transform.affine_inverse() * part.global_transform * part.get_aabb()
				box_bounds = part_bounds if first else box_bounds.merge(part_bounds)
				first = false
				part.visibility_range_end = 45
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ratio := 0.85 / maxf(box_bounds.size.length(), 0.01)
			model.scale = Vector3.ONE * ratio
			model.position = -box_bounds.get_center() * ratio
			model.rotation.z = PI * 0.5 if loot[id].kind == 0 else 0.0
			mesh.hide()
	var label := Label3D.new()
	label.text = KINDS[loot[id].kind]
	label.position.y = 0.55
	label.font_size = 24
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 22.0
	node.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if not active: return
			menu.visible = not menu.visible
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED
			return
		if not active or menu.visible: return
		match event.physical_keycode:
			KEY_V: third_person = not third_person
			KEY_M: radar.toggle_map()
			KEY_TAB:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			KEY_SPACE: request_action("jump")
			KEY_E: request_action("interact")
			KEY_R: request_action("reload")
			KEY_H: request_action("heal")
			KEY_G: request_action("grenade")
			KEY_F5: request_action("rematch")
			KEY_B:
				if training_enabled: place_training_robot()
	if not active or menu.visible: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not review_mode:
		look_yaw -= event.relative.x * 0.002
		look_pitch = clampf(look_pitch - event.relative.y * 0.002, -1.45, 1.45)

func resume_game() -> void:
	if not active: return
	menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func controls() -> Dictionary:
	var axis := Vector2.ZERO
	var enabled: bool = not menu.visible and not radar.expanded and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or review_mode)
	if enabled:
		axis = Vector2(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)), int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	var command := {"move": axis.limit_length(), "yaw": look_yaw, "pitch": look_pitch, "run": enabled and Input.is_physical_key_pressed(KEY_SHIFT), "jump": false, "crouch": enabled and Input.is_physical_key_pressed(KEY_CTRL), "aim": enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "fire": enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)}
	command.third_person = third_person
	command.pitch = clampf(look_pitch + recoil, -1.45, 1.45)
	return mobile_hud.merge_controls(command) if mobile_hud else command

func _physics_process(delta: float) -> void:
	if not active: return
	update_flight(delta)
	for rider in fighters:
		if fighters[rider].phase == "helicopter": fighters[rider].position = drop_position(rider)
	var command := controls()
	if fighters.has(local_id):
		var old_jump: bool = fighters[local_id].command.get("jump", false)
		fighters[local_id].command = command
		fighters[local_id].command.jump = old_jump
	if authority:
		update_training(delta)
		if end_text.is_empty() and (mode == 2 or not multiplayer.get_peers().is_empty()): clock += delta
		zone_radius = zone_start if mode == 2 else lerpf(zone_start, 22.0, clampf((clock - 35.0) / 210.0, 0, 1))
		for id in fighters:
			var body = fighters[id]
			if not end_text.is_empty(): continue
			if body.phase == "helicopter":
				body.position = drop_position(id)
				body.velocity = Vector3.ZERO
			if body.phase == "fall":
				var ground := floor_at(body.position)
				if ground.is_finite() and body.position.y - ground.y < 42:
					body.phase = "parachute"
					body.velocity.y = maxf(body.velocity.y, -7)
			body.step(delta)
			if body.phase == "dead":
				if body.respawn_left <= 0:
					if id == TRAINING_ID: place_training_robot()
					else: body.drop(drop_position(id))
				continue
			if body.position.y < arena_bounds.position.y - 15: damage(id, 1000, 0)
			elif body.hp <= 0: damage(id, 1000, 0)
			if body.command.get("fire", false): shoot(id)
		zone_timer += delta
		if zone_timer >= 1.0:
			zone_timer -= 1.0
			for id in fighters:
				var body = fighters[id]
				var distance := Vector2(body.position.x - zone_center.x, body.position.z - zone_center.z).length()
				if mode != 2 and body.phase == "ground" and distance > zone_radius: damage(id, 8, 0)
		update_throwables(delta)
		if training_enabled and not fighters.has(TRAINING_ID) and fighters[local_id].phase == "ground": place_training_robot()
		for id in loot:
			if loot[id].ready > 0 and clock >= loot[id].ready:
				loot[id].ready = 0.0
				loot_dirty = true
				loot_nodes[id].show()
		if mode == 0 and clock >= 300 and end_text.is_empty(): finish_match()
		snapshot_timer += delta
		if snapshot_timer >= 0.05:
			snapshot_timer = 0
			send_snapshot()
	else:
		if fighters.has(local_id) and end_text.is_empty(): fighters[local_id].step(delta)
		input_timer += delta
		if input_timer >= 0.033:
			input_timer = 0
			submit_input.rpc_id(1, command)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(command: Dictionary) -> void:
	if not authority: return
	var id := multiplayer.get_remote_sender_id()
	if not fighters.has(id): return
	if not command.get("move", Vector2.ZERO) is Vector2: return
	var axis: Vector2 = command.move
	var yaw_value: float = float(command.get("yaw", 0))
	var pitch_value: float = float(command.get("pitch", 0))
	if not axis.is_finite() or not is_finite(yaw_value) or not is_finite(pitch_value): return
	command.move = axis.limit_length()
	command.yaw = wrapf(yaw_value, -PI, PI)
	command.pitch = clampf(pitch_value, -1.45, 1.45)
	command.jump = fighters[id].command.get("jump", false)
	fighters[id].command = command

func request_action(action: String) -> void:
	if authority: perform_action(local_id, action)
	else: submit_action.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable", 2)
func submit_action(action: String) -> void:
	if authority: perform_action(multiplayer.get_remote_sender_id(), action)

func perform_action(id: int, action: String) -> void:
	if not fighters.has(id): return
	var body = fighters[id]
	if action == "rematch":
		if id == 1 and not end_text.is_empty():
			clock = 0
			end_text = ""
			for peer in fighters:
				fighters[peer].score = 0
				fighters[peer].drop(drop_position(peer))
			for crate in crates: crate.set_open(false)
			for item in loot:
				loot[item].ready = 0.0
				loot_nodes[item].show()
			loot_dirty = true
		return
	if body.phase == "dead" or not end_text.is_empty(): return
	match action:
		"jump":
			if body.phase == "helicopter":
				body.phase = "fall"
				body.velocity = aircraft.basis * Vector3(0, 0, 17)
			elif body.phase == "fall":
				body.phase = "parachute"
				body.velocity.y = maxf(body.velocity.y, -7)
			elif body.phase == "ground": body.command.jump = true
		"reload":
			if body.weapon and body.magazine < 30 and body.ammo > 0 and body.reload_left <= 0: body.reload_left = 1.8
		"heal":
			if body.medkits > 0 and body.hp < 100:
				body.medkits -= 1
				body.hp = minf(100, body.hp + 50)
		"interact": interact(id)
		"grenade": throw_grenade(id)

func interact(id: int) -> void:
	var body = fighters[id]
	if body.phase != "ground": return
	for crate in crates:
		if not crate.opened and body.position.distance_to(crate.position) < 2.6:
			crate.set_open(true)
			for i in range(3):
				add_loot(i, crate.position + Vector3(-0.6 + i * 0.6, 0.85, 1.0))
			return
	var nearest := -1
	var gap := 2.8
	for item in loot:
		if loot[item].ready > 0: continue
		var distance: float = body.position.distance_to(loot[item].p)
		if distance < gap:
			gap = distance
			nearest = item
	if nearest >= 0:
		var capacity := 240 if body.backpack else 120
		match loot[nearest].kind:
			0:
				body.weapon = true
				body.magazine = 30
				body.ammo = mini(capacity, body.ammo + 60)
			1: body.ammo = mini(capacity, body.ammo + 60)
			2: body.medkits = mini(4 if body.backpack else 2, body.medkits + 1)
			3: body.armor = 75
			4: body.grenades = mini(4 if body.backpack else 2, body.grenades + 1)
			5: body.backpack = true
		loot[nearest].ready = clock + 35
		loot_dirty = true
		loot_nodes[nearest].hide()
		return
	for door in doors:
		if body.position.distance_to(door.to_global(Vector3(door.width * 0.5, 0, 0))) < 2.8:
			if door.is_open:
				for other in fighters.values():
					var local: Vector3 = door.get_closed_transform().affine_inverse() * other.position
					if other.phase != "dead" and absf(local.z) < 0.65 and local.x > -0.35 and local.x < door.width + 0.35: return
			door.toggle(body.position)
			return

func shot_eye(body: CharacterBody3D) -> Vector3:
	return body.global_position + Vector3.UP * (1.05 if body.crouched else 1.64)

func shoulder_camera(eye: Vector3, view: Basis, excluded: Array[RID]) -> Vector3:
	var desired := eye + view * Vector3(0.5, 0.25, 3.4)
	var query := PhysicsRayQueryParameters3D.create(eye, desired)
	query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return desired if hit.is_empty() else hit.position + hit.normal * 0.2

func trace_shot(body: CharacterBody3D, view: Basis, shoulder: bool) -> Dictionary:
	var eye := shot_eye(body)
	var direction := -view.z
	var excluded: Array[RID] = [body.get_rid()]
	for fighter in fighters.values():
		if fighter.phase == "dead": excluded.append(fighter.get_rid())
	var endpoint := eye + direction * 220
	if shoulder:
		var sight := shoulder_camera(eye, view, excluded)
		var sight_query := PhysicsRayQueryParameters3D.create(sight, sight + direction * 220)
		sight_query.exclude = excluded
		var aimed := get_world_3d().direct_space_state.intersect_ray(sight_query)
		var target: Vector3 = sight_query.to if aimed.is_empty() else aimed.position
		# The camera chooses the point. The shot still starts at the fighter so cover can stop it.
		if (target - eye).dot(direction) > 0:
			var aim_direction := eye.direction_to(target)
			endpoint = eye + aim_direction * minf(220.0, eye.distance_to(target) + 0.03)
	var shot := PhysicsRayQueryParameters3D.create(eye, endpoint)
	shot.exclude = excluded
	shot.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(shot)
	return {"hit": hit, "endpoint": hit.get("position", endpoint)}

func shoot(id: int) -> void:
	var body = fighters[id]
	if body.phase != "ground" or not body.weapon or body.magazine <= 0 or body.cooldown > 0 or body.reload_left > 0: return
	body.magazine -= 1
	body.cooldown = 0.12
	var origin := shot_eye(body)
	var view := Basis.from_euler(Vector3(body.pitch, body.yaw, 0))
	var trace := trace_shot(body, view, body.command.get("third_person", false))
	var hit: Dictionary = trace.hit
	var endpoint: Vector3 = trace.endpoint
	if not hit.is_empty():
		for other in fighters:
			if fighters[other] == hit.collider:
				var before_hp: float = fighters[other].hp
				var before_armor: float = fighters[other].armor
				damage(other, 26, id)
				if fighters[other].hp < before_hp:
					var normal: Vector3 = hit.normal if hit.normal != Vector3.ZERO else view.z
					var health_lost: float = before_hp - fighters[other].hp
					var armor_lost: float = before_armor - fighters[other].armor
					confirmed_impact(hit.position, normal, other, id, health_lost, armor_lost)
					if not multiplayer.get_peers().is_empty():
						confirmed_impact.rpc(hit.position, normal, other, id, health_lost, armor_lost)
				break
	shot_effect(origin, endpoint, id)
	if multiplayer.get_peers().size() > 0: remote_shot.rpc(origin, endpoint, id)

@rpc("authority", "call_remote", "unreliable", 3)
func remote_shot(from: Vector3, to: Vector3, id: int) -> void:
	shot_effect(from, to, id)

func shot_effect(from: Vector3, to: Vector3, id: int) -> void:
	shot_index = (shot_index % 2) + 1
	if id == local_id:
		play_local_sound("ar15_close_0%s_responsive.wav" % shot_index, -4)
	elif id > 0:
		var sound := AudioStreamPlayer3D.new()
		var far_shot: bool = fighters.has(local_id) and fighters[local_id].position.distance_to(from) > 35
		sound.stream = RIFLE_AUDIO["ar15_%s_0%s.wav" % ["mid" if far_shot else "close", shot_index]]
		sound.volume_db = -9
		sound.unit_size = 18
		sound.max_distance = 240
		add_child(sound)
		sound.position = from
		sound.finished.connect(sound.queue_free)
		sound.play()
	var line := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffe2a3")
	line.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	line.surface_add_vertex(from)
	line.surface_add_vertex(to)
	line.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = line
	add_child(node)
	fx_nodes.append({"node": node, "ttl": 0.06})
	if id == local_id: recoil = minf(0.08, recoil + 0.025)

func play_local_sound(file: String, volume: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = RIFLE_AUDIO[file]
	sound.volume_db = volume
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

@rpc("authority", "call_remote", "reliable", 2)
func confirmed_impact(at: Vector3, normal: Vector3, victim: int, attacker: int, health_lost: float, armor_lost: float) -> void:
	if attacker == local_id:
		hit_flash = 0.15
		if combat_effects: combat_effects.show_hit_number(at, health_lost, armor_lost)
	if fighters.has(victim): fighters[victim].react_to_hit(normal)
	if combat_effects: combat_effects.bullet_impact(at, normal, victim == TRAINING_ID)

@rpc("authority", "call_remote", "reliable", 2)
func receive_hurt(amount: float, source: Vector3, source_known: bool) -> void:
	if combat_effects: combat_effects.show_damage(amount, source, source_known)

func damage(id: int, amount: float, attacker: int) -> void:
	if not fighters.has(id): return
	var body = fighters[id]
	if body.phase == "dead" or (body.protection > 0 and attacker != 0): return
	var absorbed: float = minf(body.armor, amount * 0.65)
	body.armor -= absorbed
	body.hp = maxf(0, body.hp - (amount - absorbed))
	if id == local_id and combat_effects:
		combat_effects.show_damage(amount - absorbed, fighters[attacker].position if fighters.has(attacker) else Vector3.ZERO, fighters.has(attacker))
	elif id in multiplayer.get_peers():
		receive_hurt.rpc_id(id, amount - absorbed, fighters[attacker].position if fighters.has(attacker) else Vector3.ZERO, fighters.has(attacker))
	if body.hp > 0: return
	body.phase = "dead"
	body.collision_layer = 0
	body.respawn_left = 4.0
	body.velocity = Vector3.ZERO
	if id == TRAINING_ID:
		var training_tag := body.get_node_or_null("TrainingTag") as Label3D
		if training_tag: training_tag.text = "TARGET DOWN · RESPAWNING"
	if attacker != id and fighters.has(attacker):
		fighters[attacker].score += 1
		if mode == 1 and fighters[attacker].score >= 10: finish_match()
	if body.weapon: add_loot(0, body.position + Vector3.UP * 0.3)
	body.animate()

func throw_grenade(id: int) -> void:
	var body = fighters[id]
	if body.phase != "ground" or body.grenades <= 0: return
	body.grenades -= 1
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	mesh.position = body.position + Vector3.UP * 1.5
	add_child(mesh)
	var direction: Vector3 = Basis.from_euler(Vector3(body.pitch, body.yaw, 0)) * Vector3.FORWARD
	grenade_serial += 1
	throwables.append({"id": grenade_serial, "node": mesh, "v": direction * 16 + Vector3.UP * 5, "ttl": 2.5, "owner": id})

func update_throwables(delta: float) -> void:
	for i in range(throwables.size() - 1, -1, -1):
		var item: Dictionary = throwables[i]
		item.ttl -= delta
		item.v.y -= 12 * delta
		var start: Vector3 = item.node.position
		var finish: Vector3 = start + item.v * delta
		var query := PhysicsRayQueryParameters3D.create(start, finish)
		query.exclude = [fighters[item.owner].get_rid()] if fighters.has(item.owner) else []
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): item.node.position = finish
		else:
			item.node.position = hit.position + hit.normal * 0.15
			item.v = item.v.bounce(hit.normal) * 0.4
		if item.ttl <= 0:
			var at: Vector3 = item.node.position
			for id in fighters:
				var distance: float = fighters[id].position.distance_to(at)
				if distance < 7:
					var cover := PhysicsRayQueryParameters3D.create(at, fighters[id].position + Vector3.UP)
					var obstruction := get_world_3d().direct_space_state.intersect_ray(cover)
					if obstruction.is_empty() or obstruction.collider == fighters[id]: damage(id, 100 * (1 - distance / 7), item.owner)
			blast_effect(at)
			if not multiplayer.get_peers().is_empty(): remote_blast.rpc(at)
			item.node.queue_free()
			throwables.remove_at(i)

@rpc("authority", "call_remote", "unreliable", 3)
func remote_blast(at: Vector3) -> void:
	blast_effect(at)

func blast_effect(at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.5, 0.1, 0.7)
	mesh.material_override = material
	add_child(mesh)
	mesh.position = at
	var tween := create_tween().set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * 12, 0.3)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(mesh.queue_free)

func finish_match() -> void:
	var best := -1
	var winners: Array[int] = []
	for id in fighters:
		if fighters[id].score > best:
			best = fighters[id].score
			winners = [id]
		elif fighters[id].score == best: winners.append(id)
	end_text = "DRAW" if winners.size() != 1 else "PLAYER %s WINS" % (1 if winners[0] == 1 else 2)
	message(end_text + " · Host: F5 for a rematch")

func send_snapshot() -> void:
	if multiplayer.get_peers().is_empty(): return
	if loot_dirty:
		receive_loot.rpc(loot)
		loot_dirty = false
	var grenade_states := []
	for grenade in throwables: grenade_states.append([grenade.id, grenade.node.position])
	receive_grenades.rpc(grenade_states)
	var states := {}
	for id in fighters: states[id] = fighters[id].pack()
	var door_states: Array[bool] = []
	for door in doors: door_states.append(door.is_open)
	for crate in crates: door_states.append(crate.opened)
	receive_snapshot.rpc(states, clock, zone_radius, door_states, mode, end_text, flight_time)

@rpc("authority", "call_remote", "unreliable_ordered", 0)
func receive_snapshot(states: Dictionary, time: float, radius: float, door_states: Array, game_mode: int, result: String, flight: float) -> void:
	if authority: return
	flight_time = flight
	update_flight(0)
	clock = time
	zone_radius = radius
	mode = game_mode
	end_text = result
	for id in states:
		if not fighters.has(id): spawn_fighter(id)
		fighters[id].unpack(states[id], id == local_id)
	for id in fighters.keys():
		if not states.has(id):
			fighters[id].queue_free()
			fighters.erase(id)
	for i in range(mini(doors.size(), door_states.size())):
		if doors[i].is_open != door_states[i]: doors[i].toggle(Vector3.INF)
	for i in range(crates.size()):
		if door_states.size() > doors.size() + i: crates[i].set_open(door_states[doors.size() + i])

@rpc("authority", "call_remote", "reliable", 2)
func receive_loot(items: Dictionary) -> void:
	if authority: return
	for id in items:
		if not loot.has(id):
			loot[id] = items[id]
			make_loot_visual(id)
		loot[id] = items[id]
		loot_nodes[id].visible = items[id].ready == 0

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func receive_grenades(states: Array) -> void:
	var seen := []
	for state in states:
		var id: int = state[0]
		seen.append(id)
		if not remote_grenades.has(id):
			var node := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.12
			sphere.height = 0.24
			node.mesh = sphere
			add_child(node)
			node.position = state[1]
			remote_grenades[id] = {"node": node, "target": state[1]}
		remote_grenades[id].target = state[1]
	for id in remote_grenades.keys():
		if id not in seen:
			remote_grenades[id].node.queue_free()
			remote_grenades.erase(id)

func _process(delta: float) -> void:
	if main_rotor: main_rotor.rotate_y(delta * 31)
	if tail_rotor: tail_rotor.rotate_x(delta * 48)
	update_suspension()
	if measure_frames and active and clock > 2 and delta > 0:
		frame_samples.append(delta)
		if delta > 0.04 and frame_hitches.size() < 20:
			frame_hitches.append({"ms": delta * 1000, "clock": clock, "phase": fighters[local_id].phase if fighters.has(local_id) else "none", "fighters": fighters.size(), "loot": loot.size()})
	hit_flash = maxf(0, hit_flash - delta)
	for grenade in remote_grenades.values(): grenade.node.position = grenade.node.position.lerp(grenade.target, 1 - exp(-16 * delta))
	if sky_audio:
		var phase: String = fighters[local_id].phase if fighters.has(local_id) else ""
		sky_audio.update(phase, delta, aircraft.position, active and use_preview_sky_audio)
	for i in range(fx_nodes.size() - 1, -1, -1):
		fx_nodes[i].ttl -= delta
		if fx_nodes[i].ttl <= 0:
			fx_nodes[i].node.queue_free()
			fx_nodes.remove_at(i)
	if not active or not fighters.has(local_id): return
	zone_wall.visible = true
	zone_wall.scale = Vector3(zone_radius, 65, zone_radius)
	for id in fighters:
		var other = fighters[id]
		if not authority and id != local_id:
			other.position = other.position.lerp(other.target_position, 1 - exp(-16 * delta))
			other.rotation.y = lerp_angle(other.rotation.y, other.target_yaw, 1 - exp(-16 * delta))
	var body = fighters[local_id]
	var distance_from_zone := Vector2(body.position.x - zone_center.x, body.position.z - zone_center.z).length()
	outside_tint.visible = body.phase == "ground" and distance_from_zone > zone_radius
	var outside_view: bool = third_person or body.phase == "helicopter"
	body.visual.visible = outside_view and body.show_pose()
	recoil = move_toward(recoil, 0, delta * 0.2)
	var eye := shot_eye(body)
	if body.phase != "helicopter":
		eye += body.get_global_transform_interpolated().origin - body.global_position
	var view_basis := Basis.from_euler(Vector3(clampf(look_pitch + recoil, -1.45, 1.45), look_yaw, 0))
	camera.global_basis = view_basis
	var desired := eye
	if outside_view:
		var excluded: Array[RID] = [body.get_rid()]
		for fighter in fighters.values():
			if fighter.phase == "dead": excluded.append(fighter.get_rid())
		desired = shoulder_camera(eye, view_basis, excluded)
		if body.phase == "helicopter": desired = eye + view_basis * Vector3(4, 3.0, 12)
	camera.global_position = desired
	if viewmodel:
		viewmodel.visible = body.weapon and not outside_view and body.phase == "ground"
		viewmodel.position.y = -0.38 - minf(body.reload_left, 0.3)
		viewmodel.rotation.x = recoil * 2
		if gun_animator and viewmodel.visible:
			var clip_time: float = 3.0 + 3.0 * (1.0 - body.reload_left / 1.8) if body.reload_left > 0 else 6.0
			if clip_time != gun_previous_time: gun_animator.seek(clip_time, true)
			if body.reload_left > 0:
				var cues := {3.25: "ar15_magazine_out.wav", 4.4: "ar15_magazine_in.wav", 5.3: "ar15_bolt_release.wav"}
				for frame_time in cues:
					if gun_previous_time < frame_time and clip_time >= frame_time: play_local_sound(cues[frame_time], -12)
			gun_previous_time = clip_time
	camera.fov = lerpf(camera.fov, 55.0 if body.aim else 78.0, 1 - exp(-12 * delta))
	feed.hide()
	target_scan -= delta
	if target_scan <= 0:
		target_scan = 0.05
		target_under_aim = false
		var hit: Dictionary = trace_shot(body, view_basis, third_person).hit
		if not hit.is_empty():
			for other in fighters:
				if other != local_id and fighters[other] == hit.collider and fighters[other].phase != "dead": target_under_aim = true
	reticle_scale = lerpf(reticle_scale, 1.7 if target_under_aim else 1.0, 1 - exp(-14 * delta))

func message(text: String) -> void:
	feed.text = text + "\nWASD move · Shift sprint · Ctrl crouch · Mouse aim/fire\nE loot/door · R reload · H heal · G grenade · V camera · M map · Esc menu"

func bake_map() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 2048)
	viewport.world_3d = get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var map_camera := Camera3D.new()
	map_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.size = maxf(arena_bounds.size.x, arena_bounds.size.z) * 1.05
	map_camera.far = 1000
	viewport.add_child(map_camera)
	map_camera.global_position = zone_center + Vector3.UP * (arena_bounds.end.y + 150)
	map_camera.look_at(zone_center, Vector3.FORWARD)
	map_camera.make_current()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	minimap_texture = ImageTexture.create_from_image(viewport.get_texture().get_image())
	viewport.queue_free()

func arena_review() -> void:
	for frame in range(30): await get_tree().physics_frame
	set_physics_process(false)
	var body = fighters[1]
	var checks := {}
	checks["loot_count"] = loot.size() >= 40
	checks["drop_starts_above_roofs"] = body.position.y > arena_bounds.end.y + 20
	perform_action(1, "jump")
	checks["manual_jump"] = body.phase == "fall"
	perform_action(1, "jump")
	checks["manual_parachute"] = body.phase == "parachute"
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4)) + Vector3.UP
	body.phase = "parachute"
	for frame in range(120):
		await get_tree().physics_frame
		body.step(1.0 / 60)
	checks["landed"] = body.phase == "ground" and body.is_on_floor()
	var weapon_id := -1
	for id in loot:
		if loot[id].kind == 0: weapon_id = id
	body.position = loot[weapon_id].p
	interact(1)
	checks["pickup"] = body.weapon and body.magazine == 30 and loot[weapon_id].ready > 0
	body.magazine = 0
	perform_action(1, "reload")
	for frame in range(120): body.step(1.0 / 60)
	checks["reload"] = body.magazine == 30
	body.protection = 0
	body.armor = 75
	damage(1, 20, 1)
	checks["armour_absorbs"] = body.armor < 75 and body.hp > 80
	body.medkits = 1
	body.hp = 50
	perform_action(1, "heal")
	checks["healing"] = body.hp == 100 and body.medkits == 0
	body.backpack = true
	body.grenades = 1
	throw_grenade(1)
	checks["grenade_created"] = throwables.size() == 1 and body.grenades == 0
	damage(1, 1000, 0)
	checks["death_respawn_timer"] = body.phase == "dead" and body.respawn_left == 4
	body.drop(drop_position(1))
	checks["respawn_resets_loot"] = body.phase == "helicopter" and not body.weapon and body.hp == 100
	checks["doors"] = doors.size() == 10
	sky_audio.update("fall", 1, aircraft.position, true)
	var wind_active: bool = sky_audio.wind.volume_db > -20
	sky_audio.update("parachute", 1, aircraft.position, true)
	var deploy_active: bool = sky_audio.deploy.playing
	sky_audio.update("ground", 1, aircraft.position, true)
	checks["sky_audio_state_hooks"] = wind_active and deploy_active and sky_audio.touchdown.playing
	sky_audio.update("", 1, aircraft.position, false)
	var passed := true
	for value in checks.values(): passed = passed and bool(value)
	var report := {"passed": passed, "checks": checks, "bounds": str(arena_bounds), "loot": loot.size()}
	var file := FileAccess.open("res://review/arena-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("ARENA_REVIEW ", JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

func connection_review() -> void:
	for attempt in range(100):
		await get_tree().create_timer(0.1).timeout
		if fighters.size() == 2 and loot.size() > 30: break
	if authority and fighters.size() == 2:
		var other_id: int = fighters.keys()[1]
		fighters[1].position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
		fighters[1].phase = "ground"
		fighters[1].weapon = true
		fighters[1].magazine = 30
		look_yaw = PI + 0.083
		look_pitch = -0.13
		fighters[other_id].position = floor_at(NORTH_ENTRY + Vector3(0, 0, 10))
		fighters[other_id].phase = "ground"
		fighters[other_id].protection = 0
		await get_tree().physics_frame
		await get_tree().physics_frame
		shoot(1)
	for attempt in range(100):
		if authority or (fighters.has(local_id) and fighters[local_id].hp < 100 and combat_effects.source_known): break
		await get_tree().create_timer(0.02).timeout
	var passed := active and fighters.size() == 2 and loot.size() > 30
	var combat_synced := false
	var movement_rigs_ready := fighters.size() == 2
	for id in fighters:
		if id != 1: combat_synced = fighters[id].hp < 100
		var motion = fighters[id].body_motion
		movement_rigs_ready = movement_rigs_ready and motion != null and motion.hips >= 0 and motion.chest >= 0
	var feedback_synced: bool = hit_flash > 0 and not combat_effects.hit_numbers.is_empty()
	if not authority and fighters.has(1):
		feedback_synced = combat_effects.source_known and combat_effects.source_position.distance_to(fighters[1].target_position) < 1.0
	passed = passed and combat_synced and feedback_synced and movement_rigs_ready and fighters.has(1) and fighters[1].magazine == 29
	var states := {}
	for id in fighters: states[id] = fighters[id].pack()
	print("NETWORK_REVIEW authority=", authority, " peers=", fighters.size(), " loot=", loot.size(), " state_bytes=", var_to_bytes(states).size(), " combat_synced=", combat_synced, " feedback_synced=", feedback_synced, " movement_rigs_ready=", movement_rigs_ready, " passed=", passed)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0 if passed else 1)

func capture_arena() -> void:
	await get_tree().create_timer(2.0).timeout
	var body = fighters[local_id]
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 8))
	body.phase = "ground"
	body.weapon = true
	body.magazine = 30
	body.ammo = 90
	look_pitch = -0.05
	message("Practice yard ready. Explore, find supplies and test your aim.")
	await get_tree().create_timer(1.0).timeout
	var animators = viewmodel.find_children("*", "AnimationPlayer", true, false)
	if not animators.is_empty():
		var animator: AnimationPlayer = animators[0]
		print("VIEWMODEL_ANIMATIONS ", animator.get_animation_list())
		for t in [0.1, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]:
			animator.play("allanims")
			animator.seek(t, true)
			animator.pause()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://review/carbine-%s.png" % str(t))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://review/arena-preview.png")
	radar.expanded = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://review/tactical-map-preview.png")
	get_tree().quit()

func review_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().physics_frame
	await get_tree().physics_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().physics_frame

func round_review() -> void:
	AudioServer.set_bus_mute(0, true)
	var checks := {}
	for frame in range(10): await get_tree().physics_frame
	var body = fighters[1]
	checks["unarmed_on_aircraft"] = body.phase == "helicopter" and not body.weapon
	await review_key(KEY_SPACE)
	for frame in range(40): await get_tree().physics_frame
	checks["actual_freefall"] = body.phase == "fall" and body.velocity.y < -8 and body.position.y < drop_position(1).y - 2
	await review_key(KEY_SPACE)
	for frame in range(4): await get_tree().physics_frame
	checks["actual_deployment"] = body.phase == "parachute" and body.canopy.visible
	for frame in range(2400):
		await get_tree().physics_frame
		if body.phase in ["ground", "dead"]: break
	checks["full_height_landing"] = body.phase == "ground" and body.hp == 100 and body.is_on_floor()
	await round_screenshot("drop-landed")
	checks["supply_caches_present"] = crates.size() >= 6
	if not crates.is_empty():
		var crate = crates[0]
		body.position = floor_at(crate.position + Vector3(1.8, 0, 0))
		body.velocity = Vector3.ZERO
		for frame in range(4): await get_tree().physics_frame
		var before := loot.size()
		await review_key(KEY_E)
		checks["cache_opened_by_input"] = crate.opened and loot.size() == before + 3
		await get_tree().create_timer(0.6).timeout
		checks["lid_actually_moved"] = crate.hinge and absf(crate.hinge.rotation.x - crate.closed_rotation.x) > 1.0
		var direction: Vector3 = (crate.position + Vector3.UP * 0.4 - (body.position + Vector3.UP * 1.64)).normalized()
		look_yaw = atan2(-direction.x, -direction.z)
		look_pitch = asin(direction.y)
		await round_screenshot("cache-open")
	var weapon_id := -1
	for id in loot:
		if loot[id].kind == 0 and loot[id].ready == 0: weapon_id = id
	body.position = loot[weapon_id].p
	body.velocity = Vector3.ZERO
	for frame in range(4): await get_tree().physics_frame
	await review_key(KEY_E)
	checks["weapon_looted_by_input"] = body.weapon and body.magazine == 30
	spawn_fighter(2)
	var opponent = fighters[2]
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
	opponent.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 10))
	body.phase = "ground"
	opponent.phase = "ground"
	body.velocity = Vector3.ZERO
	opponent.velocity = Vector3.ZERO
	opponent.protection = 0
	look_yaw = PI + 0.083
	look_pitch = -0.13
	for frame in range(4): await get_tree().physics_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	for frame in range(14): await get_tree().physics_frame
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	checks["firing_input_hits_opponent"] = opponent.hp < 100 and body.magazine < 30
	await round_screenshot("combat")
	await review_key(KEY_R)
	for frame in range(120): await get_tree().physics_frame
	checks["reload_input_completes"] = body.magazine == 30 and body.reload_left == 0
	damage(2, 1000, 1)
	checks["elimination_scores"] = body.score == 1 and opponent.phase == "dead"
	mode = 0
	clock = 250
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
	body.hp = 100
	body.armor = 0
	for frame in range(70): await get_tree().physics_frame
	checks["zone_shrinks_and_hurts"] = zone_radius <= 22.1 and body.hp < 100
	body.medkits = 1
	var before_hp: float = body.hp
	await review_key(KEY_H)
	checks["healing_input"] = body.hp > before_hp and body.medkits == 0
	damage(1, 1000, 2)
	for frame in range(270): await get_tree().physics_frame
	checks["actual_respawn"] = body.phase == "helicopter" and body.hp == 100 and not body.weapon
	mode = 1
	body.score = 9
	opponent.phase = "ground"
	opponent.hp = 1
	opponent.protection = 0
	damage(2, 20, 1)
	checks["score_limit_ends_match"] = body.score == 10 and end_text.contains("WINS")
	await review_key(KEY_F5)
	checks["rematch_by_input"] = end_text.is_empty() and clock < 0.1 and body.score == 0 and body.phase == "helicopter"
	mode = 0
	clock = 300
	for frame in range(3): await get_tree().physics_frame
	checks["timed_mode_ends"] = not end_text.is_empty()
	var passed := true
	for result in checks.values(): passed = passed and bool(result)
	var report := {"passed": passed, "checks": checks, "note": "Actual full-height physics drop and game input events; multiplayer uses a separate two-process check."}
	var file := FileAccess.open("res://review/full-round-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	if not frame_samples.is_empty():
		var sorted := frame_samples.duplicate()
		sorted.sort()
		var total := 0.0
		for frame_time in sorted: total += frame_time
		var performance := {"frames": sorted.size(), "average_fps": sorted.size() / total, "median_frame_ms": sorted[sorted.size() / 2] * 1000, "p95_frame_ms": sorted[int(sorted.size() * 0.95)] * 1000, "maximum_frame_ms": sorted[-1] * 1000, "hitches": frame_hitches, "scope": "Rendered scripted PC round at 1280x800; this is not a two-machine or Android performance test."}
		var metrics := FileAccess.open("res://review/rendered-round-performance.json", FileAccess.WRITE)
		metrics.store_string(JSON.stringify(performance, "  "))
		print("RENDERED_PERFORMANCE ", JSON.stringify(performance))
	print("FULL_ROUND_REVIEW ", JSON.stringify(report))
	get_tree().quit(0 if passed else 1)

func capture_menu() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://review/menu-preview.png")
	get_tree().quit()

func round_screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var resume_measurement := measure_frames
	measure_frames = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://review/round-" + name + ".png")
	for frame in range(2): await get_tree().process_frame
	measure_frames = resume_measurement

func portable_review() -> void:
	for frame in range(30): await get_tree().physics_frame
	perform_action(1, "jump")
	perform_action(1, "jump")
	var passed: bool = fighters[1].phase == "parachute" and loot.size() >= 40 and crates.size() >= 6 and fighters[1].animator.has_animation("sky/SkyGlide")
	print("PORTABLE_REVIEW passed=", passed, " loot=", loot.size(), " crates=", crates.size())
	get_tree().quit(0 if passed else 1)

func update_flight(delta: float) -> void:
	flight_time += delta
	var north: float = arena_bounds.position.z + 18
	var south: float = arena_bounds.end.z - 18
	var leg_seconds: float = (south - north) / 17.0
	var cycle := fposmod(flight_time, leg_seconds * 2)
	var outbound := cycle < leg_seconds
	var t := cycle / leg_seconds if outbound else 2.0 - cycle / leg_seconds
	aircraft.position = Vector3(zone_center.x, maxf(arena_bounds.end.y + 145, 165), lerpf(north, south, t))
	aircraft.rotation.y = 0 if outbound else PI

func update_suspension() -> void:
	for old_id in suspension_lines.keys():
		if not fighters.has(old_id):
			suspension_lines[old_id].queue_free()
			suspension_lines.erase(old_id)
	for id in fighters:
		if not suspension_lines.has(id):
			var rope := preload("res://sway_rope.gd").new()
			add_child(rope)
			suspension_lines[id] = rope
		var rope = suspension_lines[id]
		rope.visible = fighters[id].phase == "helicopter"
		if not rope.visible: continue
		var top := aircraft.to_global(Vector3(-1.2 if id == 1 else 1.2, -0.65, 0))
		var bottom: Vector3 = fighters[id].position + Vector3.UP * 1.65
		rope.set_endpoints(top, bottom, flight_time)

func flight_review() -> void:
	await get_tree().create_timer(0.5).timeout
	var body = fighters[1]
	var checks := {}
	var start := aircraft.position
	var rotation_before: float = main_rotor.rotation.y if main_rotor else 0
	await get_tree().create_timer(2.0).timeout
	checks["flight_moves"] = aircraft.position.distance_to(start) > 25
	checks["starts_at_north_edge"] = start.z < arena_bounds.position.z + 35
	checks["rotor_rotates"] = main_rotor != null and absf(main_rotor.rotation.y - rotation_before) > 0.1
	checks["tail_rotor_present"] = tail_rotor != null
	checks["rider_follows"] = body.position.distance_to(drop_position(1)) < 0.5
	checks["below_cabin"] = aircraft.position.y - body.position.y > 6.5
	checks["rope_visible"] = suspension_lines.has(1) and suspension_lines[1].visible
	look_yaw = 0.6
	look_pitch = 0.1
	await round_screenshot("rope-flight")
	var saved_time := flight_time
	flight_time = (arena_bounds.size.z - 36) / 17.0
	update_flight(0)
	checks["reaches_opposite_edge"] = absf(aircraft.position.z - (arena_bounds.end.z - 18)) < 0.1
	flight_time = saved_time
	update_flight(0)
	perform_action(1, "jump")
	await get_tree().create_timer(0.2).timeout
	checks["release_detaches_rope"] = body.phase == "fall" and not suspension_lines[1].visible
	perform_action(1, "jump")
	checks["parachute_still_works"] = body.phase == "parachute"
	var passed := true
	for result in checks.values(): passed = passed and bool(result)
	var file := FileAccess.open("res://review/flight-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks}, "  "))
	print("FLIGHT_REVIEW ", JSON.stringify(checks), " passed=", passed)
	get_tree().quit(0 if passed else 1)

func bot_review() -> void:
	print("TRAINING_TEST_BEGIN")
	AudioServer.set_bus_mute(0, true)
	shooting_practice()
	var checks := {}
	await get_tree().create_timer(0.3).timeout
	var bot = fighters[TRAINING_ID]
	checks["practice_starts_armed"] = fighters[local_id].weapon and fighters[local_id].magazine == 30
	checks["bot_on_ground"] = bot.phase == "ground" and bot.hp == 100
	var start: Vector3 = bot.position
	await get_tree().create_timer(2.0).timeout
	checks["bot_moves"] = bot.position.distance_to(start) > 0.3
	training_enabled = false
	bot.command.move = Vector2.ZERO
	var shooter = fighters[local_id]
	bot.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 10))
	bot.velocity = Vector3.ZERO
	shooter.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
	shooter.velocity = Vector3.ZERO
	look_yaw = PI + 0.083
	look_pitch = -0.13
	await get_tree().create_timer(0.3).timeout
	checks["indicator_detects_target"] = target_under_aim and reticle_scale > 1.4
	print("TRAINING_AIM shooter=", shooter.position, " bot=", bot.position, " yaw=", shooter.yaw, " target=", target_under_aim)
	await round_screenshot("training-robot")
	await review_key(KEY_M)
	checks["full_map_opens"] = radar.expanded and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	await round_screenshot("full-map")
	var map_click := InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.pressed = true
	map_click.position = get_viewport().get_visible_rect().size * 0.5
	get_viewport().push_input(map_click, true)
	map_click = map_click.duplicate()
	map_click.pressed = false
	get_viewport().push_input(map_click, true)
	for frame in range(2): await get_tree().process_frame
	checks["map_click_closes"] = not radar.expanded
	if radar.expanded: radar.toggle_map()
	var cover := StaticBody3D.new()
	var blocker := CollisionShape3D.new()
	var block_shape := BoxShape3D.new()
	block_shape.size = Vector3(0.3, 0.3, 0.3)
	blocker.shape = block_shape
	cover.add_child(blocker)
	add_child(cover)
	cover.global_position = shot_eye(shooter) + Vector3(0.0, -0.06, 0.7)
	for frame in range(3): await get_tree().physics_frame
	var blocked_view := Basis.from_euler(Vector3(shooter.pitch, shooter.yaw, 0))
	var blocked_hit: Dictionary = trace_shot(shooter, blocked_view, true).hit
	shoot(local_id)
	checks["cover_blocks_shot"] = not blocked_hit.is_empty() and blocked_hit.collider == cover and bot.hp == 100 and hit_flash == 0
	cover.queue_free()
	while shooter.cooldown > 0: await get_tree().physics_frame
	recoil = 0
	third_person = false
	look_yaw = PI
	look_pitch = -0.09
	bot.armor = 75
	for frame in range(3): await get_tree().physics_frame
	shoot(local_id)
	var number: Dictionary = combat_effects.hit_numbers.back() if not combat_effects.hit_numbers.is_empty() else {}
	checks["first_person_armor_hit"] = is_equal_approx(bot.hp, 90.9) and is_equal_approx(bot.armor, 58.1)
	checks["damage_numbers"] = number.get("health") == "9" and number.get("armor") == "17 ARMOR"
	bot.hp = 100
	bot.armor = 0
	third_person = true
	look_yaw = PI + 0.083
	look_pitch = -0.13
	for shot in range(4):
		while shooter.cooldown > 0: await get_tree().physics_frame
		recoil = 0
		for frame in range(2): await get_tree().physics_frame
		shoot(local_id)
		if shot == 0:
			checks["hit_reaction"] = bot.hp == 74 and bot.body_motion and bot.body_motion.time_left > 0 and hit_flash > 0
			await round_screenshot("bullet-impact")
	checks["shots_defeat_bot"] = bot.phase == "dead" and bot.hp == 0 and shooter.score == 1
	checks["death_animation_visible"] = bot.show_pose() and bot.animator.current_animation == "death"
	training_enabled = true
	await get_tree().create_timer(4.5).timeout
	checks["bot_respawns"] = bot.phase == "ground" and bot.hp == 100
	checks["bot_does_not_shoot"] = shooter.hp == 100
	var passed := true
	for result in checks.values(): passed = passed and bool(result)
	var file := FileAccess.open("res://review/training-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks}, "  "))
	print("TRAINING_REVIEW ", JSON.stringify(checks), " passed=", passed)
	get_tree().quit(0 if passed else 1)

func safety_review() -> void:
	var checks := {}
	var body = fighters[local_id]
	checks["third_person_default"] = third_person
	checks["higher_aircraft"] = aircraft.position.y >= 165
	perform_action(local_id, "jump")
	var freefall_frames := 0
	for frame in range(1000):
		await get_tree().physics_frame
		freefall_frames += 1
		if body.phase != "fall": break
	checks["automatic_deployment"] = body.phase == "parachute" and freefall_frames > 120
	var glide_frames := 0
	for frame in range(2400):
		await get_tree().physics_frame
		glide_frames += 1
		if body.phase != "parachute": break
	checks["visible_glide_time"] = glide_frames > 180
	checks["landed_alive"] = body.phase == "ground" and body.hp == 100
	clock = 260
	zone_timer = 0
	body.position = floor_at(NORTH_ENTRY + Vector3(0, 0, 4))
	body.velocity = Vector3.ZERO
	look_yaw = PI
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var start: Vector3 = body.position
	for frame in range(180): await get_tree().physics_frame
	key = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	checks["walking_stays_on_ground"] = body.phase == "ground" and body.hp == 100 and body.position.distance_to(start) > 5
	checks["practice_no_storm_damage"] = zone_radius == zone_start and body.hp == 100
	var passed := true
	for result in checks.values(): passed = passed and bool(result)
	var file := FileAccess.open("res://review/safety-checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "freefall_seconds": freefall_frames / 60.0, "glide_seconds": glide_frames / 60.0}, "  "))
	print("SAFETY_REVIEW ", JSON.stringify(checks), " passed=", passed)
	get_tree().quit(0 if passed else 1)
