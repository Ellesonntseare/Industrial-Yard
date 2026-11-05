extends RefCounted

# Original prototype poses, generated on the current rig's rest skeleton.
# All limb lengths and parent relationships are preserved.
static func attach(model: Node3D, animator: AnimationPlayer) -> void:
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty(): return
	var rig: Skeleton3D = rigs[0]
	var root := animator.get_node(animator.root_node)
	var path := String(root.get_path_to(rig))
	var library := AnimationLibrary.new()
	for kind in ["Seat", "Fall", "Pull", "Glide", "Land"]:
		var clip := Animation.new()
		clip.length = 0.55 if kind == "Pull" else (0.35 if kind == "Land" else 2.0)
		clip.loop_mode = Animation.LOOP_NONE if kind in ["Pull", "Land"] else Animation.LOOP_LINEAR
		var poses := solve_pose(rig, model, kind)
		for bone in range(rig.get_bone_count()):
			var track := clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(track, NodePath(path + ":" + rig.get_bone_name(bone)))
			var q: Quaternion = poses[bone]
			clip.rotation_track_insert_key(track, 0, q)
			clip.rotation_track_insert_key(track, clip.length, q)
			var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
			clip.track_set_path(position_track, NodePath(path + ":" + rig.get_bone_name(bone)))
			var offset := rig.get_bone_rest(bone).origin
			clip.position_track_insert_key(position_track, 0, offset)
			clip.position_track_insert_key(position_track, clip.length, offset)
		library.add_animation("Sky" + kind, clip)
	animator.add_animation_library("sky", library)

static func solve_pose(rig: Skeleton3D, model: Node3D, kind: String) -> Array[Quaternion]:
	var orientations: Array[Quaternion] = []
	var globals: Array[Transform3D] = []
	var desired: Dictionary = {}
	var children: Dictionary = {}
	for i in range(rig.get_bone_count()):
		var name := rig.get_bone_name(i).to_lower()
		var side := 1.0 if "left" in name else -1.0
		var target := Vector3.ZERO
		if "left" in name or "right" in name:
			if "upperarm" in name or "uparm" in name or ("arm" in name and "fore" not in name and "shoulder" not in name and "pole" not in name):
				if kind == "Fall": target = Vector3(side, -0.15, -0.2)
				elif kind in ["Glide", "Pull"]: target = Vector3(side * 0.6, 0.8, 0)
				else: target = Vector3(side * 0.15, -0.7, -0.3)
			elif "forearm" in name or "lowerarm" in name:
				if kind == "Fall": target = Vector3(side * 0.25, 0.15, -0.8)
				elif kind in ["Glide", "Pull"]: target = Vector3(-side * 0.2, 1.0, -0.15)
				else: target = Vector3(side * 0.05, -0.2, -0.8)
			elif "upleg" in name or "thigh" in name:
				if kind == "Seat": target = Vector3(side * 0.12, -0.15, -1)
				elif kind == "Fall": target = Vector3(side * 0.3, -1, 0.05)
				elif kind == "Land": target = Vector3(side * 0.15, -1, -0.25)
				else: target = Vector3(side * 0.15, -1, -0.15)
			elif "leg" in name and "up" not in name and "pole" not in name:
				if kind == "Seat": target = Vector3(0, -1, 0)
				elif kind == "Fall": target = Vector3(side * 0.1, -0.7, 0.65)
				else: target = Vector3(0, -1, 0.12)
		if target != Vector3.ZERO:
			desired[i] = rig.global_basis.inverse() * model.get_parent().global_basis * target.normalized()
		var parent := rig.get_bone_parent(i)
		if parent >= 0 and not children.has(parent): children[parent] = i
	for bone in range(rig.get_bone_count()):
		var parent := rig.get_bone_parent(bone)
		var parent_pose := globals[parent] if parent >= 0 else Transform3D.IDENTITY
		var local := rig.get_bone_rest(bone)
		var posed := parent_pose * local
		if desired.has(bone) and children.has(bone):
			var child_rest := rig.get_bone_rest(children[bone])
			var current := (posed.basis * child_rest.origin).normalized()
			if current.length_squared() > 0.5:
				var turn := Quaternion(current, Vector3(desired[bone]).normalized())
				posed.basis = Basis(turn) * posed.basis
				local.basis = parent_pose.basis.inverse() * posed.basis
		globals.append(posed)
		orientations.append(local.basis.orthonormalized().get_rotation_quaternion())
	return orientations
