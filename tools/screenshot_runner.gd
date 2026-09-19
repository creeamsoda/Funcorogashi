extends Node
## 見た目テスト用ハーネス(操作を伴わないビジュアル確認をCLIで自動化する)。
##
## 使い方:
##   godot --path . res://tools/ScreenshotRunner.tscn -- \
##       --scene=res://scenes/Stage.tscn --out=C:/path/shot.png --frames=8
##
## --scene 省略時は内蔵デモ(床cube + フンsphere)を描画してスタイルを確認する。
## --out   保存先PNG(絶対パス推奨。省略時 res://_shot.png)。
## --frames 描画待機フレーム数(既定 8)。

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]

	var out_path: String = args.get("out", "res://_shot.png")
	var frames: int = int(args.get("frames", "8"))
	var scene_path: String = args.get("scene", "")

	if scene_path != "" and ResourceLoader.exists(scene_path):
		add_child((load(scene_path) as PackedScene).instantiate())
	else:
		_build_demo()

	for _i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("screenshot: viewport image is null")
		get_tree().quit(1)
		return
	var err := img.save_png(out_path)
	print("screenshot saved: ", out_path, " err=", err)
	get_tree().quit(0 if err == OK else 2)


func _build_demo() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 16, 12)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation_degrees = Vector3(-55, -35, 0)

	var floor_mi := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(20, 0.5, 14)
	floor_mi.mesh = floor_mesh
	floor_mi.position = Vector3(0, -0.25, 0)
	add_child(floor_mi)

	var dung_mi := MeshInstance3D.new()
	var dung_mesh := SphereMesh.new()
	dung_mesh.radius = 1.0
	dung_mesh.height = 2.0
	dung_mi.mesh = dung_mesh
	dung_mi.position = Vector3(0, 1.0, 0)
	add_child(dung_mi)
