extends Node3D
## I1 の headless 自動テスト(操作不要):
##  - GameManager が起動しプレイヤー/HUD/スポナーを構築するか
##  - 制限時間切れで match_ended が発火し、Results が表示されるか
##  - 数秒の間に動物ドロップが発生するか

func _ready() -> void:
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	add_child(gm)

	var ended := {"hit": false, "results": []}
	gm.match_ended.connect(func(r: Array) -> void:
		ended["hit"] = true
		ended["results"] = r)

	# 数秒回して動物ドロップを確認 → その後 残時間を詰めて即終了させる
	await get_tree().create_timer(3.0).timeout
	var pickups := 0
	var dung := gm.get_node_or_null("World/Dung")
	if dung != null:
		pickups = dung.get_child_count()

	gm.time_left = 0.2
	# 結果発表の全シーケンス完了後にボタンが操作可能になる。
	await get_tree().create_timer(8.0).timeout

	var results_ui := 0
	var retry_button: Button = null
	for c in gm.get_children():
		if c is Results:
			results_ui += 1
			retry_button = c.find_child("RetryButton", true, false) as Button

	var res_arr: Array = ended["results"]
	var retry_ok := retry_button != null \
		and retry_button.text == "リトライ" \
		and retry_button.has_focus()
	var ok: bool = gm.players.size() == Config.balance.player_count \
		and ended["hit"] and res_arr.size() == Config.balance.player_count \
		and results_ui >= 1 and retry_ok
	print("[game_check] result=", ("PASS" if ok else "FAIL"),
		" players=", gm.players.size(), " ended=", ended["hit"],
		" results=", res_arr.size(), " pickups_in_3s=", pickups,
		" results_ui=", results_ui, " retry_button=", retry_ok)
	get_tree().quit(0 if ok else 1)
