shader_type spatial;
// 加速板の床面。オレンジの下地の上に、灰色の太い長方形の枠線が中央から外へ広がり続ける。
// 線の太さ・間隔はどの辺も同じメートル数(板の中心にある長辺方向の線分からの距離で縞を作る)。
// そのため内側ほど細長く、中心は長辺方向の1本線から湧き出す。外側の枠は板の縁と一致する。

instance uniform vec2 pad_half_size = vec2(1.25, 3.0); // 板の半分のサイズ(m。x, z。板ごとに設定)
uniform vec3 base_color : source_color = vec3(1.0, 0.55, 0.1);
uniform vec3 line_color : source_color = vec3(0.55, 0.55, 0.55);
uniform float line_spacing = 0.6;   // 枠線の間隔(m)
uniform float line_width = 0.2;     // 枠線の太さ(m)
uniform float scroll_speed = 0.6;   // 外へ広がる速さ(m/s)
uniform float emission_ratio = 0.25; // 色に対する自己発光の割合(暗所でも見えるように)

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX.xz; // BoxMesh は中心が原点
}

void fragment() {
	vec2 a = abs(local_pos);
	// 中心の線分(短辺に合わせて縮めた残り)からのチェビシェフ距離。0=中心線、短辺の半分=板の縁
	vec2 core = max(pad_half_size - vec2(min(pad_half_size.x, pad_half_size.y)), vec2(0.0));
	vec2 q = max(a - core, vec2(0.0));
	float d = max(q.x, q.y);
	// 縞の位相(0〜1)。時間とともに減るので模様は外へ流れる
	float phase = fract((d - TIME * scroll_speed) / line_spacing);
	float w = clamp(line_width / line_spacing, 0.0, 1.0);
	float aa = fwidth(d) / line_spacing;
	// 位相 0〜w が線。両端をなめらかにしてちらつきを抑える
	float line = smoothstep(0.0, aa, phase) * (1.0 - smoothstep(w - aa, w, phase));
	vec3 col = mix(base_color, line_color, line);
	ALBEDO = col;
	EMISSION = col * emission_ratio;
}
