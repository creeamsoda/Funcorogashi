class_name ResultContestant
extends Control
## 結果発表用。フンコロガシの背中と、その奥のフン球を正投影カメラで表示する。

const DISPLAY_SIZE := Vector2(220.0, 310.0)
const PIXELS_PER_UNIT := 42.0
const GROUND_Y := 239.0

var player_id := 0
var final_size := 1.0
var _viewport: SubViewport


func setup(p_player_id: int, p_final_size: float) -> void:
	player_id = p_player_id
	final_size = p_final_size
	custom_minimum_size = DISPLAY_SIZE
	size = DISPLAY_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_node_ready():
		_build_preview()


func _ready() -> void:
	_build_preview()


func _build_preview() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_viewport = SubViewport.new()
	_viewport.name = "ModelViewport"
	_viewport.size = Vector2i(DISPLAY_SIZE * 2.0)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var presentation := Node3D.new()
	presentation.name = "Presentation"
	_viewport.add_child(presentation)

	# 従来の結果表示と同じ半径の範囲に収め、全員を同じカメラ倍率で比較する。
	var radius := clampf(
		Config.balance.radius_for_size(final_size, Config.balance.size_to_scale) * PIXELS_PER_UNIT,
		28.0,
		76.0
	) / PIXELS_PER_UNIT
	var ball := MeshInstance3D.new()
	ball.name = "DungBall"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	ball.mesh = sphere
	# 本編と同じく、フン球もフンコロガシの全身もプレイヤー色で塗る。
	var player_color := Player.color_for(player_id)
	var material := ToonMaterial.create(player_color)
	ball.material_override = material
	ball.position.y = radius
	presentation.add_child(ball)

	var beetle := BeetleModel.create(presentation, player_color)
	beetle.root.position.z = -beetle.distance_from_ball(radius)

	var combined_bounds := BeetleModel.mesh_bounds(beetle.meshes, presentation).merge(ball.transform * ball.get_aabb())
	var camera := Camera3D.new()
	camera.name = "BackCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = DISPLAY_SIZE.x / PIXELS_PER_UNIT
	# 横からの画角を90度回し、頭を下げたフンコロガシの背中を手前、フン球を奥にする。
	# カメラの高さと倍率は維持し、全員の足元を揃える。
	camera.position = Vector3(combined_bounds.get_center().x, (GROUND_Y - DISPLAY_SIZE.y * 0.5) / PIXELS_PER_UNIT, combined_bounds.get_center().z - 10.0)
	camera.rotation.y = PI
	camera.near = 0.1
	camera.far = 30.0
	camera.current = true
	presentation.add_child(camera)
	_build_lighting(presentation)

	var image := TextureRect.new()
	image.name = "ModelImage"
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = _viewport.get_texture()
	add_child(image)
	# モデルの姿勢は固定。落下とジャンプは親Controlの既存Tweenで動かす。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_lighting(presentation: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.80, 0.85, 1.0)
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	presentation.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	key_light.light_color = Color(1.0, 0.93, 0.83)
	key_light.light_energy = 1.4
	presentation.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -135.0, 0.0)
	fill_light.light_color = Color(0.74, 0.83, 1.0)
	fill_light.light_energy = 0.55
	presentation.add_child(fill_light)
