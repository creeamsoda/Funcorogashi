extends SceneTree

var meshes: Array = []
var nodes: Array = []
var totals: Dictionary = {"vertices": 0, "triangles": 0, "surfaces": 0}
var wing_checks: Dictionary = {}
var ground_checks: Dictionary = {"minimum_global_y": INF, "mesh_minimum_global_y": {}}
const SOURCE_RELATIVE := "resources/models/beetle/beetle.glb"
const EXPECTED_PIVOTS := {
	"Arm_L": Vector3(-0.62, 0.43, -0.82),
	"Arm_R": Vector3(0.62, 0.43, -0.82),
	"Leg_Middle_L": Vector3(-0.70, 0.37, -0.15),
	"Leg_Middle_R": Vector3(0.70, 0.37, -0.15),
	"Leg_Rear_L": Vector3(-0.67, 0.35, 0.40),
	"Leg_Rear_R": Vector3(0.67, 0.35, 0.40),
}

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func connected_components(vertex_count: int, indices: PackedInt32Array) -> int:
	var adjacency: Array = []
	for unused in range(vertex_count):
		adjacency.append([])
	for tri in range(0, indices.size(), 3):
		for corner in range(3):
			var a: int = indices[tri + corner]
			var b: int = indices[tri + (corner + 1) % 3]
			adjacency[a].append(b)
			adjacency[b].append(a)
	var seen: Dictionary = {}
	var components: int = 0
	for start in range(vertex_count):
		if seen.has(start):
			continue
		components += 1
		var pending: Array = [start]
		while not pending.is_empty():
			var current: int = pending.pop_back()
			if seen.has(current):
				continue
			seen[current] = true
			for neighbor in adjacency[current]:
				if not seen.has(neighbor):
					pending.append(neighbor)
	return components

func inspect_node(node: Node) -> void:
	nodes.append({"path": str(node.get_path()), "class": node.get_class()})
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		var mesh_minimum_global_y: float = INF
		var record: Dictionary = {"name": str(node.name), "path": str(node.get_path()), "position": vec(node.position), "global_position": vec(node.global_position), "aabb_position": vec(mesh.get_aabb().position), "aabb_size": vec(mesh.get_aabb().size), "surfaces": []}
		for i in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				mesh_minimum_global_y = minf(mesh_minimum_global_y, node.to_global(vertex).y)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var mat: Material = mesh.surface_get_material(i)
			var uv_min := Vector2(INF, INF)
			var uv_max := Vector2(-INF, -INF)
			for uv in uvs:
				uv_min = uv_min.min(uv)
				uv_max = uv_max.max(uv)
			var triangle_count: int = int(indices.size() / 3) if indices.size() > 0 else int(vertices.size() / 3)
			var surface: Dictionary = {"vertices": vertices.size(), "triangles": triangle_count, "uv_count": uvs.size(), "uv_min": [uv_min.x, uv_min.y], "uv_max": [uv_max.x, uv_max.y], "material_name": mat.resource_name if mat != null else "", "material_class": mat.get_class() if mat != null else ""}
			if mat is StandardMaterial3D:
				surface["albedo_texture"] = mat.albedo_texture.resource_path if mat.albedo_texture != null else ""
				surface["albedo_color"] = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a]
				if node.name == "WingShell" and i == 0:
					wing_checks = {"image_surface_material": mat.resource_name, "texture_present": mat.albedo_texture != null, "uv_count_matches_vertices": uvs.size() == vertices.size(), "uv_within_0_1": uv_min.x >= 0.0 and uv_min.y >= 0.0 and uv_max.x <= 1.0 and uv_max.y <= 1.0, "surface_connected_components": connected_components(vertices.size(), indices)}
					if mat.albedo_texture != null:
						wing_checks["texture_size"] = [mat.albedo_texture.get_width(), mat.albedo_texture.get_height()]
			record.surfaces.append(surface)
			totals.vertices += vertices.size()
			totals.triangles += triangle_count
			totals.surfaces += 1
		meshes.append(record)
		ground_checks.mesh_minimum_global_y[str(node.name)] = mesh_minimum_global_y
		ground_checks.minimum_global_y = minf(ground_checks.minimum_global_y, mesh_minimum_global_y)
	for child in node.get_children():
		inspect_node(child)

func _initialize() -> void:
	call_deferred("run_validation")

