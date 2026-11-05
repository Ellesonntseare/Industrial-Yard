extends Control

var arena: Node3D
var radius := 15.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not arena or not arena.fighters.has(arena.local_id): return
	var body = arena.fighters[arena.local_id]
	var target := 23.0 if arena.target_under_aim else (12.0 if body.aim else 15.0)
	if body.cooldown > 0.07: target += 3
	radius = lerpf(radius, target, 1 - exp(-14 * delta))
	queue_redraw()

func _draw() -> void:
	if not arena or not arena.active or arena.menu.visible or arena.radar.expanded or not arena.fighters.has(arena.local_id): return
	if arena.fighters[arena.local_id].phase != "ground": return
	var center := get_viewport_rect().size * 0.5
	var color := Color("ff7065") if arena.target_under_aim else Color("e9fff4")
	if arena.hit_flash > 0: color = Color("ffc16b")
	draw_arc(center, radius, 0, TAU, 96, Color(0, 0, 0, 0.7), 3.5, true)
	draw_arc(center, radius, 0, TAU, 96, color, 1.5, true)
	for quarter in [0.0, PI]:
		draw_arc(center, radius + 6, quarter + 0.35, quarter + PI - 0.35, 48, Color(color, 0.45), 1, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius + 9), center + direction * (radius + 13), Color(color, 0.65), 1.2, true)
	draw_circle(center, 1.4, color)
	if arena.hit_flash > 0:
		for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * 5, center + direction * 9, color, 2, true)
