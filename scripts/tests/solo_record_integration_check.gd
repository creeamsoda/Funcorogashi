extends Node
## 正常終了だけを自己記録へ登録する GameManager と ScoreStore の統合確認。
## 実行時には APPDATA を .godot/test-runtime-record-integration に切り替える。

var _ok := true
var _test_directory := ""
var _record_path := ""


func _ready() -> void:
	_test_directory = "user://solo_record_integration_%d" % Time.get_ticks_usec()
	_record_path = _test_directory + "/records.json"
	_check(DirAccess.make_dir_absolute(_test_directory) == OK, "create isolated record directory")
	var original_course := MatchSession.course_override
	var original_mode := MatchSession.mode
	MatchSession.mode = "solo"
	var short_course := SoloCourse.new()
	short_course.course_id = "integration-check"
	short_course.duration = 0.1
	MatchSession.course_override = short_course

	var early := _new_game()
	_check(early.time_left > 0.0, "early end is before deadline")
	early._end_match()
	_check(early._score_store.records(early.score_profile).is_empty(), "early end does not save")
	_check(not FileAccess.file_exists(_record_path), "early end creates no record file")
	early.queue_free()
	await get_tree().process_frame

	var debug_game := _new_game()
	debug_game.players[0].debug_growth_enabled = true
	debug_game.players[0].debug_growth_enabled = false
	_check(debug_game.players[0].debug_growth_used, "debug flag remembers earlier enable")
	await _wait_for_finish(debug_game)
	_check(debug_game.time_left == 0.0, "debug run reaches normal deadline")
	_check(debug_game._score_store.records(debug_game.score_profile).is_empty(), "disabled debug after use cannot save")
	_check(not FileAccess.file_exists(_record_path), "debug run creates no record file")
	debug_game.queue_free()
	await get_tree().process_frame

	var normal := _new_game()
	var completions := [0]
	normal.match_ended.connect(func(_results: Array) -> void: completions[0] += 1)
	await _wait_for_finish(normal)
	var original_profile := normal.score_profile
	var entries := normal._score_store.records(original_profile)
	_check(normal.time_left == 0.0 and completions[0] == 1, "normal run finishes once at deadline")
	_check(entries.size() == 1, "normal run creates exactly one record")
	if entries.size() == 1:
		_check(entries[0]["run_id"] == normal._run_id, "record uses this run id")
		_check(entries[0]["score"] == normal.final_results[0]["size"], "record matches frozen final score")
	var saved_contents := FileAccess.get_file_as_string(_record_path)
	normal._end_match()
	normal._end_match()
	_check(completions[0] == 1 and FileAccess.get_file_as_string(_record_path) == saved_contents, "repeated end does not rewrite or duplicate record")
	normal.queue_free()
	await get_tree().process_frame

	# 制限時間が変われば同じコースIDでも別の記録条件になる。
	var alternate_course := short_course.duplicate(true) as SoloCourse
	alternate_course.duration = 0.15
	MatchSession.course_override = alternate_course
	var alternate := _new_game()
	await _wait_for_finish(alternate)
	_check(alternate.score_profile != original_profile, "duration creates a distinct profile")
	_check(alternate._score_store.records(alternate.score_profile).size() == 1, "alternate profile stores its own record")
	_check(alternate._score_store.records(original_profile).size() == 1, "original profile remains separate")
	alternate.queue_free()
	await get_tree().process_frame

	# 開始後にコース内容を変えた場合も通常の記録へ混ぜない。
	var changed_course := short_course.duplicate(true) as SoloCourse
	MatchSession.course_override = changed_course
	var changed := _new_game()
	changed_course.version += 1
	var before_changed := FileAccess.get_file_as_string(_record_path)
	await _wait_for_finish(changed)
	_check(FileAccess.get_file_as_string(_record_path) == before_changed, "mid-run course changes do not save")
	changed.queue_free()
	await get_tree().process_frame

	MatchSession.course_override = original_course
	MatchSession.mode = original_mode
	for filename in DirAccess.get_files_at(_test_directory):
		DirAccess.remove_absolute(_test_directory.path_join(filename))
	DirAccess.remove_absolute(_test_directory)
	print("[solo_record_integration_check] result=", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _new_game() -> GameManager:
	var game := load("res://scenes/Game.tscn").instantiate() as GameManager
	game._score_store.storage_path = _record_path
	add_child(game)
	# ハードウェア入力が試験結果に影響しないよう待機ソースへ割り当てる。
	game.players[0].input_device = 9000
	return game


func _wait_for_finish(game: GameManager) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while game._running and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not game._running, "short course naturally reaches deadline")


func _check(condition: bool, label: String) -> void:
	if not condition:
		_ok = false
		push_error("[solo_record_integration_check] " + label)
