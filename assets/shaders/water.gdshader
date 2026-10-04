shader_type spatial;
// 호수 물: 둥근 사각(초타원) 모양으로 잘라 내고, 물가는 옅은 청록 → 가운데는 깊은 파랑, 물가에 흔들리는 거품 띠,
// 잔물결 반짝임. 비가 오면(world_wetness) 빗방울 동심원이 퍼진다. 텍스처 없음, 알파 블렌드 없음(가장자리만 discard).
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;

// 수면 절반 크기 (FishingSpot 이 spots.json 값으로 넣는다).
uniform vec2 half_extent = vec2(9.0, 7.0);
// 모양 지수: 2 = 타원, 클수록 사각형에 가깝다. village_layout.json 의 lake_shape_power 와 같아야 한다.
uniform float shape_power = 4.0;
uniform vec4 shallow_color : source_color = vec4(0.55, 0.85, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.24, 0.55, 0.74, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);

varying vec2 local_xz;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_xz = VERTEX.xz;
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
}

void fragment() {
	vec2 q = abs(local_xz) / half_extent;
	float r = pow(pow(q.x, shape_power) + pow(q.y, shape_power), 1.0 / shape_power);
	if (r > 1.0) {
		discard;
	}
	float depth = smoothstep(0.0, 0.55, 1.0 - r);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, depth);
	float t = TIME;
	// 잔물결: 서로 다른 방향의 사인 물결 둘을 곱해 반짝이는 줄무늬.
	float wave = sin(local_xz.x * 1.6 + local_xz.y * 0.7 + t * 1.3) * sin(local_xz.y * 1.9 - local_xz.x * 0.4 - t * 1.05);
	color += vec3(0.08, 0.1, 0.1) * smoothstep(0.55, 0.95, wave);
	// 물가 거품 띠: 둘레를 따라 출렁인다.
	float angle = atan(local_xz.y, local_xz.x);
	float foam_edge = 0.94 + 0.02 * sin(angle * 14.0 + t * 1.6) + 0.015 * sin(angle * 31.0 - t * 2.3);
	float foam = smoothstep(foam_edge - 0.02, foam_edge + 0.01, r);
	color = mix(color, foam_color.rgb, foam * 0.85);
	// 빗방울 동심원 (1.5m 칸마다 하나, 칸마다 다른 시각에 떨어진다).
	if (world_wetness > 0.01) {
		vec2 cell = floor(local_xz / 1.5);
		vec2 center = (cell + 0.3 + 0.4 * vec2(hash2(cell), hash2(cell + 7.1))) * 1.5;
		float phase = fract(t * 0.8 + hash2(cell + 3.3));
		float ring = abs(length(local_xz - center) - phase * 0.7);
		color = mix(color, foam_color.rgb, smoothstep(0.05, 0.0, ring) * (1.0 - phase) * world_wetness * 0.7);
	}
	ALBEDO = color;
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
}
