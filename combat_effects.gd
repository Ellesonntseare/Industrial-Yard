extends CanvasLayer
## Local screen feedback and short world-space hit effects.
## World impacts only play after the host confirms a hit.

var arena: Node3D
var overlay: Control
var vignette: ColorRect
var vignette_material: ShaderMaterial
var hurt_strength := 0.0
var damage_time := 0.0
var source_position := Vector3.ZERO
var source_known := false
var previous_hp := -1.0
var previous_phase := ""
var air_amount := 0.0
var elapsed := 0.0
var last_explicit_damage := -10.0
var impact_nodes: Array[CPUParticles3D] = []
var hit_numbers: Array[Dictionary] = []
var dust: CPUParticles3D

func setup(owner_arena: Node3D) -> void:
	arena = owner_arena
	layer = 8
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform float intensity = 0.0;
void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float edge = smoothstep(0.30, 1.15, length(p));
 float corners = smoothstep(0.58, 1.30, length(p));
 COLOR = vec4(vec3(0.46,0.018,0.032), (edge*0.43 + corners*0.15)*intensity);
}
"""
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = shader
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = vignette_material
	overlay.add_child(vignette)
	var drawing := Control.new()
	drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(drawing)
	drawing.draw.connect(_draw_feedback.bind(drawing))
	set_meta("drawing", drawing)

func show_damage(amount: float, from: Vector3 = Vector3.ZERO, has_source: bool = false) -> void:
	hurt_strength = clampf(hurt_strength + amount / 45.0, 0.25, 1.0)
	damage_time = 0.85
	source_position = from
	source_known = has_source
	last_explicit_damage = elapsed

func show_hit_number(at: Vector3, health: float, armor: float) -> void:
	if hit_numbers.size() >= 10: hit_numbers.pop_front()
	hit_numbers.append({
		"position": at + Vector3.UP * 0.25,
		"health": str(maxi(1, roundi(health))),
		"armor": str(maxi(1, roundi(armor))) + " ARMOR" if armor > 0 else "",
		"offset": randf_range(18.0, 40.0),
		"start": elapsed,
	})

func _process(delta: float) -> void:
	if not is_instance_valid(arena) or not is_instance_valid(overlay): return
	elapsed += delta
	hurt_strength = move_toward(hurt_strength, 0.0, delta * 1.5)
	damage_time = maxf(0.0, damage_time - delta)
	var enabled: bool = arena.active and arena.fighters.has(arena.local_id)
	if not enabled:
		previous_hp = -1
		previous_phase = ""
		air_amount = 0.0
		hurt_strength = 0.0
		hit_numbers.clear()
		overlay.hide()
		return
	var body = arena.fighters[arena.local_id]
	var phase: String = body.phase
	var hp: float = body.hp
	# This fallback also covers zone damage and state snapshots. Explicit RPC feedback
	# supplies shooter direction; do not retrigger that same hit when hp changes.
	if previous_hp >= 0 and hp < previous_hp and phase != "helicopter" and elapsed-last_explicit_damage > 0.12:
		show_damage(previous_hp-hp)
	if hp > previous_hp or (phase == "helicopter" and previous_phase == "dead"):
		hurt_strength = minf(hurt_strength, 0.12)
		damage_time = 0.0
		source_known = false
	previous_hp = hp
	previous_phase = phase
	var menu_open: bool = arena.menu.visible
	overlay.visible = not menu_open
	var low_health := clampf((30.0-hp)/30.0, 0.0, 0.65) if phase != "dead" else 0.0
	var pulse := low_health * (0.68+0.12*sin(elapsed*4.0))
	vignette_material.set_shader_parameter("intensity", maxf(hurt_strength,pulse))
	var target_air := 1.0 if phase == "fall" else 0.2 if phase == "parachute" else 0.0
	air_amount = move_toward(air_amount, target_air, delta*3.0)
	var drawing := get_meta("drawing") as Control
	while not hit_numbers.is_empty() and elapsed - hit_numbers[0].start >= 0.75:
		hit_numbers.pop_front()
	drawing.queue_redraw()
	impact_nodes = impact_nodes.filter(func(node): return is_instance_valid(node))
	_update_rotor_dust()

func _draw_feedback(surface: Control) -> void:
	var size := surface.get_viewport_rect().size
	var center := size*0.5
	if air_amount > 0.01:
		# Thin peripheral airflow streaks leave the aiming area clear.
		for i in range(18):
			var angle := float(i)*TAU/18.0 + 0.06*sin(float(i)*1.7)
			var travel := fposmod(elapsed*(1.0 if air_amount>.5 else .25)+float(i)*.173,1.0)
			var radial := Vector2(cos(angle),sin(angle))*Vector2(size.x*.67,size.y*.67)
			var start := center+radial*lerpf(.68,1.12,travel)
			var end := start+radial*.055*air_amount
			var alpha := .12*air_amount*sin(travel*PI)
			surface.draw_line(start,end,Color(.81,.92,.96,alpha),1.2,true)
	if source_known and damage_time>0 and arena.fighters.has(arena.local_id):
		var body = arena.fighters[arena.local_id]
		var relative: Vector3 = source_position-body.position
		if Vector2(relative.x,relative.z).length()>.001:
			var local: Vector3 = Basis(Vector3.UP,arena.look_yaw).inverse()*relative
			var bearing := atan2(local.x,-local.z)-PI*.5
			var radius := minf(size.x,size.y)*.21
			var alpha := clampf(damage_time/.35,0,1)
			surface.draw_arc(center,radius,bearing-.31,bearing+.31,22,Color(1.0,.27,.23,alpha),5.0,true)
	if not arena.radar.expanded:
		_draw_hit_numbers(surface)

func _draw_hit_numbers(surface: Control) -> void:
	var camera := arena.get_viewport().get_camera_3d()
	if not camera: return
	var font := ThemeDB.fallback_font
	for hit in hit_numbers:
		if camera.is_position_behind(hit.position): continue
		var progress: float = (elapsed - hit.start) / 0.75
		var fade := 1.0 - smoothstep(0.4, 1.0, progress)
		var point := camera.unproject_position(hit.position) + Vector2(hit.offset + progress * 8.0, -16.0 - progress * 44.0)
		var font_size := roundi(22.0 + 8.0 * maxf(0.0, 1.0 - progress * 6.0))
		surface.draw_string_outline(font, point, hit.health, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.04, 0.05, 0.06, fade))
		surface.draw_string(font, point, hit.health, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.88, 0.63, fade))
		if not hit.armor.is_empty():
			var armor_point := point + Vector2(0.0, 14.0)
			surface.draw_string_outline(font, armor_point, hit.armor, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0.04, 0.05, 0.06, fade))
			surface.draw_string(font, armor_point, hit.armor, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.49, 0.85, 1.0, fade))

func bullet_impact(at: Vector3, normal: Vector3, robot: bool) -> void:
	if not is_instance_valid(arena) or not at.is_finite(): return
	impact_nodes = impact_nodes.filter(func(node): return is_instance_valid(node))
	if impact_nodes.size() >= 8: return
	var effect := CPUParticles3D.new()
	effect.amount = 22
	effect.lifetime = 0.23 if robot else 0.32
	effect.one_shot = true
	effect.explosiveness = 1.0
	effect.local_coords = false
	effect.direction = (normal + Vector3.UP * 0.35).normalized()
	effect.spread = 40 if robot else 50
	effect.initial_velocity_min = 2.0 if robot else 0.8
	effect.initial_velocity_max = 5.0 if robot else 2.7
	effect.gravity = Vector3(0,-8,0)
	effect.scale_amount_min = .012
	effect.scale_amount_max = .035
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 6
	mesh.rings = 3
	effect.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffba52") if robot else Color("9b1c2f")
	if robot: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = .9
	effect.material_override = mat
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(effect)
	effect.global_position = at
	effect.finished.connect(effect.queue_free)
	effect.emitting = true
	impact_nodes.append(effect)

func _update_rotor_dust() -> void:
	# Do not create a dust cloud under a high-altitude helicopter.
	if not is_instance_valid(arena.aircraft): return
	var altitude: float = arena.aircraft.position.y-arena.arena_bounds.position.y
	if altitude>18 or not arena.active:
		if is_instance_valid(dust): dust.emitting=false
		return
	if not is_instance_valid(dust):
		dust = CPUParticles3D.new()
		dust.amount = 18
		dust.lifetime = 1.1
		dust.local_coords = false
		dust.direction = Vector3.UP
		dust.spread = 80
		dust.initial_velocity_min = 1
		dust.initial_velocity_max = 3
		dust.gravity = Vector3(0,-.4,0)
		dust.scale_amount_min = .08
		dust.scale_amount_max = .2
		var mesh := SphereMesh.new()
		mesh.radial_segments=6
		mesh.rings=3
		mesh.radius=.5
		mesh.height=1
		dust.mesh=mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color=Color(.42,.38,.30,.15)
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		dust.material_override=mat
		dust.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arena.add_child(dust)
	dust.global_position=Vector3(arena.aircraft.position.x,arena.arena_bounds.position.y+.2,arena.aircraft.position.z)
	dust.emitting=true
