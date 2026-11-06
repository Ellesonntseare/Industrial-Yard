extends Control

var arena: Node3D
var expanded := false
var live_feed := false
var compact_span := 90.0
var zoom := 1.0
var pan := Vector2.ZERO
var feed_view: SubViewport
var feed_camera: Camera3D
var hd_map: Texture2D
var feed_clock := 0.0
var feed_ready := false
var drag_start := Vector2.ZERO
var dragging := false
var dragged := false
var touch_points: Dictionary = {}
var pinch_distance := 0.0
var latest_size := Vector2i.ZERO
const CYAN := Color("79e4ed")
const AMBER := Color("ffbd59")
const RED := Color("ff6f79")
const MAP_PATH := "res://assets/ui/yard-overhead-4096.png"
const HD_SPAN := 392.3685063
var circle_outline := PackedVector2Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(MAP_PATH): hd_map = load(MAP_PATH) as Texture2D
	for i in range(96):
		circle_outline.append(Vector2.from_angle(TAU * i / 96.0))

func toggle_map() -> void:
	expanded = not expanded
	dragging = false
	touch_points.clear()
	pinch_distance = 0
	if expanded:
		zoom = 1.0
		pan = Vector2.ZERO
	if expanded: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif arena.has_method("capture_game_pointer"): arena.capture_game_pointer()
	else: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_redraw()

func _process(delta: float) -> void:
	if not arena or not arena.active or not arena.fighters.has(arena.local_id):
		if feed_view: feed_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if DisplayServer.get_name() == "headless": return
	if not live_feed:
		if feed_view: feed_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_redraw()
		return
	if not is_instance_valid(feed_view): _build_feed()
	var desired_size := Vector2i(768,768) if expanded else Vector2i(512,512)
	if not OS.has_feature("mobile"): desired_size = Vector2i(1024,1024) if expanded else Vector2i(768,768)
	if desired_size != latest_size:
		feed_view.size = desired_size
		latest_size = desired_size
	feed_clock += delta
	var cadence := 1.0 / (8.0 if OS.has_feature("mobile") else 12.0)
	if feed_clock >= cadence:
		feed_clock = fmod(feed_clock,cadence)
		var focus := map_focus()
		feed_camera.size = map_span()
		feed_camera.global_position = Vector3(focus.x,arena.arena_bounds.end.y + 220,focus.y)
		feed_camera.look_at(Vector3(focus.x,0,focus.y),Vector3.FORWARD)
		feed_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		feed_ready = true
	queue_redraw()

func _build_feed() -> void:
	feed_view = SubViewport.new()
	feed_view.name = "LiveOverheadMap"
	feed_view.world_3d = arena.get_world_3d()
	feed_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	feed_view.gui_disable_input = true
	feed_view.msaa_3d = Viewport.MSAA_DISABLED
	add_child(feed_view)
	feed_camera = Camera3D.new()
	feed_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	feed_camera.far = 1500
	feed_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	feed_view.add_child(feed_camera)
	feed_camera.make_current()

func map_span() -> float:
	var full_span: float = maxf(arena.arena_bounds.size.x,arena.arena_bounds.size.z)*1.05
	return full_span / zoom if expanded else compact_span

func map_focus() -> Vector2:
	if expanded: return Vector2(arena.zone_center.x,arena.zone_center.z)+pan
	var position: Vector3 = arena.fighters[arena.local_id].position
	return Vector2(position.x,position.z)

func map_radius() -> float:
	return minf(get_viewport_rect().size.y*.38,360.0) if expanded else clampf(get_viewport_rect().size.y*.145,82,120)

func map_center() -> Vector2:
	return get_viewport_rect().size*.5 if expanded else Vector2(map_radius()+24,map_radius()+35)

func contains_point(point: Vector2) -> bool:
	return point.distance_to(map_center()) < map_radius()+10

func _zoom(factor: float) -> void:
	if expanded: zoom = clampf(zoom*factor,1,8)
	else: compact_span = clampf(compact_span/factor,35,220)
	feed_clock = 1
	queue_redraw()

func _pan(relative: Vector2) -> void:
	pan -= relative * map_span()/(map_radius()*2)
	var limit: float = maxf(arena.arena_bounds.size.x,arena.arena_bounds.size.z)*.5
	pan = pan.clamp(Vector2.ONE*-limit,Vector2.ONE*limit)
	feed_clock = 1

