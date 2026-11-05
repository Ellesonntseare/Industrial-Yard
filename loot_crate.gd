extends Node3D

var opened := false
var hinge: Node3D
var closed_rotation := Vector3.ZERO
var tween: Tween

func _ready() -> void:
	var packed := load("res://assets/provided/openable_crate__loot_box___chest.glb") as PackedScene
	if not packed: return
	var model := packed.instantiate()
	model.scale = Vector3.ONE * 1.6
	add_child(model)
	hinge = model.find_child("lid", true, false)
	if hinge: closed_rotation = hinge.rotation
	var body := StaticBody3D.new()
	add_child(body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.58, 0.8)
	collision.shape = box
	collision.position = Vector3(0, 0.28, 0.38)
	body.add_child(collision)
	var label := Label3D.new()
	label.text = "SUPPLY CACHE · E"
	label.position = Vector3(0, 1, 0.35)
	label.font_size = 24
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 24
	add_child(label)

func set_open(value: bool) -> void:
	if value == opened: return
	opened = value
	if not hinge: return
	if tween: tween.kill()
	tween = create_tween()
	tween.tween_property(hinge, "rotation:x", closed_rotation.x + (-1.5 if value else 0.0), 0.5).set_trans(Tween.TRANS_SINE)
