// 툰 / 일반 라이팅 셰이더가 공유하는 본문. render_mode만 다르다.
#include "res://assets/shaders/include/world_curve.gdshaderinc"

// 툰 경계의 부드러움. diffuse_toon에서는 ROUGHNESS가 경계 블러를 결정한다.
global uniform float toon_softness;
// 비에 젖은 정도(0~1). SkyController가 날씨에 따라 천천히 올리고 내린다. 젖으면 색이 어두워진다.
global uniform float world_wetness;
// 밤 조명 세기(0~1). 가로등·창문처럼 emission 이 있는 머티리얼만 밤에 빛난다.
global uniform float night_light;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
// 밤에만 켜지는 자체 발광 (가로등 갓, 창문).
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

void vertex() {
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
	// 정점 색(메시·MultiMesh 인스턴스 색)은 sRGB 로 칠해 두었다. 조명 계산은 선형 공간이라 여기서 바꾼다 (정점마다 한 번).
	COLOR.rgb = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb));
}

void fragment() {
	// 정점 색이 없는 메시는 COLOR가 흰색이라 그대로다. 나무처럼 부위별 색을 정점 색으로 칠한 메시는 머티리얼 하나로 그린다.
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb * COLOR.rgb;
	ALBEDO = base * mix(1.0, 0.72, world_wetness);
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
	EMISSION = emission * emission_energy * night_light;
}