func _input(event: InputEvent) -> void:
	if not arena or not arena.active or arena.menu.visible: return
	if event is InputEventKey and event.pressed and expanded:
		if event.physical_keycode in [KEY_EQUAL,KEY_KP_ADD]:
			_zoom(1.25)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_MINUS,KEY_KP_SUBTRACT]:
			_zoom(.8)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_L:
			live_feed = not live_feed
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		var over := contains_point(event.position)
		if expanded and event.pressed and event.position.distance_to(map_center()+Vector2(-map_radius()+45,map_radius()+49))<50:
			live_feed = not live_feed
			get_viewport().set_input_as_handled()
			return
		if event.pressed and over and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.2)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and over:
				if not expanded: toggle_map()
				else:
					dragging = true
					dragged = false
					drag_start = event.position
				get_viewport().set_input_as_handled()
			elif not event.pressed and dragging:
				dragging = false
				if not dragged: toggle_map()
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_start)>6: dragged = true
		if dragged: _pan(event.relative)
		get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.pressed and (contains_point(event.position) or expanded):
			if not expanded:
				toggle_map()
				dragged = true
			else:
				dragged = false
				drag_start = event.position
			touch_points[event.index] = event.position
			get_viewport().set_input_as_handled()
		elif not event.pressed and touch_points.has(event.index):
			touch_points.erase(event.index)
			if touch_points.is_empty() and not dragged: toggle_map()
			pinch_distance = 0
			get_viewport().set_input_as_handled()
	if event is InputEventScreenDrag and touch_points.has(event.index):
		touch_points[event.index] = event.position
		if touch_points.size()>=2:
			var points: Array = touch_points.values()
			var separation: float = points[0].distance_to(points[1])
			if pinch_distance>1: _zoom(separation/pinch_distance)
			pinch_distance = separation
			dragged = true
		else:
			if event.position.distance_to(drag_start)>8: dragged = true
			if dragged: _pan(event.relative)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not arena or not arena.active or not arena.fighters.has(arena.local_id): return
	var radius := map_radius()
	var center := map_center()
	var focus := map_focus()
	var span := map_span()
	var factor := radius*2/span
	if expanded: draw_rect(get_viewport_rect(),Color(0.01,0.025,0.035,.90))
	draw_circle(center,radius+9,Color(0.018,0.035,0.045,.98))
	var texture: Texture2D
	var use_live := live_feed and feed_ready and is_instance_valid(feed_view)
	if use_live: texture = feed_view.get_texture()
	elif hd_map: texture = hd_map
	else: texture = arena.minimap_texture
	if texture:
		var full_span := HD_SPAN if texture==hd_map else maxf(arena.arena_bounds.size.x,arena.arena_bounds.size.z)*1.05
		var uv_center := Vector2.ONE*.5 if use_live else Vector2.ONE*.5 + (focus-Vector2(arena.zone_center.x,arena.zone_center.z))/full_span
		var crop := 1.0 if use_live else span/full_span
		draw_map_texture(texture, center, radius, uv_center, crop)
	draw_arc(center,radius+3,0,TAU,128,CYAN,2,true)
	var zone := center+(Vector2(arena.zone_center.x,arena.zone_center.z)-focus)*factor
	var zr: float = arena.zone_radius*factor
	for index in range(256):
		var a := zone+Vector2.from_angle(TAU*index/256)*zr
		var b := zone+Vector2.from_angle(TAU*(index+1)/256)*zr
		if a.distance_to(center)<radius and b.distance_to(center)<radius: draw_line(a,b,Color("73eeb0"),2,true)
	for id in arena.loot:
		var item: Dictionary = arena.loot[id]
		if item.ready>0: continue
		var at := center+(Vector2(item.p.x,item.p.z)-focus)*factor
		if at.distance_to(center)<radius-8: draw_circle(at,2.0,Color("d9d3a7"))
	# Permanent markers intentionally ignore line of sight, per user choice.
	for id in arena.fighters:
		var body = arena.fighters[id]
		var self_marker: bool = id==arena.local_id
		var color := AMBER if self_marker else RED
		var offset := (Vector2(body.position.x,body.position.z)-focus)*factor
		var offscreen := offset.length()>radius-12
		var at := center+offset.limit_length(radius-12)
		var yaw: float = arena.look_yaw if self_marker else body.yaw
		var direction := Vector2(-sin(yaw),-cos(yaw))
		var side := direction.orthogonal()
		if body.phase=="dead":
			draw_circle(at,7,Color(0.03,0.04,0.05,.9))
			draw_line(at-Vector2(4,4),at+Vector2(4,4),color,2,true)
			draw_line(at-Vector2(4,-4),at+Vector2(4,-4),color,2,true)
		else:
			draw_circle(at,10,Color(0.02,0.025,0.03,.95))
			draw_colored_polygon(PackedVector2Array([at+direction*8,at-direction*5+side*5,at-direction*5-side*5]),color)
		if expanded:
			var label := "YOU" if self_marker else "FRIEND"
			if body.phase=="dead": label+=" / RESPAWNING"
			draw_string(ThemeDB.fallback_font,at+Vector2(13,5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
		elif offscreen: draw_arc(at,11,0,TAU,24,color,1,true)
	draw_string(ThemeDB.fallback_font,center+Vector2(-6,-radius-10),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,17,CYAN)
	var label_rect := Rect2(center+Vector2(-radius,radius+15),Vector2(radius*2,27))
	draw_rect(label_rect,Color(.02,.04,.055,.95))
	draw_string(ThemeDB.fallback_font,label_rect.position+Vector2(8,19),("LIVE" if use_live else "HD MAP")+"  /  BOTH PLAYERS",HORIZONTAL_ALIGNMENT_LEFT,-1,13,CYAN)
	if expanded:
		draw_string(ThemeDB.fallback_font,center+Vector2(-radius,radius+54),"LIVE/HD [L]     ZOOM + / -     DRAG TO PAN",HORIZONTAL_ALIGNMENT_LEFT,-1,14,CYAN)
		draw_string(ThemeDB.fallback_font,center+Vector2(-radius,radius+77),"AMBER: YOU  /  RED: FRIEND  /  TAP TO CLOSE",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("bed8dc"))

func draw_map_texture(texture: Texture2D, center: Vector2, radius: float, uv_center: Vector2, crop: float) -> void:
	var points := PackedVector2Array()
	for point in circle_outline: points.append(center + point * radius)
	var pixels_per_uv := radius * 2.0 / crop
	var image_start := center - uv_center * pixels_per_uv
	var image_end := image_start + Vector2.ONE * pixels_per_uv
	var image_rect := Rect2(image_start, image_end - image_start)
	if not image_rect.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)):
		var border := PackedVector2Array([image_start, Vector2(image_end.x, image_start.y), image_end, Vector2(image_start.x, image_end.y)])
		var clipped := Geometry2D.intersect_polygons(points, border)
		if clipped.is_empty(): return
		points = clipped[0]
	if points.size() < 3: return
	var uvs := PackedVector2Array()
	for point in points: uvs.append((point - image_start) / pixels_per_uv)
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, texture)
