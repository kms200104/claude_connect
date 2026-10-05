shader_type spatial;
// 캐릭터 전용 펠트(양모 인형) 질감. 툰 경계는 더 부드럽게, 겉면에 가는 섬유 결, 가장자리에 보풀 같은 옅은 테두리 빛.
// 정점 색·월드 곡률·젖음 처리는 toon_common 과 같다 (그 파일의 uniform 이름을 그대로 쓴다).
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;

uniform vec4 albedo : source_color = vec4(1.0);
// 섬유 결의 촘촘함(클수록 곱다)과 세기.
uniform float grain_scale = 70.0;
uniform float grain_strength = 0.06;
// 가장자리 보풀 빛.
uniform float fuzz_strength = 0.28;
uniform float fuzz_power = 2.4;
// 전체를 흰색 쪽으로 살짝 풀어 파스텔로 (0 = 그대로).
uniform float pastel = 0.14;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
	COLOR.rgb = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void fragment() {
	vec3 base = albedo.rgb * COLOR.rgb;
	base = mix(base, vec3(1.0), pastel * 0.5);
	// 섬유 결: 굵은 결과 고운 결을 섞어 천 같은 얼룩.
	float n = value_noise(local_pos * grain_scale) * 0.6 + value_noise(local_pos * grain_scale * 2.3) * 0.4;
	base *= 1.0 + (n - 0.5) * 2.0 * grain_strength;
	// 보풀: 시선과 비스듬한 면이 밝게 번진다.
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fuzz_power);
	base += base * rim * fuzz_strength;
	ALBEDO = base * mix(1.0, 0.72, world_wetness);
	ROUGHNESS = mix(toon_softness, 1.0, 0.6);
	METALLIC = 0.0;
}