func inspect_limb(instance: Node, limb_name: String) -> Dictionary:
	var limb := instance.find_child(limb_name, true, false) as MeshInstance3D
	if limb == null or limb.mesh == null or limb.mesh.get_surface_count() == 0:
		return {"name": limb_name, "found": false}
	var original: Transform3D = limb.transform
	var pivot_before: Vector3 = limb.global_position
	var arrays: Array = limb.mesh.surface_get_arrays(0)
	var sample_local := Vector3.ZERO
	for vertex in arrays[Mesh.ARRAY_VERTEX]:
		if vertex.length_squared() > sample_local.length_squared():
			sample_local = vertex
	var sample_before: Vector3 = limb.to_global(sample_local)
	limb.rotate_y(deg_to_rad(25.0))
	var pivot_after: Vector3 = limb.global_position
	var sample_after: Vector3 = limb.to_global(sample_local)
	limb.transform = original
	var expected: Vector3 = EXPECTED_PIVOTS[limb_name]
	return {"name": limb_name, "found": true, "pivot": vec(pivot_before), "expected_pivot": vec(expected), "pivot_matches_authored_attachment": pivot_before.distance_to(expected) < 0.00001, "neutral_rotation": original.basis.is_equal_approx(Basis.IDENTITY), "distal_vertex": vec(sample_before), "distal_vertex_selection": "mesh vertex farthest from its local pivot", "distal_vertex_below_pivot": sample_before.y < pivot_before.y, "rotation_degrees_tested": 25, "pivot_shift": pivot_after.distance_to(pivot_before), "sample_movement": sample_after.distance_to(sample_before), "rotates_about_fixed_pivot": pivot_after.is_equal_approx(pivot_before) and not sample_after.is_equal_approx(sample_before)}

func finish_validation(result: Dictionary, errors: Array[String]) -> void:
	result["passed"] = errors.is_empty()
	result["errors"] = errors
	var result_file := FileAccess.open("res://validation.json", FileAccess.WRITE)
	if result_file == null:
		push_error("Could not write validation.json: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	result_file.store_string(JSON.stringify(result, "\t"))
	result_file.close()
	var summary: Dictionary = result.duplicate()
	summary.erase("hierarchy")
	summary.erase("meshes")
	print(JSON.stringify(summary, "\t"))
	quit(0 if errors.is_empty() else 1)

func run_validation() -> void:
	# Resolve the repository asset directly; this mini-project requires no copied
	# beetle.glb and no pre-existing .godot import cache.
	var source_path: String = ProjectSettings.globalize_path("res://../../../" + SOURCE_RELATIVE).simplify_path()
	var errors: Array[String] = []
	var result: Dictionary = {"engine": Engine.get_version_info().string, "source": SOURCE_RELATIVE, "source_sha256": FileAccess.get_sha256(source_path), "import_method": "GLTFDocument.append_from_file + generate_scene", "import_ok": false}
	if not FileAccess.file_exists(source_path):
		errors.append("Source GLB does not exist: " + source_path)
		finish_validation(result, errors)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var import_error: Error = document.append_from_file(source_path, state)
	if import_error != OK:
		errors.append("GLB import failed: " + error_string(import_error))
		finish_validation(result, errors)
		return
	var instance: Node = document.generate_scene(state)
	if instance == null:
		errors.append("GLB scene generation failed")
		finish_validation(result, errors)
		return
	root.add_child(instance)
	inspect_node(instance)
	var arm_checks: Array = []
	var limb_checks: Array = []
	for limb_name: String in EXPECTED_PIVOTS:
		var check: Dictionary = inspect_limb(instance, limb_name)
		limb_checks.append(check)
		if limb_name.begins_with("Arm_"):
			arm_checks.append(check)
		for key in ["found", "pivot_matches_authored_attachment", "neutral_rotation", "rotates_about_fixed_pivot", "distal_vertex_below_pivot"]:
			if not check.get(key, false):
				errors.append(limb_name + ": " + key + " failed")
	ground_checks["tolerance"] = 0.00001
	ground_checks["all_meshes_above_ground_y_0"] = ground_checks.minimum_global_y >= -ground_checks.tolerance
	result.merge({"import_ok": true, "mesh_count": meshes.size(), "totals": totals, "within_1000_vertex_budget": totals.vertices <= 1000, "arms": arm_checks, "limbs": limb_checks, "wing": wing_checks, "ground": ground_checks, "hierarchy": nodes, "meshes": meshes}, true)
	if meshes.size() != 10:
		errors.append("Expected 10 mesh objects")
	if totals.vertices > 1000:
		errors.append("Export exceeds 1,000 vertices")
	for key in ["uv_count_matches_vertices", "uv_within_0_1", "texture_present"]:
		if not wing_checks.get(key, false):
			errors.append("WingShell: " + key + " failed")
	if wing_checks.get("surface_connected_components", 0) != 1:
		errors.append("WingShell image surface must have one connected component")
	if wing_checks.get("image_surface_material", "") != "Wing_Image":
		errors.append("WingShell surface 0 must use Wing_Image")
	if wing_checks.get("texture_size", []) != [1024, 1024]:
		errors.append("WingShell texture must be 1024 x 1024")
	if not ground_checks.all_meshes_above_ground_y_0:
		errors.append("A mesh extends below ground Y=0")
	finish_validation(result, errors)
