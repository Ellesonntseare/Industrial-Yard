extends Control
## Unified PC/Android HUD and multitouch control state.
## Host reads merge_controls() after building its keyboard command dictionary.

var arena: Node3D
var movement := Vector2.ZERO
var sprinting := false
var aiming := false
var firing := false
var crouching := false
var sensitivity := 0.0028
var touch_layout := false
var button_scale := 1.0
var button_opacity := 0.62
var editing := false
var finger_roles: Dictionary = {}
var positions: Dictionary = {}
var settings: PanelContainer
var settings_open := false
var auto_ammo := false
var last_auto_pickup := 0.0
var joystick_finger := -99
var look_finger := -99
var drag_finger := -99
var drag_name := ""
var last_phase := ""
var loot_hint := ""
var loot_kind := -1
var frame_scale := 1.0
var frame_size := Vector2(1600,900)
var font := ThemeDB.fallback_font
var last_health := 100.0
const CYAN = Color("8deaf2")
const AMBER = Color("ffb63d")
const PANEL = Color(0.025,0.04,0.055,0.87)
const CONFIG = "user://industrial-yard-controls.cfg"
const DEFAULTS = {
	"move": Vector2(.095,.73), "run": Vector2(.095,.55),
	"aim": Vector2(.84,.53), "fire": Vector2(.93,.61),
	"jump": Vector2(.93,.79), "crouch": Vector2(.84,.79),
	"reload": Vector2(.76,.85), "camera": Vector2(.94,.30),
	"heal": Vector2(.44,.92), "grenade": Vector2(.50,.92),
	"bag": Vector2(.56,.92), "interact": Vector2(.50,.78)
}

func setup(owner_arena: Node3D) -> void:
	arena = owner_arena

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	positions = DEFAULTS.duplicate()
	touch_layout = OS.has_feature("android") or "--touch-preview" in OS.get_cmdline_user_args()
	load_preferences()
	build_settings()

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG) != OK: return
	button_scale = clampf(float(config.get_value("controls","scale",1)),.75,1.45)
	button_opacity = clampf(float(config.get_value("controls","opacity",.62)),.25,1)
	sensitivity = clampf(float(config.get_value("controls","sensitivity",.0028)),.0008,.008)
	auto_ammo = bool(config.get_value("controls","auto_ammo",false))
	for key in DEFAULTS:
		var value = config.get_value("positions",key,DEFAULTS[key])
		if value is Vector2 and value.is_finite(): positions[key] = value.clamp(Vector2(.04,.08),Vector2(.96,.94))

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("controls","scale",button_scale)
	config.set_value("controls","opacity",button_opacity)
	config.set_value("controls","sensitivity",sensitivity)
	config.set_value("controls","auto_ammo",auto_ammo)
	for key in positions: config.set_value("positions",key,positions[key])
	config.save(CONFIG)

func reset_inputs() -> void:
	movement = Vector2.ZERO
	sprinting = false
	aiming = false
	firing = false
	crouching = false
	finger_roles.clear()
	joystick_finger = -99
	look_finger = -99
	drag_finger = -99
	drag_name = ""

func playable() -> bool:
	return arena != null and arena.active and not arena.menu.visible and not settings_open and not editing and arena.fighters.has(arena.local_id) and arena.fighters[arena.local_id].phase != "dead" and arena.end_text.is_empty()

func merge_controls(command: Dictionary) -> Dictionary:
	if not playable():
		command.move = Vector2.ZERO
		command.run = false
		command.fire = false
		command.aim = false
		command.crouch = false
		return command
	command.move = (command.move + movement).limit_length()
	command.run = command.run or sprinting
	# Touch-to-mouse emulation must not turn joystick/setup touches into shots.
	command.fire = firing if touch_layout else command.fire
	command.aim = aiming if touch_layout else command.aim
	command.crouch = command.crouch or crouching
	return command

