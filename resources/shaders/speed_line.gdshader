shader_type spatial;
// 突進の加速線(流線)。加算合成の白い細線。色・透明度はパーティクルの COLOR で付ける。
// use_texture = false なら UV から細長い線を手続き生成する(仮素材)。
// 描いた PNG に差し替えるときは streak_tex に設定して use_texture = true にする。
// 想定する PNG: 白、縦長(例 32x512)。上端(UV.y=0)が進行方向の先端で、下へフェードアウトする。
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform bool use_texture = false;
uniform sampler2D streak_tex : source_color, hint_default_white;
uniform float core_width : hint_range(0.01, 1.0) = 0.45; // 幅方向の芯の太さ(小さいほど鋭い)
uniform float head_length : hint_range(0.0, 0.5) = 0.06; // 先端の立ち上がり
uniform float tail_power : hint_range(0.1, 4.0) = 1.6;   // 尾のフェードの強さ
uniform float intensity : hint_range(0.0, 4.0) = 1.4;

void fragment() {
	float a;
	if (use_texture) {
		vec4 t = texture(streak_tex, UV);
		a = t.a * t.r;
	} else {
		float across = 1.0 - abs(UV.x * 2.0 - 1.0);
		float width = smoothstep(0.0, core_width, across);
		float head = smoothstep(0.0, max(head_length, 0.001), UV.y);
		float tail = pow(1.0 - UV.y, tail_power);
		a = width * head * tail;
	}
	ALBEDO = COLOR.rgb * intensity;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
