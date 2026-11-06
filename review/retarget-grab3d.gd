extends SceneTree

var report := {}
const CATALOG = preload("res://characters_catalog.gd")

func _initialize() -> void: call_deferred("run")

func source_bone(rig: Skeleton3D, name: String) -> int:
	var pattern := name
	if name=="Chest":pattern="Spine1"
	if name=="Toe":pattern="ToeBase"
	if name.ends_with("Toe"):pattern=name+"Base"
	for i in range(rig.get_bone_count()):
		if rig.get_bone_name(i).begins_with("Bind_"+pattern+"_"):return i
	return -1

func child_for(rig: Skeleton3D,bone: int) -> int:
	var preferred := {"Hips":"Spine","Spine":"Chest","Chest":"Neck","Neck":"Head"}
	var name := rig.get_bone_name(bone)
	if preferred.has(name):return rig.find_bone(preferred[name])
	for i in range(rig.get_bone_count()):
		if rig.get_bone_parent(i)==bone:return i
	return -1

func run() -> void:
	var stage:=Node3D.new();root.add_child(stage)
	var source=load("res://assets/provided/training_soldier.glb").instantiate();stage.add_child(source)
	var source_rig: Skeleton3D=source.find_children("*","Skeleton3D",true,false)[0]
	var player: AnimationPlayer=source.find_children("*","AnimationPlayer",true,false)[0]
	player.stop()
	for id in CATALOG.IDS:
		var target=CATALOG.scene_for(id).instantiate();stage.add_child(target)
		var rig: Skeleton3D=target.find_children("*","Skeleton3D",true,false)[0]
		var library:=AnimationLibrary.new()
		for clip_name in player.get_animation_list():
			if clip_name=="RESET":continue
			var original:=player.get_animation(clip_name)
			var clip:=Animation.new();clip.length=original.length;clip.loop_mode=original.loop_mode
			var tracks: Array[int]=[]
			var source_map: Array[int]=[]
			for bone in range(rig.get_bone_count()):
				var t:=clip.add_track(Animation.TYPE_ROTATION_3D)
				clip.track_set_path(t,NodePath(String(target.get_path_to(rig))+":"+rig.get_bone_name(bone)))
				tracks.append(t);source_map.append(source_bone(source_rig,rig.get_bone_name(bone)))
			var count:=maxi(2,ceili(clip.length*24)+1)
			player.play(clip_name)
			for frame in range(count):
				var time:=minf(frame/24.0,clip.length)
				player.seek(time,true);player.advance(0)
				source_rig.force_update_all_bone_transforms()
				var globals: Array[Transform3D]=[]
				for bone in range(rig.get_bone_count()):
					var parent:=rig.get_bone_parent(bone)
					var parent_pose:=globals[parent] if parent>=0 else Transform3D.IDENTITY
					var local:=rig.get_bone_rest(bone)
					var posed:=parent_pose*local
					var source_index:=source_map[bone]
					var child:=child_for(rig,bone)
					if source_index>=0 and child>=0:
						var source_child:=source_bone(source_rig,rig.get_bone_name(child))
						if source_child>=0:
							var a:=source_rig.get_bone_global_pose(source_index).origin
							var b:=source_rig.get_bone_global_pose(source_child).origin
							var desired:=source_rig.global_basis*(b-a)
							desired=rig.global_basis.inverse()*desired
							var current:=posed.basis*rig.get_bone_rest(child).origin
							if desired.length_squared()>.000001 and current.length_squared()>.000001:
								posed.basis=Basis(Quaternion(current.normalized(),desired.normalized()))*posed.basis
								local.basis=parent_pose.basis.inverse()*posed.basis
					globals.append(posed)
					clip.rotation_track_insert_key(tracks[bone],time,local.basis.orthonormalized().get_rotation_quaternion())
			library.add_animation(clip_name,clip)
		ResourceSaver.save(library,"res://assets/characters/"+id+"_motions.tres")
		report[id]={"animations":library.get_animation_list().size(),"bones":rig.get_bone_count()}
		target.free()
	print("RETARGET_COMPLETE ",JSON.stringify(report))
	quit()
