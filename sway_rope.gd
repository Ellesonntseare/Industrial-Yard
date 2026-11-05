extends Node3D

var segments: Array[MeshInstance3D] = []

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("716954")
	material.roughness = 0.95
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 1
	mesh.radial_segments = 10
	for i in range(14):
		var segment := MeshInstance3D.new()
		segment.mesh = mesh
		segment.material_override = material
		add_child(segment)
		segments.append(segment)

func set_endpoints(top: Vector3, bottom: Vector3, time: float) -> void:
	var previous := top
	for i in range(segments.size()):
		var t := float(i + 1) / segments.size()
		var bend := sin(t * PI)
		var next := top.lerp(bottom, t) + Vector3(sin(time * 1.3 + t * 1.2) * 0.23, 0, cos(time * 1.1 + t) * 0.18) * bend
		var difference := next - previous
		var segment := segments[i]
		segment.global_position = (next + previous) * 0.5
		segment.global_basis = Basis(Quaternion(Vector3.UP, difference.normalized())).scaled(Vector3(1, maxf(0.001, difference.length() + 0.004), 1))
		previous = next
