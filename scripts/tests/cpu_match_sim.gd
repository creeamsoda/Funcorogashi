extends Node3D
## CPUだけの試合を headless で回し、詰まり・壁激突・命中率・回収数を記録する(C4〜C7の検証)。
## 実時間を待たずに速く回すため --fixed-fps 60 を付けて実行する:
##   godot --headless --path . --fixed-fps 60 res://scenes/tests/CpuMatchSim.tscn
## 引数(-- の後): --matches=N(4体戦の回数。既定2) --duration=秒(既定は BalanceConfig.match_duration)
##
## 判定:
##  collect    : CPU1体だけの試合で、時間とともにサイズが伸びる。詰まり続けない(回り道の回数が多すぎない)
##  versus     : CPU4体の試合で、突進が当たる場面と、回避の突進を打つ場面が両方起きる
##  aggression : aggression を上げると攻撃の突進の回数がはっきり増える

var _failures: Array[String] = []
var _args := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	var base_duration: float = float(_args.get("duration", Config.balance.match_duration))
	await _test_collect()
	var matches := int(_args.get("matches", 2))
	var totals := {}
	for i in matches:
		var r := await _run_match(4, base_duration, {})
		_print_match("versus#%d" % (i + 1), r)
		for k in r["sum"]:
			totals[k] = float(totals.get(k, 0.0)) + float(r["sum"][k])
	print("  [versus total] ", _fmt(totals))
	var hit_rate := float(totals.get("dash_hits", 0.0)) / maxf(float(totals.get("attack_dashes", 0.0)), 1.0)
	print("  [versus] hit_rate=%.0f%% (dash_hits / attack_dashes)" % (hit_rate * 100.0))
	_expect(float(totals.get("dash_hits", 0.0)) >= 1.0, "dash hits happen between CPUs")
	_expect(float(totals.get("evade_dashes", 0.0)) >= 1.0, "evade dashes happen between CPUs")
	await _test_aggression()
	print("[cpu_match_sim] result=", "PASS" if _failures.is_empty() else "FAIL", " failures=", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


## C4: CPU1体だけで40秒。サイズの推移と詰まりを見る。
func _test_collect() -> void:
	var r := await _run_match(1, 40.0, {}, [10.0, 20.0, 30.0, 40.0])
	_print_match("collect", r)
	var timeline: Array = r["timeline"]
	print("  [collect] size timeline=", timeline)
	var grows := timeline.size() >= 3 and float(timeline[-1]) > float(timeline[0]) and float(timeline[-1]) > Config.balance.size_start + 3.0
	_expect(grows, "single CPU grows over time %s" % str(timeline))
	_expect(float(r["sum"]["unstuck"]) <= 12.0, "single CPU is not stuck often (unstuck=%d)" % int(r["sum"]["unstuck"]))
	_expect(float(r["sum"]["wall_crashes"]) <= 3.0, "single CPU rarely crashes into walls (%d)" % int(r["sum"]["wall_crashes"]))


## C6: aggression を 0.3 と 2.5 で比べる。
func _test_aggression() -> void:
	var low := await _run_match(4, 60.0, {"aggression": 0.3})
	var high := await _run_match(4, 60.0, {"aggression": 2.5})
	var a_low := float(low["sum"]["attack_dashes"])
	var a_high := float(high["sum"]["attack_dashes"])
	print("  [aggression] low(0.3) attacks=%d hits=%d / high(2.5) attacks=%d hits=%d" % [
		a_low, int(low["sum"]["dash_hits"]), a_high, int(high["sum"]["dash_hits"])])
	_expect(a_high >= a_low * 1.5 + 3.0, "aggression clearly increases attacks (%d -> %d)" % [a_low, a_high])


## n体のCPUだけの試合を duration 秒回す。overrides は CpuProfile の値の上書き。
## 返り値: {sum: 全CPU合計の集計, per: CPUごと, timeline: sample_times のサイズ(1体目)}
func _run_match(n: int, duration: float, overrides: Dictionary, sample_times: Array = []) -> Dictionary:
	var saved_duration := Config.balance.match_duration
	var saved := {}
	for k in overrides:
		saved[k] = Config.cpu.get(k)
		Config.cpu.set(k, overrides[k])
	Config.balance.match_duration = duration
	var gm: GameManager = (load("res://scenes/Game.tscn") as PackedScene).instantiate()
	gm.mode = "solo"
	gm.solo_human_count = 0
	gm.solo_total_count = n
	add_child(gm)
	var ended := {"results": []}
	gm.match_ended.connect(func(r: Array) -> void: ended.results = r)
	var timeline: Array = []
	var next_sample := 0
	var cpus: Array[CpuBeetle] = []
	for p in gm.players:
		cpus.append(p as CpuBeetle)
	while ended.results.is_empty():
		await get_tree().physics_frame
		if next_sample < sample_times.size() and gm.elapsed >= float(sample_times[next_sample]):
			timeline.append(snappedf(cpus[0].size, 0.01))
			next_sample += 1
	while next_sample < sample_times.size():
		timeline.append(snappedf(cpus[0].size, 0.01))
		next_sample += 1
	var per: Array = []
	var sum := {}
	for r in ended.results:
		var entry: Dictionary = (r as Dictionary).duplicate()
		var cpu: CpuBeetle = cpus[int(r["player_id"])]
		entry.merge(cpu.brain.counters)
		per.append(entry)
		for k in entry:
			if k in ["player_id", "cpu"]:
				continue
			sum[k] = float(sum.get(k, 0.0)) + float(entry[k])
	gm.queue_free()
	for _i in 3:
		await get_tree().process_frame
	Config.balance.match_duration = saved_duration
	for k in saved:
		Config.cpu.set(k, saved[k])
	return {"sum": sum, "per": per, "timeline": timeline}


func _print_match(label: String, r: Dictionary) -> void:
	print("  [%s] %s" % [label, _fmt(r["sum"])])
	for e in r["per"]:
		print("      P%d size=%.1f pickups=%d hits=%d recv=%d walls=%d attacks=%d evades=%d collect_dashes=%d unstuck=%d give_ups=%d" % [
			int(e["player_id"]) + 1, float(e["size"]), int(e["pickups"]), int(e["dash_hits"]), int(e["dash_hits_received"]),
			int(e["wall_crashes"]), int(e["attack_dashes"]), int(e["evade_dashes"]), int(e["collect_dashes"]),
			int(e["unstuck"]), int(e["give_ups"])])


func _fmt(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in ["size", "pickups", "dash_hits", "wall_crashes", "crash_attack", "crash_collect", "crash_evade", "crash_other", "attack_dashes", "evade_dashes", "collect_dashes", "unstuck", "give_ups", "boost_pads"]:
		if d.has(k):
			parts.append("%s=%s" % [k, str(snappedf(float(d[k]), 0.1))])
	return " ".join(parts)


func _expect(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
		push_error(label)
