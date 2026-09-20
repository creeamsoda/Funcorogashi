extends Node3D
## GLB差し替えの回帰検証。実頂点と頭/腹の位置から接地・向き・大きさを確認する。

const EPSILON := 0.0001
const EXPECTED_MODEL_LENGTH := 0.9 * 1.2


func _ready() -> void:
	var player := (load("res://scenes/Player.tscn") as PackedScene).instantiate() as Player
	player.input_device = 9999
	player.initial_size = 1.0
	add_child(player)
	player.set_physics_process(false)
	await get_tree().process_frame
	var beetle := player.get_node_or_null("Beetle") as Node3D
	var model := beetle.get_node_or_null("Model") as Node3D if beetle != null else null
	var meshes: Array[MeshInstance3D] = []
	if beetle != null:
		for node in beetle.find_children("*", "MeshInstance3D", true, false):
			meshes.append(node as MeshInstance3D)
	var glb_ok := model != null and meshes.size() == 10 and not beetle is MeshInstance3D
	for mesh_instance in meshes:
		glb_ok = glb_ok and mesh_instance.mesh != null and not mesh_instance.mesh is BoxMesh
	if not glb_ok:
		push_error("Expected a Beetle/Model GLB with 10 mesh parts, got %d." % meshes.size())
		get_tree().quit(1)
		return

	var head := beetle.find_child("Head", true, false) as MeshInstance3D
	var abdomen := beetle.find_child("Abdomen", true, false) as MeshInstance3D
	if head == null or abdomen == null:
		push_error("Imported beetle is missing Head or Abdomen.")
		get_tree().quit(1)
		return
	var original_scale: Vector3 = model.scale
	var original_rotation: Vector3 = model.rotation
	# 傾きを変えても、元の12度姿勢で合わせたモデルサイズを維持する。
	model.rotation.x = deg_to_rad(-12.0)
	var reference_dimensions := _bounds_in_space(meshes, beetle.global_transform.affine_inverse()).size
	model.rotation = original_rotation
	var original_dimensions := _bounds_in_space(meshes, beetle.global_transform.affine_inverse()).size
	var size_ok := absf(reference_dimensions.z - EXPECTED_MODEL_LENGTH) < EPSILON \
		and is_equal_approx(Player.BEETLE_VISUAL_SIZE_RATIO, 1.2) \
		and is_equal_approx(original_scale.x, original_scale.y) \
		and is_equal_approx(original_scale.y, original_scale.z)
	var facing_ok := true
	var pitch_ok := absf(rad_to_deg(model.rotation.x) + 45.0) < EPSILON
	var grounded_ok := true
	var clearance_ok := true
	var unchanged_ok := true
	var directions: Array[Vector3] = [
		Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT,
		Vector3(1, 0, 1).normalized(), Vector3(3, 0, -2).normalized(),
	]
	var states: Array[Player.State] = [
		Player.State.ROLLING, Player.State.DASH_WINDUP,
		Player.State.DASHING, Player.State.STUNNED,
	]
	var checked := 0
	for dung_size in [1.0, 6.0, 32.0]:
		player.size = dung_size
		player._apply_size_visual()
		for direction in directions:
			for state in states:
				player.facing = direction
				player.state = state
				player._dash_dir = direction
				player._windup_t = 1.0
				player._stun_t = 1.0
				player._physics_process(0.0)
				var head_center: Vector3 = head.global_transform * head.get_aabb().get_center()
				var abdomen_center: Vector3 = abdomen.global_transform * abdomen.get_aabb().get_center()
				var head_to_abdomen := abdomen_center - head_center
				head_to_abdomen.y = 0.0
				var to_ball := player.global_position - beetle.global_position
				to_ball.y = 0.0
				facing_ok = facing_ok and head_to_abdomen.normalized().dot(to_ball.normalized()) > 0.9999 \
					and head_to_abdomen.normalized().dot(direction) > 0.9999
				pitch_ok = pitch_ok and head_center.y < abdomen_center.y - 0.01
				var world_bounds := _bounds_in_space(meshes, Transform3D.IDENTITY)
				grounded_ok = grounded_ok and world_bounds.position.y >= -EPSILON \
					and world_bounds.position.y < 0.01
				var local_bounds := _bounds_in_space(meshes, beetle.global_transform.affine_inverse())
				unchanged_ok = unchanged_ok and local_bounds.size.is_equal_approx(original_dimensions) \
					and model.scale.is_equal_approx(original_scale)
				var front_projection := -INF
				var surface_clearance := INF
				for point in _world_vertices(meshes):
					front_projection = maxf(front_projection, (point - player.global_position).dot(direction))
					surface_clearance = minf(surface_clearance, point.distance_to(player.global_position) - player.body_radius())
				var gap := -front_projection - player.body_radius()
				# 外接矩形へは近づけつつ、実際の球面へのめり込みを確認する。
				clearance_ok = clearance_ok and gap < 0.0 and gap > -0.2 and surface_clearance >= -EPSILON
				checked += 1

	var ok := glb_ok and size_ok and facing_ok and pitch_ok and grounded_ok and clearance_ok and unchanged_ok
	print("[beetle_visual_check] result=", ("PASS" if ok else "FAIL"),
		" meshes=", meshes.size(), " cases=", checked, " length=", original_dimensions.z,
		" size=", size_ok, " abdomen_to_ball=", facing_ok, " head_down=", pitch_ok,
		" grounded=", grounded_ok, " clearance=", clearance_ok, " size_invariant=", unchanged_ok)
	player.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)


func _world_vertices(meshes: Array[MeshInstance3D]) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh_instance in meshes:
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				points.append(mesh_instance.global_transform * vertex)
	return points


func _bounds_in_space(meshes: Array[MeshInstance3D], to_space: Transform3D) -> AABB:
	var points := _world_vertices(meshes)
	var bounds := AABB(to_space * points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(to_space * point)
	return bounds
