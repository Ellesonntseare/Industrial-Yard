extends StaticBody3D

const SIZE := Vector3(3.8, 2.45, .54)
const LIFETIME := 22.0
var expires_at := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	collision.shape = shape
	collision.position.y = SIZE.y * .5
	add_child(collision)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("61c4e2")
	material.metallic = .18
	material.roughness = .32
	material.emission_enabled = true
	material.emission = Color("20576b")
	var core := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = SIZE
	core.mesh = slab
	core.position = collision.position
	core.material_override = material
	add_child(core)
	var frost := material.duplicate() as StandardMaterial3D
	frost.albedo_color = Color("ace5f0")
	for i in range(7):
		var shard := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(.65, .64 + .3 * sin(i * 2.4), .38)
		shard.mesh = mesh
		shard.material_override = frost
		shard.position = Vector3((i - 3) * .51, SIZE.y - .07, 0)
		add_child(shard)
