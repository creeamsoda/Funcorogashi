extends Node3D
## Phase 0 開発ツールの headless 自動テスト(操作不要):
##  - デバッグビルドで GameManager に DebugTools が追加されるか
##  - 調整パネルが BalanceConfig のグループを列挙し、開くと一時停止・閉じると解除されるか
##  - パネル経由の変更が Config.balance に即反映され、保存→再読込で往復できるか(テスト用パスを使用)
##  - F2 相当で線が描かれるか
##  - アリーナ境界が Stage に一元化されているか

const TEMP_PATH := "user://debug_tools_check_balance.tres"


func _ready() -> void:
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(gm)
	await get_tree().process_frame

	var failures: Array[String] = []
	var tools := gm.get_node_or_null("DebugTools") as DebugTools
	if tools == null:
		_finish(["debug_tools_missing"])
		return
	var panel := tools.panel
	if not ("Dash" in panel.group_names() and "Drop & Pickup" in panel.group_names()):
		failures.append("groups=%s" % str(panel.group_names()))

	panel.open()
	if not get_tree().paused or not panel.visible:
		failures.append("open_pause")
	panel.close()
	if get_tree().paused or panel.visible:
		failures.append("close_unpause")

	# 値の即時反映 → テスト用パスへ保存 → 別値にして再読込で戻る
	var original: float = Config.balance.dash_speed_max
	panel._set_value("dash_speed_max", 23.5)
	if not is_equal_approx(Config.balance.dash_speed_max, 23.5):
		failures.append("live_set")
	if panel.save_to_file(TEMP_PATH) != OK:
		failures.append("save")
	Config.balance.dash_speed_max = 1.0
	panel.reload_from_file(TEMP_PATH)
	if not is_equal_approx(Config.balance.dash_speed_max, 23.5):
		failures.append("reload=%s" % Config.balance.dash_speed_max)
	Config.balance.dash_speed_max = original
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

	tools.overlay.visible = true
	await get_tree().process_frame
	if tools.overlay.line_count() <= 0:
		failures.append("overlay_lines")

	if Player.ARENA_HX != Stage.HALF_X or Player.ARENA_HZ != Stage.HALF_Z \
			or Animal.HX != Stage.HALF_X or Stage.STAGE_SIZE != Vector2(36.0, 24.0):
		failures.append("arena_bounds")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	print("[debug_tools_check] result=", ("PASS" if failures.is_empty() else "FAIL"), " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