func set_settings(opened: bool) -> void:
	settings_open = opened
	settings.visible = opened
	reset_inputs()
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		save_preferences()
		if arena and arena.active and not arena.menu.visible and not touch_layout: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func build_settings() -> void:
	settings = PanelContainer.new()
	settings.position = Vector2(32,32)
	settings.custom_minimum_size = Vector2(390,0)
	settings.mouse_filter = Control.MOUSE_FILTER_STOP
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(.025,.04,.055,.98)
	box_style.border_color = CYAN
	box_style.set_border_width_all(2)
	box_style.set_content_margin_all(18)
	settings.add_theme_stylebox_override("panel",box_style)
	add_child(settings)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",12)
	settings.add_child(list)
	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size",24)
	list.add_child(title)
	add_slider(list,"Button size",.75,1.45,button_scale,func(v): button_scale=v)
	add_slider(list,"Button opacity",.25,1,button_opacity,func(v): button_opacity=v)
	add_slider(list,"Aiming sensitivity",.0008,.008,sensitivity,func(v): sensitivity=v)
	var auto := CheckButton.new()
	auto.text = "Automatically pick up nearby ammo"
	auto.button_pressed = auto_ammo
	auto.toggled.connect(func(v): auto_ammo=v; save_preferences())
	list.add_child(auto)
	var preview := CheckButton.new()
	preview.text = "Show phone controls on this screen"
	preview.button_pressed = touch_layout
	preview.toggled.connect(func(v): touch_layout=v; reset_inputs())
	list.add_child(preview)
	add_button(list,"MOVE BUTTONS",func(): touch_layout=true; editing=true; set_settings(false))
	add_button(list,"RESET BUTTON POSITIONS",func(): positions=DEFAULTS.duplicate(); save_preferences())
	add_button(list,"SAVE AND CLOSE",func(): set_settings(false))
	settings.hide()

func add_slider(list: VBoxContainer,title: String,low: float,high: float,value: float,change: Callable) -> void:
	var label := Label.new()
	label.text = title
	list.add_child(label)
	var slider := HSlider.new()
	slider.min_value=low
	slider.max_value=high
	slider.step=(high-low)/100
	slider.value=value
	slider.custom_minimum_size=Vector2(350,32)
	slider.value_changed.connect(change)
	list.add_child(slider)

func add_button(list: VBoxContainer,title: String,action: Callable) -> void:
	var button := Button.new()
	button.text=title
	button.custom_minimum_size.y=42
	button.pressed.connect(action)
	list.add_child(button)

func center(key: String) -> Vector2:
	return positions[key]*frame_size

func radius(key: String) -> float:
	return (80.0 if key=="move" else 57.0 if key=="fire" else 39.0)*button_scale

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: reset_inputs()

func _input(event: InputEvent) -> void:
	if arena == null: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F8:
		set_settings(not settings_open)
		get_viewport().set_input_as_handled()
		return
	if settings_open: return
	var idx := -99
	var point := Vector2.ZERO
	var pressed := false
	var is_press := false
	var is_drag := false
	var delta := Vector2.ZERO
	if event is InputEventScreenTouch:
		idx=event.index;point=event.position;pressed=event.pressed;is_press=true
	elif event is InputEventScreenDrag:
		idx=event.index;point=event.position;delta=event.relative;is_drag=true
	elif touch_layout and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		idx=-1;point=event.position;pressed=event.pressed;is_press=true
	elif touch_layout and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		idx=-1;point=event.position;delta=event.relative;is_drag=true
	else: return
	point/=frame_scale
	if is_press and not pressed:
		if idx==joystick_finger: movement=Vector2.ZERO;joystick_finger=-99
		if idx==look_finger: look_finger=-99
		if finger_roles.get(idx,"")=="fire": firing=false
		finger_roles.erase(idx)
		if idx==drag_finger: drag_finger=-99;drag_name="";save_preferences()
		return
	if is_press and pressed:
		if Rect2(frame_size.x-104,178,76,42).has_point(point):
			set_settings(true);get_viewport().set_input_as_handled();return
		if editing:
			if Rect2(frame_size.x/2-160,32,320,52).has_point(point):
				editing=false;save_preferences();get_viewport().set_input_as_handled();return
			for key in positions:
				if point.distance_to(center(key))<=radius(key)+12:
					drag_name=key;drag_finger=idx;get_viewport().set_input_as_handled();return
			return
		if not playable(): return
		# Reserve the top-left map for tap-to-expand; radar handles its own gestures.
		if point.x<290 and point.y<290:return
		if not touch_layout:return
		for key in positions:
			if key=="interact" and loot_hint.is_empty():continue
			var inside := Rect2(center(key)-Vector2(170,26),Vector2(340,52)).has_point(point) if key=="interact" else point.distance_to(center(key))<=radius(key)+8
			if inside:
				finger_roles[idx]=key
				match key:
					"move": joystick_finger=idx; update_joystick(point)
					"run": sprinting=not sprinting
					"aim": aiming=not aiming
					"fire": firing=true
					"crouch": crouching=not crouching
					"camera": arena.third_person=not arena.third_person
					"bag": arena.message("SUPPLIES: ammo, medkits and grenades are shown below")
					"heal": arena.request_action("heal")
					"jump": arena.request_action("jump")
					"reload": arena.request_action("reload")
					"grenade": arena.request_action("grenade")
					"interact": arena.request_action("interact")
				get_viewport().set_input_as_handled();return
		if point.x>frame_size.x*.36 and point.y>165:
			look_finger=idx;finger_roles[idx]="look";get_viewport().set_input_as_handled()
	elif is_drag:
		if editing and idx==drag_finger and not drag_name.is_empty():
			positions[drag_name]=(point/frame_size).clamp(Vector2(.04,.08),Vector2(.96,.94));get_viewport().set_input_as_handled()
		elif idx==joystick_finger:
			update_joystick(point);get_viewport().set_input_as_handled()
		elif idx==look_finger and playable():
			arena.look_yaw-=delta.x*sensitivity
			arena.look_pitch=clampf(arena.look_pitch-delta.y*sensitivity,-1.45,1.45)
			get_viewport().set_input_as_handled()

