extends Node3D

const HARNESS_HEIGHT := 1.58
var shell: MeshInstance3D
var cords: Array[Dictionary] = []

func _ready() -> void:
	var fabric := StandardMaterial3D.new()
	fabric.vertex_color_use_as_albedo = true
	fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
	fabric.roughness = 0.85
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rib in range(16):
		var color := Color("c49343") if rib in [0, 1, 14, 15] else Color("425640") if rib % 2 == 0 else Color("54674b")
		for row in range(6):
			for point in [Vector2i(rib,row), Vector2i(rib+1,row), Vector2i(rib,row+1), Vector2i(rib+1,row), Vector2i(rib+1,row+1), Vector2i(rib,row+1)]:
				surface.set_color(color)
				surface.add_vertex(fabric_point(point.x, point.y) - Vector3.UP * HARNESS_HEIGHT)
	surface.generate_normals()
	shell = MeshInstance3D.new()
	shell.mesh = surface.commit()
	shell.material_override = fabric
	add_child(shell)
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color("c6c4ad")
	for side in [-1, 1]:
		for rib in ([0, 2, 4] if side < 0 else [12, 14, 16]):
			for row in [0, 6]:
				var line := MeshInstance3D.new()
				var mesh := CylinderMesh.new()
				mesh.top_radius = .008
				mesh.bottom_radius = .008
				mesh.height = 1.0
				mesh.radial_segments = 4
				mesh.rings = 0
				line.mesh = mesh
				line.material_override = cord
				add_child(line)
				cords.append({"line": line, "left": side < 0, "anchor": fabric_point(rib, row) - Vector3.UP * HARNESS_HEIGHT})
	update_lines(Vector3(-.3, 0, 0), Vector3(.3, 0, 0), 1.0)

func update_lines(left_hand: Vector3, right_hand: Vector3, opening: float) -> void:
	shell.scale = Vector3.ONE * opening
	for cord in cords:
		var grip: Vector3 = left_hand if cord.left else right_hand
		var anchor: Vector3 = cord.anchor * opening
		var span := anchor - grip
		var line: MeshInstance3D = cord.line
		line.position = (grip + anchor) * .5
		line.basis = Basis(Quaternion(Vector3.UP, span.normalized())).scaled_local(Vector3(1, span.length(), 1))

func fabric_point(rib: int, row: int) -> Vector3:
	var across := rib / 8.0 - 1.0
	var chord := row / 6.0
	return Vector3(across * 2.65, 4.45 - across * across * .85 + sin(chord * PI) * .30, (chord - .5) * 1.9)
