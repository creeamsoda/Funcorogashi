class_name Results
extends CanvasLayer
## 結果画面: サイズ降順ランキング + サブ表彰(突進命中数1位)。
## show_results(results) で表示。results 要素: {player_id:int, size:float, dash_hits:int}
## 注: Dictionary の "size" キーは r["size"] で参照(r.size は Dictionary.size() と衝突するため)。

func show_results(results: Array) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := _label("RESULT", 52, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sorted := results.duplicate()
	sorted.sort_custom(func(a, b): return a["size"] > b["size"])
	var medals := ["1st", "2nd", "3rd", "4th"]
	for rank in sorted.size():
		var r = sorted[rank]
		var pid: int = r["player_id"]
		var col: Color = Player.PLAYER_COLORS[pid % Player.PLAYER_COLORS.size()]
		vbox.add_child(_label("%s   P%d   size %.1f" % [medals[rank % medals.size()], pid + 1, r["size"]], 32, col))

	var best = _top_by(results, "dash_hits")
	if best != null:
		var bpid: int = best["player_id"]
		var sub := _label("DASH HITS #1 :  P%d  (%d)" % [bpid + 1, best["dash_hits"]], 26, Color(1.0, 0.9, 0.4))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub)

func _top_by(results: Array, key: String) -> Variant:
	var best: Variant = null
	for r in results:
		if best == null or r[key] > best[key]:
			best = r
	return best

func _label(text: String, fs: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
