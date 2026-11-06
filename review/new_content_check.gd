extends SceneTree

var checks: Dictionary = {}
var arena

func _initialize() -> void:call_deferred("run")

func record(name: String,passed: bool) -> void:
	checks[name]=passed
	if not passed:push_error("CHECK FAILED: "+name)

func run() -> void:
	arena=load("res://battle.tscn").instantiate()
	root.add_child(arena)
	current_scene=arena
	await process_frame
	await physics_frame
	arena.review_mode=true
	arena.practice()
	await process_frame
	var body=arena.fighters[1]
	body.phase="ground"
	body.position=arena.floor_at(arena.NORTH_ENTRY+Vector3(0,0,8))
	await physics_frame
	var present:Dictionary={}
	for item in arena.loot.values():
		if item.kind==0:present[item.get("weapon_id","")]=true
	record("all_weapons_in_world_loot",present.size()==arena.Weapons.ids().size())
	for id in arena.Weapons.ids():
		var at:Vector3=body.position
		for item in arena.loot.values():item.ready=9999
		var pickup:int=arena.add_loot(0,at,id)
		arena.interact(1)
		record("pickup_"+id,body.weapon_id==id and body.weapon and id in body.weapon_slots and arena.loot[pickup].ready>0)
		var capacity:int=arena.Weapons.definition(id).magazine
		record("capacity_"+id,body.magazine_capacity==capacity)
		var saved:int=body.magazine
		body.cooldown=0
		body.command={"move":Vector2.ZERO,"yaw":PI,"pitch":0.0,"run":false,"jump":false,"third_person":true}
		body.yaw=PI;body.pitch=0
		arena.shoot(1)
		record("fire_"+id,body.cooldown>0 and body.magazine==(saved if id=="knife" else saved-1))
	arena.equip_weapon(body,"pistol")
	body.magazine=3
	arena.equip_weapon(body,"shotgun")
	arena.equip_weapon(body,"pistol")
	record("switch_preserves_magazine",body.magazine==3)
	body.ammo=90
	arena.perform_action(1,"reload")
	body.step(2)
	record("pistol_reload_capacity",body.magazine==12 and body.ammo==81)
	for id in arena.Characters.IDS:
		body.set_character(id)
		await process_frame
		var rigs=body.model_root.find_children("*","Skeleton3D",true,false)
		record("character_"+id,body.character_id==id and rigs.size()==1 and rigs[0].get_bone_count()==21 and body.animator.has_animation("walk") and body.animator.has_animation("sky/SkyFall"))
		body.drop(arena.drop_position(1))
		record("character_respawn_"+id,body.character_id==id)
	var remote=arena.Fighter.new()
	root.add_child(remote)
	remote.unpack(body.pack(),false)
	record("snapshot_character",remote.character_id==body.character_id)
	record("snapshot_weapon",remote.weapon_id==body.weapon_id)
	remote.free()
	body.phase="ground"
	body.position=arena.floor_at(arena.NORTH_ENTRY+Vector3(0,0,8))
	body.c4_count=2
	# Aim at the actual side wall, place and detonate via authority.
	body.yaw=PI*.5;body.pitch=0
	body.command.yaw=body.yaw
	body.command.pitch=0.0
	body.command.third_person=false
	await physics_frame
	var hit:Dictionary=arena.c4_surface(body)
	if hit.is_empty():
		for yaw in [0.0,PI*.5,PI,-PI*.5]:
			body.yaw=yaw
			body.command.yaw=yaw
			hit=arena.c4_surface(body)
			if not hit.is_empty():break
	record("c4_surface_found",not hit.is_empty())
	if not hit.is_empty():
		arena.place_c4(1)
		record("c4_inventory_consumed",body.c4_count==1 and arena.charges.size()==1)
		var charge=arena.charges.values()[0]
		await create_timer(.8).timeout
		record("c4_armed_attached",charge.armed and charge.get_parent()!=arena)
		arena.detonate_c4(1)
		record("c4_detonated_once",arena.charges.is_empty())
	var arm=arena.armory
	record("armory_created",arm!=null and not arm.is_unlocked)
	body.phase="ground"
	body.position=arm.card_position
	arena.interact(1)
	record("keycard_pickup",arm.keycard_owner==1)
	body.position=arm.door.global_position
	var before:int=arena.loot.size()
	arena.interact(1)
	record("armory_unlock_reward",arm.is_unlocked and arena.loot.size()>=before+6)
	before=arena.loot.size()
	arena.interact(1)
	record("armory_no_duplicate",arena.loot.size()==before)
	arena.clear_round()
	record("armory_reset",not arm.is_unlocked and arm.keycard_owner==0)
	var ok:=true
	for value in checks.values():ok=ok and value
	var f:=FileAccess.open("res://review/new-content-checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":ok,"checks":checks},"  "));f.close()
	print("NEW_CONTENT_REVIEW ",JSON.stringify({"passed":ok,"checks":checks}))
	if DisplayServer.get_name()!="headless":
		arena.practice()
		arena.fighters[1].position=arena.floor_at(arena.NORTH_ENTRY+Vector3(0,0,8))
		arena.fighters[1].phase="ground"
		arena.fighters[1].weapon_slots.assign(["carbine","ak47","pistol","shotgun","knife"])
		arena.equip_weapon(arena.fighters[1],"ak47")
		arena.look_yaw=PI
		await create_timer(.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://review/new-content-preview.png")
	root.remove_child(arena);arena.free()
	await process_frame
	quit(0 if ok else 1)
