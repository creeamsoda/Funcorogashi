extends Node3D
## 結果画面の3D表示と演出をheadlessで検証。描画画素の見た目はResultsTestで確認する。

const TIMEOUT_SECONDS := 10.0
const EPSILON := 0.001

var _results: Results
var _elapsed := 0.0
var _finished_at := -1.0
var _observed_ranks: Array[int] = []
var _drop_from_above := true
var _winner_min_y := INF
var _winner_max_y := -INF
var _other_ranks_still := true
var _player_count_before := 0
var _models_ok := false
var _done := false


func _ready() -> void:
	_player_count_before = get_tree().get_nodes_in_group("player").size()
	_results = (load("res://scenes/ui/Results.tscn") as PackedScene).instantiate() as Results
	add_child(_results)
	_results.animation_speed_scale = 0.12
	_results.presentation_finished.connect(func() -> void: _finished_at = _elapsed)
	_results.show_results([
		{"player_id": 0, "size": 2.0, "dash_hits_received": 5},
		{"player_id": 1, "size": 0.01, "dash_hits_received": 9},
		{"player_id": 2, "size": 1000.0, "dash_hits_received": 2},
		{"player_id": 3, "size": 5.0, "dash_hits_received": 4},
	])
	await get_tree().process_frame
	_models_ok = _check_models()
	if not _models_ok:
		_finish(false)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		push_error("Result presentation stalled or failed before completing the visual check.")
		_finish(false)
		return
	if _results == null:
		return
	for rank in _results._contestants.size():
		var contestant := _results._contestants[rank]
		if contestant.modulate.a > 0.5 and not _observed_ranks.has(rank):
			_observed_ranks.append(rank)
			_drop_from_above = _drop_from_above and contestant.position.y < _results._contestant_targets[rank].y
	if _finished_at < 0.0:
		return
	var winner := _results._contestants[0]
	_winner_min_y = minf(_winner_min_y, winner.position.y)
	_winner_max_y = maxf(_winner_max_y, winner.position.y)
	for rank in range(1, _results._contestants.size()):
		_other_ranks_still = _other_ranks_still \
			and _results._contestants[rank].position.is_equal_approx(_results._contestant_targets[rank])
	if _elapsed - _finished_at < 0.3:
		return
	var reverse_order := _observed_ranks == [3, 2, 1, 0]
	var winner_bounces := _winner_max_y - _winner_min_y > 1.0
	var retry := _results._retry_button
	var retry_ready := not retry.disabled and retry.modulate.a > 0.99 and retry.has_focus()
	var groups_unchanged := get_tree().get_nodes_in_group("player").size() == _player_count_before
	print("  [results_sequence] reverse_drop=", reverse_order, " from_above=", _drop_from_above,
		" winner_bounces=", winner_bounces, " others_still=", _other_ranks_still,
		" retry_ready=", retry_ready, " groups_unchanged=", groups_unchanged)
	_finish(_models_ok and reverse_order and _drop_from_above and winner_bounces and _other_ranks_still \
		and retry_ready and groups_unchanged)


