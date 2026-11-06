extends Node3D
## Magnetic charge visual and attachment lifecycle. Authority validates placement,
## inventory, blast damage and network calls; this node never applies damage.

signal armed_changed(armed: bool)
signal detonation_requested(at: Vector3, owner_id: int)

const Blast = preload("res://explosive_fx.gd")
const DEFAULT_ARM_DELAY := 0.7
var placement_owner_id := 0
var armed := false
var is_preview := false
var preview_valid := false
var surface_normal := Vector3.UP
var sound_arm: AudioStream
var sound_explosion: AudioStream
var _elapsed := 0.0
var _arm_remaining := -1.0
var _detonated := false
var _visual: Node3D
var _model: PackedScene
var _indicator: MeshInstance3D
var _indicator_material: StandardMaterial3D
var _ghost_material: StandardMaterial3D

static func surface_pose(at: Vector3, normal: Vector3) -> Transform3D:
	var y := normal.normalized() if normal.is_finite() and normal.length_squared() > .00001 else Vector3.UP
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < .95 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x,y,z),at+y*.015)

static func create_preview(model: PackedScene = null) -> Node3D:
	var ghost := new()
	ghost.is_preview = true
	ghost._model = model
	return ghost

func configure(at: Vector3, normal: Vector3, owner_id: int, collider: Node3D = null) -> void:
	placement_owner_id = owner_id
	surface_normal = normal.normalized() if normal.length_squared() > .00001 else Vector3.UP
	var pose := surface_pose(at, surface_normal)
	if is_instance_valid(collider) and collider != self:
		if get_parent() == null: collider.add_child(self)
		elif get_parent() != collider: reparent(collider, true)
	if is_inside_tree(): global_transform = pose
	else: transform = pose

func set_model(model: PackedScene) -> void:
	_model = model
	if is_inside_tree(): _build_visual()

func _ready() -> void:
	_build_visual()
	if is_preview: set_preview_valid(preview_valid)

func _build_visual() -> void:
	if is_instance_valid(_visual):
		remove_child(_visual)
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	if _model:
		var model := _model.instantiate() as Node3D
		_visual.add_child(model)
		var bounds := AABB()
		var first := true
		for item in model.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = model.global_transform.affine_inverse()*item.global_transform*item.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
		if not first:
			var scale_factor := .30/maxf(bounds.size.x,maxf(bounds.size.z,bounds.size.y))
			model.scale = Vector3.ONE*scale_factor
			model.position = Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)*scale_factor
	else:
		# Temporary block, electronics housing, straps and wire. Replace with supplied model.
		_box(Vector3(.27,.065,.17),Vector3(0,.035,0),Color("586045"))
		_box(Vector3(.12,.045,.105),Vector3(0,.087,0),Color("272e2d"))
		for x in [-.09,.09]: _box(Vector3(.019,.071,.179),Vector3(x,.037,0),Color("262d28"))
		_box(Vector3(.07,.003,.025),Vector3(0,.111,.015),Color("222923"))
		_box(Vector3(.004,.008,.09),Vector3(.07,.075,-.015),Color("c9a553"))
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.albedo_color = Color("552626")
	_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator = MeshInstance3D.new()
	var light_mesh := SphereMesh.new()
	light_mesh.radius = .007
	light_mesh.height = .014
	light_mesh.radial_segments = 6
	light_mesh.rings = 3
	_indicator.mesh = light_mesh
	_indicator.position = Vector3(.035,.115,.025)
	_indicator.material_override = _indicator_material
	_visual.add_child(_indicator)
	# Imported model collision must never influence a placement preview or player movement.
	for node in _visual.find_children("*", "CollisionObject3D", true, false):
		node.collision_layer = 0
		node.collision_mask = 0
	if is_preview: set_preview_valid(preview_valid)

func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	item.material_override = material
	_visual.add_child(item)

func set_preview_valid(valid: bool) -> void:
	preview_valid = valid
	if not is_preview or not is_instance_valid(_visual): return
	if not _ghost_material:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_material.no_depth_test = false
	_ghost_material.albedo_color = Color(.2,1,.5,.38) if valid else Color(1,.18,.16,.38)
	for item in _visual.find_children("*", "MeshInstance3D", true, false):
		item.material_override = _ghost_material
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func arm(delay: float = DEFAULT_ARM_DELAY) -> void:
	if is_preview or _detonated: return
	_arm_remaining = maxf(delay,0)
	if _arm_remaining == 0: _finish_arm()

func _finish_arm() -> void:
	_arm_remaining = -1
	armed = true
	armed_changed.emit(true)
	_play_sound(sound_arm,-16)

func detonate() -> bool:
	if is_preview or not armed or _detonated: return false
	_detonated = true
	var at := global_position
	var normal := global_basis.y.normalized()
	var root := get_tree().current_scene as Node3D
	if root == null: root = get_parent() as Node3D
	if root:
		Blast.spawn(root,at,normal,1.0)
		if sound_explosion:
			var player := AudioStreamPlayer3D.new()
			player.stream=sound_explosion
			player.volume_db=-8
			player.unit_size=12
			player.max_distance=200
			root.add_child(player)
			player.global_position=at
			player.finished.connect(player.queue_free)
			player.play()
	detonation_requested.emit(at,placement_owner_id)
	queue_free()
	return true

func _play_sound(stream: AudioStream, volume: float) -> void:
	if not stream:return
	var player := AudioStreamPlayer3D.new()
	player.stream=stream
	player.volume_db=volume
	player.unit_size=3
	player.max_distance=25
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _process(delta: float) -> void:
	_elapsed += delta
	if _arm_remaining >= 0:
		_arm_remaining -= delta
		if _arm_remaining <= 0: _finish_arm()
	if not is_preview and is_instance_valid(_indicator_material):
		var lit := armed and fposmod(_elapsed,1.0)<.12
		_indicator_material.albedo_color = Color("ff493f") if lit else Color("552626")
