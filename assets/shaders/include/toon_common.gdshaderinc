// 툰 / 일반 라이팅 셰이더가 공유하는 본문. render_mode만 다르다.
#include "res://assets/shaders/include/world_curve.gdshaderinc"

// 툰 경계의 부드러움. diffuse_toon에서는 ROUGHNESS가 경계 블러를 결정한다.
global uniform float toon_softness;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

void vertex() {
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
}

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
}