func _check_models() -> bool:
	if _results._contestants.size() != 4:
		push_error("Expected four result contestants.")
		return false
	var viewports: Array[SubViewport] = []
	var wing_materials: Array[StandardMaterial3D] = []
	var radii: Array[float] = []
	var ok := true
	for contestant in _results._contestants:
		var viewport := contestant.get_node_or_null("ModelViewport") as SubViewport
		var image := contestant.get_node_or_null("ModelImage") as TextureRect
		if viewport == null or image == null:
			push_error("Result contestant has no 3D viewport or viewport image.")
			return false
		var beetle := viewport.find_child("Beetle", true, false) as Node3D
		var ball := viewport.find_child("DungBall", true, false) as MeshInstance3D
		var camera := viewport.find_child("BackCamera", true, false) as Camera3D
		if beetle == null or ball == null or camera == null or not ball.mesh is SphereMesh:
			push_error("Result viewport is missing its beetle, sphere or back camera.")
			return false
		var viewport_ok := viewport.own_world_3d and viewport.transparent_bg and viewport.gui_disable_input \
			and viewport.find_world_3d() != get_viewport().find_world_3d() \
			and image.texture == viewport.get_texture() and viewport.size.x > 0 and viewport.size.y > 0
		for other in viewports:
			viewport_ok = viewport_ok and viewport.find_world_3d() != other.find_world_3d()
		viewports.append(viewport)
		# 横から90度回した平行投影。水平な視線が-Z側から+Z側へ向く。
		var camera_forward := -camera.global_basis.z.normalized()
		var camera_ok := camera.projection == Camera3D.PROJECTION_ORTHOGONAL and camera.current \
			and absf(camera_forward.x) < EPSILON and absf(camera_forward.y) < EPSILON \
			and camera_forward.z > 0.9999 and camera.global_basis.y.normalized().dot(Vector3.UP) > 0.9999
		var meshes: Array[MeshInstance3D] = []
		for node in beetle.find_children("*", "MeshInstance3D", true, false):
			meshes.append(node as MeshInstance3D)
		var model_ok := meshes.size() == 10
		for part in meshes:
			model_ok = model_ok and part.mesh != null and not part.mesh is PrimitiveMesh
		var shell := beetle.find_child("WingShell", true, false) as MeshInstance3D
		var head := beetle.find_child("Head", true, false) as MeshInstance3D
		var abdomen := beetle.find_child("Abdomen", true, false) as MeshInstance3D
		if shell == null or head == null or abdomen == null:
			push_error("Result beetle does not contain the imported GLB body parts.")
			return false
		var material := shell.get_active_material(0) as StandardMaterial3D
		if material == null:
			push_error("Result beetle has no wing material.")
			return false
		var expected_color: Color = Player.PLAYER_COLORS[contestant.player_id]
		# 全身(全部位・全サーフェス)がテクスチャなしのプレイヤー色一色。
		var colors_ok := true
		for part in meshes:
			for surface in part.mesh.get_surface_count():
				var part_mat := part.get_active_material(surface) as StandardMaterial3D
				colors_ok = colors_ok and part_mat != null and part_mat.albedo_texture == null \
					and part_mat.albedo_color.is_equal_approx(expected_color)
		# フン球も本編と同じくプレイヤー色。
		var ball_mat := ball.material_override as StandardMaterial3D
		colors_ok = colors_ok and ball_mat != null and ball_mat.albedo_color.is_equal_approx(expected_color)
		for other in wing_materials:
			colors_ok = colors_ok and material != other
		wing_materials.append(material)
		var head_to_abdomen := abdomen.global_transform * abdomen.get_aabb().get_center() \
			- head.global_transform * head.get_aabb().get_center()
		head_to_abdomen.y = 0.0
		# 頭を下げたモデルの背中がこちらを向き、フン球より手前に見える。
		var model := beetle.get_node("Model") as Node3D
		var back_ok := head_to_abdomen.normalized().dot(camera_forward) > 0.9999 \
			and model.global_basis.y.normalized().dot(-camera_forward) > 0.7 \
			and (ball.global_position - beetle.global_position).dot(camera_forward) > 0.0
		meshes.append(ball)
		var fits := _geometry_fits(camera, viewport, meshes)
		var render_only := viewport.find_children("*", "CollisionObject3D", true, false).is_empty() \
			and viewport.find_children("*", "AudioStreamPlayer3D", true, false).is_empty() \
			and viewport.find_children("*", "AudioStreamPlayer", true, false).is_empty()
		radii.append((ball.mesh as SphereMesh).radius)
		var contestant_ok := viewport_ok and camera_ok and model_ok and colors_ok and back_ok and fits and render_only
		print("  [results_model] player=", contestant.player_id, " viewport=", viewport_ok,
			" back_camera=", camera_ok, " imported_model=", model_ok, " color=", colors_ok,
			" back_visible=", back_ok, " fits=", fits, " render_only=", render_only)
		ok = ok and contestant_ok
	# 並びは大きさ降順。極端な成績も表示領域に収まり、大小が逆転しない。
	var size_order := radii[0] > radii[3] and radii[3] > 0.0
	for rank in range(1, radii.size()):
		size_order = size_order and radii[rank - 1] >= radii[rank]
	print("  [results_sizes] radii=", radii, " descending=", size_order)
	return ok and size_order


func _geometry_fits(camera: Camera3D, viewport: SubViewport, meshes: Array[MeshInstance3D]) -> bool:
	var half_size := Vector2.ONE * camera.size * 0.5
	var aspect := float(viewport.size.x) / float(viewport.size.y)
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		half_size.x *= aspect
	else:
		half_size.y /= aspect
	for part in meshes:
		if part.mesh == null:
			return false
		var to_camera := camera.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := to_camera * vertex
				if not point.is_finite() or absf(point.x) > half_size.x + EPSILON \
					or absf(point.y) > half_size.y + EPSILON \
					or point.z > -camera.near or point.z < -camera.far:
					return false
	return true


func _finish(ok: bool) -> void:
	_done = true
	print("[results_visual_check] result=", ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
