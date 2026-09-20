class_name ScoreStore
extends RefCounted
## 条件別の端末内記録。成功した保存だけをメモリに反映する。

const FORMAT_VERSION := 1
const RECORD_LIMIT := 10

var storage_path := "user://solo_records.json"
var _loaded_path := ""
var _data: Dictionary = {}
var _load_error := ""


func records(profile: String) -> Array:
	_load_once()
	return _data.get("profiles", {}).get(profile, []).duplicate(true)


func best(profile: String) -> float:
	var entries := records(profile)
	return float(entries[0]["score"]) if not entries.is_empty() else 0.0


func submit(profile: String, score: float, run_id: String) -> Dictionary:
	_load_once()
	if profile.strip_edges().is_empty() or run_id.strip_edges().is_empty():
		return _result(profile, false, false, "記録の識別子がありません。")
	if not is_finite(score) or score < 0.0:
		return _result(profile, false, false, "スコアが不正です。")
	if not _load_error.is_empty():
		return _result(profile, false, false, _load_error)
	var seen: Dictionary = _data["seen_runs"].get(profile, {})
	if seen.has(run_id):
		return _result(profile, true, false, "")

	var candidate := _data.duplicate(true)
	var entries: Array = candidate["profiles"].get(profile, [])
	var new_best := entries.is_empty() or score > float(entries[0]["score"])
	var timestamp := Time.get_datetime_string_from_system(true) + "Z"
	var entry := {"score": score, "run_id": run_id, "timestamp": timestamp}
	# 等しい値の手前には挿入しない。sort_custom の安定性に依存しない。
	var insertion := entries.size()
	for index in entries.size():
		if score > float(entries[index]["score"]):
			insertion = index
			break
	entries.insert(insertion, entry)
	if entries.size() > RECORD_LIMIT:
		entries.resize(RECORD_LIMIT)
	candidate["profiles"][profile] = entries
	var candidate_seen: Dictionary = candidate["seen_runs"].get(profile, {})
	candidate_seen[run_id] = timestamp
	candidate["seen_runs"][profile] = candidate_seen
	var error := _save_atomic(candidate)
	if not error.is_empty():
		return _result(profile, false, false, error)
	_data = candidate
	return _result(profile, true, new_best, "")


func _result(profile: String, saved: bool, new_best: bool, error: String) -> Dictionary:
	return {"saved": saved, "new_best": new_best, "best": best(profile),
		"records": records(profile), "error": error}


func _load_once() -> void:
	if _loaded_path == storage_path:
		return
	_loaded_path = storage_path
	_load_error = ""
	_data = {"version": FORMAT_VERSION, "profiles": {}, "seen_runs": {}}
	# 更新中に中断した場合、最後に成功したファイルを戻す。
	if not FileAccess.file_exists(storage_path) and FileAccess.file_exists(storage_path + ".bak"):
		if DirAccess.rename_absolute(storage_path + ".bak", storage_path) != OK:
			_load_error = "前回の記録を復元できませんでした。"
			return
	if not FileAccess.file_exists(storage_path):
		return
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		_load_error = "記録ファイルを読み込めませんでした。"
		return
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error == OK and _valid_data(json.data):
		_data = json.data
		return
	var suffix := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if DirAccess.rename_absolute(storage_path, storage_path + ".corrupt-" + suffix) != OK:
		_load_error = "不正な記録ファイルを退避できませんでした。"
		return
	# 破損ファイルは保存しておき、利用可能なバックアップがあれば採用する。
	if FileAccess.file_exists(storage_path + ".bak"):
		_loaded_path = ""
		_load_once()


func _valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.get("version") != FORMAT_VERSION:
		return false
	if not value.get("profiles") is Dictionary or not value.get("seen_runs") is Dictionary:
		return false
	var profiles: Dictionary = value["profiles"]
	var seen_runs: Dictionary = value["seen_runs"]
	for profile in seen_runs:
		if not profile is String or profile.strip_edges().is_empty() or not seen_runs[profile] is Dictionary:
			return false
		for run_id in seen_runs[profile]:
			if not run_id is String or run_id.strip_edges().is_empty() or not seen_runs[profile][run_id] is String:
				return false
	for profile in profiles:
		if not profile is String or profile.strip_edges().is_empty():
			return false
		if not profiles[profile] is Array or profiles[profile].size() > RECORD_LIMIT:
			return false
		var previous := INF
		var listed: Dictionary = {}
		for entry in profiles[profile]:
			if not entry is Dictionary:
				return false
			if not entry.get("score") is float and not entry.get("score") is int:
				return false
			var score := float(entry["score"])
			if not is_finite(score) or score < 0.0 or score > previous:
				return false
			if not entry.get("timestamp") is String or entry["timestamp"].is_empty():
				return false
			var run_id: Variant = entry.get("run_id")
			if not run_id is String or run_id.strip_edges().is_empty() or listed.has(run_id):
				return false
			if not seen_runs.get(profile, {}).has(run_id):
				return false
			listed[run_id] = true
			previous = score
	return true


func _save_atomic(candidate: Dictionary) -> String:
	var temp_path := storage_path + ".tmp"
	var backup_path := storage_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return "記録を保存できませんでした。"
	file.store_string(JSON.stringify(candidate, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		return "記録を書き込めませんでした。"
	var has_previous := FileAccess.file_exists(storage_path)
	if has_previous:
		if FileAccess.file_exists(backup_path) and DirAccess.remove_absolute(backup_path) != OK:
			DirAccess.remove_absolute(temp_path)
			return "記録のバックアップを更新できませんでした。"
		if DirAccess.rename_absolute(storage_path, backup_path) != OK:
			DirAccess.remove_absolute(temp_path)
			return "前回の記録を保護できませんでした。"
	if DirAccess.rename_absolute(temp_path, storage_path) != OK:
		if has_previous:
			DirAccess.rename_absolute(backup_path, storage_path)
		DirAccess.remove_absolute(temp_path)
		return "記録を更新できませんでした。前回の記録は保持されています。"
	if has_previous:
		DirAccess.remove_absolute(backup_path)
	return ""
