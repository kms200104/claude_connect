shader_type spatial;
// 마을 바닥: 색 지도(잔디·길·모래톱, 0.25m/px) 위에 3m마다 반복하는 잔결을 겹쳐 가까이서도 뭉개지지 않게 한다.
// 툰 라이팅·월드 커브·젖은 땅은 다른 월드 머티리얼과 같다. 텍스처 2장, 샘플 3번.
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;

uniform sampler2D map_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 색 지도가 덮는 범위 (마을 가운데 ±map_extent 미터). village_layout.json 의 map_extent 와 같아야 한다.
uniform float map_extent = 64.0;
uniform float detail_tile = 3.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
}

void fragment() {
	vec4 map = texture(map_texture, world_pos.xz / (2.0 * map_extent) + 0.5);
	float fine = texture(detail_texture, world_pos.xz / detail_tile).r - 0.5;
	float broad = texture(detail_texture, world_pos.xz / (detail_tile * 4.3) + vec2(0.37, 0.11)).r - 0.5;
	// 잔디(알파 1)는 잔결을 세게, 흙길·모래는 약하게.
	float grain = fine * detail_strength * mix(0.45, 1.0, map.a) + broad * 0.12;
	vec3 base = map.rgb * (1.0 + grain);
	ALBEDO = base * mix(1.0, 0.7, world_wetness);
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
}
