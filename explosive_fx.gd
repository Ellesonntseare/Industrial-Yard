extends Node3D
## Visual-only, short-lived blast. Gameplay damage remains on the authority.

var _time := 0.0
var _flash: OmniLight3D
var _particles: Array[CPUParticles3D] = []
var _grenade: Node3D
var _grenade_spin := Vector3.ZERO

static func spawn(parent: Node3D, at: Vector3, normal: Vector3 = Vector3.UP, strength: float = 1.0) -> Node3D:
	var fx := new()
	parent.add_child(fx)
	fx.global_position = at
	fx._build(normal, clampf(strength, 0.4, 1.8))
	return fx

static func spin_grenade(model: Node3D, delta: float, angular_velocity: Vector3 = Vector3(6.0, 3.5, 2.0)) -> void:
	if is_instance_valid(model):
		model.rotate_x(angular_velocity.x * delta)
		model.rotate_y(angular_velocity.y * delta)
		model.rotate_z(angular_velocity.z * delta)

func _build(normal: Vector3, strength: float) -> void:
	_flash = OmniLight3D.new()
	_flash.light_color = Color("ffc77d")
	_flash.light_energy = 5.0 * strength
	_flash.omni_range = 7.0 * strength
	_flash.shadow_enabled = false
	add_child(_flash)
	var outward := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	_make_particles(14, .22, outward, 4.0, 8.0, Vector3(0,-4,0), .025, .09, Color("ffce70"), true, strength)
	_make_particles(20, .55, outward, 2.0, 5.5, Vector3(0,-8,0), .025, .07, Color("655a48"), false, strength)
	_make_particles(12, 1.15, Vector3.UP, .6, 2.5, Vector3(0,.4,0), .12, .35, Color(.29,.27,.23,.28), false, strength)

func _make_particles(count: int, duration: float, direction: Vector3, speed_min: float, speed_max: float, gravity_vector: Vector3, size_min: float, size_max: float, color: Color, bright: bool, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = duration
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = direction
	p.spread = 105.0 if bright else 80.0
	p.initial_velocity_min = speed_min * strength
	p.initial_velocity_max = speed_max * strength
	p.gravity = gravity_vector
	p.scale_amount_min = size_min * strength
	p.scale_amount_max = size_max * strength
	var growth := Curve.new()
	growth.add_point(Vector2(0, .35 if duration > 1 else 1))
	growth.add_point(Vector2(.4, 1))
	growth.add_point(Vector2(1, .15 if bright else 1.6))
	p.scale_amount_curve = growth
	var colors := Gradient.new()
	colors.set_color(0, color)
	colors.set_color(1, Color(color.r,color.g,color.b,0))
	p.color_ramp = colors
	var mesh := SphereMesh.new()
	mesh.radial_segments = 5
	mesh.rings = 2
	mesh.radius = .5
	mesh.height = 1
	p.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if bright else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 1.0
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	_particles.append(p)

func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_flash):
		_flash.light_energy = maxf(0.0, _flash.light_energy * exp(-delta*38.0))
	if _time > 1.45: queue_free()
