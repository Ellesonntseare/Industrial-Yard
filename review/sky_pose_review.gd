extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var views: Array[SubViewport] = []
	var names := ["Seat", "Fall", "Pull", "Glide", "Steering", "Land"]
	var errors := []
	for name in names:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(480, 400)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("243342")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.9
		world.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-35, -35, 0)
		world.add_child(light)
		var body = load("res://arena_player.gd").new()
		world.add_child(body)
		body.set_process(false)
		body.rotation.y = PI
		body.phase = "fall" if name == "Fall" else ("parachute" if name in ["Pull", "Glide", "Steering"] else ("ground" if name == "Land" else "helicopter"))
		body.canopy.visible = name in ["Pull", "Glide", "Steering"]
		body.animator.play("sky/Sky" + ("Glide" if name == "Steering" else name), 0)
		body.animator.seek(0.2, true)
		body.animator.advance(0)
		body.animator.pause()
		if body.embedded_gun: body.embedded_gun.hide()
		if name == "Fall": body.visual.rotation.x = -PI / 2
		if name == "Steering": body.visual.rotation.z = -0.18
		if body.canopy.visible:
			body.visual_dive = 0.9 if name == "Steering" else 0.0
			body.update_parachute_visual(0.72 if name == "Pull" else 1.0)
		var rig: Skeleton3D = body.model_root.find_children("*", "Skeleton3D", true, false)[0]
		for bone in range(rig.get_bone_count()):
			if "LeftArm_" in rig.get_bone_name(bone):
				print("SKY_ARM ", name, " ", rig.get_bone_pose_rotation(bone), " track=", body.animator.get_animation("sky/Sky" + ("Glide" if name == "Steering" else name)).track_get_path(bone * 2))
		print("SKY_GUN ", name, " ", body.embedded_gun.get_path() if body.embedded_gun else "none")
		for bone in range(rig.get_bone_count()):
			var pos := rig.get_bone_global_pose(bone)
			if not pos.is_finite(): errors.append(name + ": non-finite bone " + rig.get_bone_name(bone))
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(2.8, 1.8, 3.6) if name not in ["Pull", "Glide", "Steering"] else Vector3(5, 4.0, 10)
		camera.look_at(Vector3(0, 1, 0) if name not in ["Pull", "Glide", "Steering"] else Vector3(0, 2.55, 0))
		camera.fov = 38
		camera.make_current()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(1440, 880, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("13202c"))
	for i in range(views.size()):
		var im := views[i].get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, 480, 400), Vector2i((i % 3) * 480, (i / 3) * 440))
	sheet.save_png("res://review/sky-poses.png")
	print("SKY_POSE_REVIEW errors=", errors, " passed=", errors.is_empty())
	quit(0 if errors.is_empty() else 1)
