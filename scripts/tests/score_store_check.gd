extends Node
## user:// 内の試験専用ディレクトリだけを利用し、通常の自己記録に触れない。

var _ok := true
var _retry_count := 0
var _test_directory := ""


func _ready() -> void:
	_test_directory = "user://score_store_check_%d" % Time.get_ticks_usec()
	_check(DirAccess.make_dir_absolute(_test_directory) == OK, "create test directory")
	var path := _test_directory + "/records.json"
	var store := ScoreStore.new()
	store.storage_path = path
	_check(store.records("course-a").is_empty() and store.best("course-a") == 0.0, "empty store")
	var first := store.submit("course-a", 10.0, "first")
	_check(first["saved"] and first["new_best"] and first["best"] == 10.0, "first score")
	var tied := store.submit("course-a", 10.0, "tied")
	_check(tied["saved"] and not tied["new_best"], "tied score is not a new best")
	_check(tied["records"][0]["run_id"] == "first" and tied["records"][1]["run_id"] == "tied", "stable ties")
	var duplicate := store.submit("course-a", 999.0, "first")
	_check(duplicate["saved"] and not duplicate["new_best"] and duplicate["records"].size() == 2, "run cannot be registered twice")
	_check(store.best("course-a") == 10.0, "duplicate cannot change score")
	for invalid_score in [-1.0, INF, -INF, NAN]:
		_check(not store.submit("course-a", invalid_score, "bad-value")["saved"], "reject nonfinite or negative score")
	_check(not store.submit("", 1.0, "invalid")["saved"], "reject empty condition")
	_check(not store.submit("course-a", 1.0, "")["saved"], "reject empty run")
	for number in range(11, 23):
		_check(store.submit("course-a", float(number), "run-%d" % number)["saved"], "save ordered score")
	var entries := store.records("course-a")
	_check(entries.size() == 10 and entries[0]["score"] == 22.0 and entries[9]["score"] == 13.0, "only top ten retained")
	entries[0]["score"] = 0.0
	_check(store.best("course-a") == 22.0, "callers cannot modify in-memory records")
	var other := store.submit("course-b", 0.0, "first")
	_check(other["saved"] and other["new_best"] and other["records"].size() == 1, "separate conditions and valid zero")
	_check(store.best("course-a") == 22.0, "other condition preserved")
	var reloaded := ScoreStore.new()
	reloaded.storage_path = path
	_check(reloaded.best("course-a") == 22.0 and reloaded.records("course-b").size() == 1, "reload saved data")
	_check(not reloaded.submit("course-a", 500.0, "first")["new_best"] and reloaded.best("course-a") == 22.0, "remember runs outside top ten across reload")

	# 書き込み先だけを塞ぎ、保存失敗で既存ファイルやメモリが更新されないことを確認。
	var previous_file := FileAccess.get_file_as_string(path)
	_check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "simulate unwritable temporary file")
	var failed := reloaded.submit("course-a", 100.0, "retry-after-failure")
	_check(not failed["saved"] and not failed["error"].is_empty(), "report failed write")
	_check(reloaded.best("course-a") == 22.0 and FileAccess.get_file_as_string(path) == previous_file, "failed write preserves existing records")
	_check(DirAccess.remove_absolute(path + ".tmp") == OK, "clear simulated failure")
	_check(reloaded.submit("course-a", 100.0, "retry-after-failure")["new_best"], "failed attempt does not consume run id")
	_check(DirAccess.rename_absolute(path, path + ".bak") == OK, "simulate interrupted rename")
	var recovered := ScoreStore.new()
	recovered.storage_path = path
	_check(recovered.best("course-a") == 100.0 and FileAccess.file_exists(path), "restore interrupted transaction")

	var corrupt_path := _test_directory + "/corrupt.json"
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{invalid json")
	corrupt_file.close()
	var corrupt := ScoreStore.new()
	corrupt.storage_path = corrupt_path
	_check(corrupt.records("course-a").is_empty(), "malformed JSON starts empty")
	_check(_has_preserved_corrupt("corrupt.json.corrupt-"), "malformed JSON preserved separately")
	_check(corrupt.submit("course-a", 42.0, "recovered")["saved"], "save after corruption")
	var schema_path := _test_directory + "/schema.json"
	var schema_file := FileAccess.open(schema_path, FileAccess.WRITE)
	schema_file.store_string('{"version":1,"profiles":{"x":[{"score":-5}]},"seen_runs":{}}')
	schema_file.close()
	var invalid_schema := ScoreStore.new()
	invalid_schema.storage_path = schema_path
	_check(invalid_schema.best("x") == 0.0 and _has_preserved_corrupt("schema.json.corrupt-"), "reject malformed record schema")

	# 保存結果の表示、標準 ui_accept と異なる Joy-Con B、二重決定を確認。
	var results := SoloResults.new()
	add_child(results)
	results.retry_requested.connect(func() -> void: _retry_count += 1)
	results.show_score(100.0, 8, recovered.submit("course-a", 100.0, "retry-after-failure"))
	await get_tree().process_frame
	_check(results.get_node("SoloResultOverlay").find_child("FinalScore", true, false).text == "100.00", "display final score")
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_B
	accept.pressed = true
	results._input(accept)
	results._input(accept)
	_check(_retry_count == 1, "Joy-Con B triggers retry exactly once")
	results.queue_free()
	_cleanup()
	print("[score_store_check] result=", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_ok = false
		push_error("[score_store_check] " + label)


func _has_preserved_corrupt(prefix: String) -> bool:
	for name in DirAccess.get_files_at(_test_directory):
		if name.begins_with(prefix):
			return true
	return false


func _cleanup() -> void:
	for name in DirAccess.get_files_at(_test_directory):
		DirAccess.remove_absolute(_test_directory.path_join(name))
	DirAccess.remove_absolute(_test_directory)
