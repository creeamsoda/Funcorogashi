shader_type spatial;
// パーティクル用。板(QuadMesh)を自分の面の中で angle_deg だけ回してから描く。
// Transform Align(速度に向きを合わせる)を使っていても、そこからさらに固定角度ずらせる。
// 板ごと回すので画像は歪まない。見た目は StandardMaterial3D の
// 「陰影なし・半透明・両面・頂点色(粒の色)を使う」と同じ。
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float angle_deg : hint_range(-180.0, 180.0) = 0.0; // 板を回す角度(度。正 = 反時計回り)

void vertex() {
	float a = radians(angle_deg);
	VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
}

void fragment() {
	vec4 c = texture(albedo_texture, UV) * albedo_color * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
