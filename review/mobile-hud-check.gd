extends SceneTree

class TestRadar extends RefCounted:
	var expanded := false

class TestBody extends Node3D:
	var phase := "ground"
	var hp := 100.0
	var armor := 75.0
	var magazine := 30
	var ammo := 90
	var weapon := true
	var weapon_id := "carbine"
	var c4_count := 2
	var reload_left := 0.0
	var medkits := 2
	var grenades := 1
	var backpack := true
	var score := 0
	var respawn_left := 4.0

class TestArena extends Node3D:
	var active := true
	var menu := Control.new()
	var fighters := {}
	var local_id := 1
	var armory: Node = null
	var c4_mode := false
	var radar := TestRadar.new()
	const Weapons = preload("res://weapons_catalog.gd")
	var end_text := ""
	var crates := []
	var loot := {}
	var doors := []
	var clock := 0.0
	var third_person := true
	var look_yaw := 0.0
	var look_pitch := 0.0
	var actions := []
	const KINDS := ["RIFLE","AMMO","MEDKIT","ARMOUR","GRENADE","BACKPACK"]
	func request_action(action): actions.append(action)
	func message(_value): pass

var ui: Control
var arena: TestArena
var checks := {}

func _initialize() -> void: call_deferred("run")

func press(key: String,index: int,down: bool=true) -> void:
	var event := InputEventScreenTouch.new()
	event.index=index
	event.position=ui.center(key)*ui.frame_scale
	event.pressed=down
	ui._input(event)

func run() -> void:
	arena=TestArena.new()
	root.add_child(arena)
	arena.add_child(arena.menu)
	arena.menu.hide()
	var body:=TestBody.new()
	arena.add_child(body)
	arena.fighters[1]=body
	ui=load("res://mobile_hud.gd").new()
	ui.setup(arena)
	root.add_child(ui)
	await process_frame
	ui.touch_layout=true
	press("run",0)
	checks.run_toggles=ui.sprinting
	press("move",1)
	var drag:=InputEventScreenDrag.new()
	drag.index=1;drag.position=(ui.center("move")+Vector2(0,-60))*ui.frame_scale
	ui._input(drag)
	checks.joystick_moves_forward=ui.movement.y<-.5
	press("fire",2)
	checks.fire_with_joystick=ui.firing and ui.movement.length()>.5
	press("fire",2,false)
	checks.fire_releases=not ui.firing
	press("jump",3)
	press("reload",4)
	press("heal",5)
	press("grenade",6)
	checks.action_dispatch=arena.actions==["jump","reload","heal","grenade"]
	press("camera",7)
	checks.camera_toggle=not arena.third_person
	press("aim",8)
	press("crouch",9)
	checks.aim_crouch_toggles=ui.aiming and ui.crouching
	var command={"move":Vector2.ZERO,"run":false,"fire":true,"aim":false,"crouch":false}
	var result: Dictionary=ui.merge_controls(command)
	checks.touch_does_not_emulate_fire=not result.fire
	checks.merged_controls=result.run and result.aim and result.crouch and result.move.y<-.5
	ui.set_settings(true)
	checks.settings_clear_held_input=not ui.firing and ui.movement==Vector2.ZERO and not ui.sprinting
	ui.settings_open=false
	body.phase="dead"
	checks.dead_blocks_input=not ui.playable()
	var passed:=true
	for value in checks.values(): passed=passed and value
	print("MOBILE_HUD_CHECK ",JSON.stringify({"passed":passed,"checks":checks}))
	quit(0 if passed else 1)