func update_joystick(point: Vector2) -> void:
	movement=((point-center("move"))/radius("move")).limit_length()
	if movement.length()<.12:movement=Vector2.ZERO

func _process(delta: float) -> void:
	frame_scale=minf(get_viewport_rect().size.x/1600.0,get_viewport_rect().size.y/900.0)
	frame_scale=maxf(frame_scale,.1)
	frame_size=get_viewport_rect().size/frame_scale
	if arena==null:return
	visible=arena.active
	if not visible:return
	if not arena.fighters.has(arena.local_id):return
	var body=arena.fighters[arena.local_id]
	if body.phase!=last_phase:
		if body.phase=="dead" or last_phase=="dead":reset_inputs()
		last_phase=body.phase
	if arena.menu.visible:reset_inputs()
	update_loot_hint(body)
	last_auto_pickup-=delta
	if auto_ammo and playable() and loot_kind==1 and last_auto_pickup<=0:
		arena.request_action("interact");last_auto_pickup=.4
	queue_redraw()

func update_loot_hint(body) -> void:
	loot_hint="";loot_kind=-1
	if body.phase!="ground":return
	for crate in arena.crates:
		if not crate.opened and body.position.distance_to(crate.position)<2.6:
			loot_hint="OPEN SUPPLY CACHE";return
	for id in arena.loot:
		if arena.loot[id].ready==0 and body.position.distance_to(arena.loot[id].p)<2.8:
			loot_kind=arena.loot[id].kind;loot_hint="PICK UP "+arena.KINDS[loot_kind];return
	for door in arena.doors:
		if body.position.distance_to(door.global_position)<2.6:
			loot_hint="USE DOOR";return

func panel(rect: Rect2) -> void:
	var s:=StyleBoxFlat.new()
	s.bg_color=PANEL;s.border_color=Color(.5,.75,.8,.6)
	s.set_border_width_all(1);s.set_corner_radius_all(7)
	draw_style_box(s,rect)

func text(at: Vector2,value: String,size_px: int=20,color: Color=Color.WHITE) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func touch_button(key: String,label: String,on: bool=false) -> void:
	var p:=center(key);var r:=radius(key)
	draw_circle(p,r,Color(.02,.04,.05,button_opacity))
	draw_arc(p,r,0,TAU,48,AMBER if on else CYAN if key in ["fire","run"] else Color(.9,.95,.96,.7),2,true)
	var width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	text(p+Vector2(-width/2,6),label,16)
	if editing:draw_circle(p,4,AMBER)

func _draw() -> void:
	if arena==null or not arena.active or not arena.fighters.has(arena.local_id):return
	if arena.radar.expanded:return
	var body=arena.fighters[arena.local_id]
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*frame_scale)
	var w:=frame_size.x;var h:=frame_size.y
	panel(Rect2(30,h-99,315,74))
	text(Vector2(47,h-69),"+ %s"%ceili(body.hp),25)
	draw_rect(Rect2(147,h-84,176,11),Color(.12,.18,.21))
	draw_rect(Rect2(147,h-84,176*clampf(body.hp/100,0,1),11),Color.WHITE)
	text(Vector2(47,h-40),"<> %s"%ceili(body.armor),23,CYAN)
	draw_rect(Rect2(147,h-55,176,10),Color(.12,.18,.21))
	draw_rect(Rect2(147,h-55,176*clampf(body.armor/75,0,1),10),CYAN)
	panel(Rect2(w-250,h-99,220,74))
	text(Vector2(w-232,h-74),"CARBINE" if body.weapon else "NO WEAPON",16)
	text(Vector2(w-232,h-39),"%s / %s"%[body.magazine,body.ammo] if body.weapon else "FIND A RIFLE",29 if body.weapon else 21)
	if body.reload_left>0:text(Vector2(w-232,h-115),"RELOADING",17,AMBER)
	var peer_score:=0
	for id in arena.fighters:
		if id!=arena.local_id:peer_score=arena.fighters[id].score
	panel(Rect2(w-323,24,290,54))
	text(Vector2(w-305,59),"YOU %s  :  %s FRIEND"%[body.score,peer_score],23)
	text(Vector2(w-190,107),"%02d:%02d"%[int(arena.clock)/60,int(arena.clock)%60],22)
	panel(Rect2(w-104,178,76,42));text(Vector2(w-95,205),"SETUP",16)
	text(Vector2(w/2-125,37),"N     |     E     |     S     |     W",17,CYAN)
	if body.phase in ["helicopter","fall","parachute"]:
		var message: String={"helicopter":"RELEASE FROM ROPE","fall":"DEPLOY PARACHUTE","parachute":"STEER TO LAND"}[body.phase]
		panel(Rect2(w/2-200,70,400,40));text(Vector2(w/2-180,98),message,21,AMBER)
		text(Vector2(w/2-95,137),"ALTITUDE %sm"%int(body.position.y),18)
	if touch_layout:
		for key in ["move","run","aim","fire","jump","crouch","reload","camera","heal","grenade","bag"]:
			var label: String={"move":"MOVE","run":"RUN","aim":"AIM","fire":"FIRE","jump":"RELEASE" if body.phase=="helicopter" else "DEPLOY" if body.phase=="fall" else "JUMP","crouch":"CROUCH","reload":"RELOAD","camera":"VIEW","heal":"+ %s"%body.medkits,"grenade":"G %s"%body.grenades,"bag":"BAG"}[key]
			touch_button(key,label,(key=="run" and sprinting) or (key=="aim" and aiming) or (key=="crouch" and crouching))
		draw_circle(center("move")+movement*radius("move")*.65,27*button_scale,Color(.65,.8,.83,.45))
	else:
		panel(Rect2(w/2-155,h-80,310,52))
		text(Vector2(w/2-135,h-47),"H  + %s     G  %s     %s"%[body.medkits,body.grenades,"BACKPACK" if body.backpack else "BAG -"],20)
		text(Vector2(32,h-120),"SHIFT RUN   V VIEW   M MAP   F8 CONTROLS",15,CYAN)
	if not loot_hint.is_empty():
		var p:=center("interact")
		panel(Rect2(p-Vector2(170,26),Vector2(340,52)))
		text(p+Vector2(-151,7),("" if touch_layout else "E  ")+loot_hint,21,AMBER)
	if editing:
		panel(Rect2(w/2-220,20,440,90))
		text(Vector2(w/2-200,49),"DRAG BUTTONS TO MOVE THEM",20,AMBER)
		text(Vector2(w/2-140,84),"TAP HERE TO SAVE",20)
	if body.phase=="dead":
		draw_rect(Rect2(0,0,w,h),Color(.025,.02,.025,.58))
		panel(Rect2(w/2-235,h/2-105,470,180))
		text(Vector2(w/2-142,h/2-51),"ELIMINATED",38,Color("ff6874"))
		text(Vector2(w/2-174,h/2),"RESPAWNING IN %s"%ceili(body.respawn_left),29)
		text(Vector2(w/2-177,h/2+43),"Returning to the helicopter",20,CYAN)
	if not arena.end_text.is_empty():
		panel(Rect2(w/2-280,h/2-70,560,135))
		text(Vector2(w/2-250,h/2-20),arena.end_text,32,AMBER)
		text(Vector2(w/2-250,h/2+25),"Host: F5 rematch / Esc menu",22)
	draw_set_transform(Vector2.ZERO)
