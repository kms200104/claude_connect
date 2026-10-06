shader_type spatial;
// 호수 물: 둥근 사각(초타원) 모양 — 또는 실제 윤곽(거리 그림, use_outline) — 으로 잘라 내고, 물가는 옅은 청록 → 가운데는 깊은 파랑, 물가에 흔들리는 거품 띠,
// 잔물결 반짝임. v0.9: 여울(얕은 물, 최대 2곳)은 모래 바닥이 비치는 맑은 물빛 + 햇빛 무늬, 그 밖의 가운데는 더 짙은 깊은 물.
// 비가 오면(world_wetness) 빗방울 동심원이 퍼진다. 텍스처 없음, 알파 블렌드 없음(가장자리만 discard).
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;

// 수면 절반 크기 (FishingSpot 이 spots.json 값으로 넣는다).
uniform vec2 half_extent = vec2(9.0, 7.0);
// 모양 지수: 2 = 타원, 클수록 사각형에 가깝다. village_layout.json 의 lake_shape_power 와 같아야 한다.
uniform float shape_power = 4.0;
// 실제 윤곽 호수: 윤곽까지의 부호 있는 거리 그림 (FishingSpot 이 data/fish/sdf/<id>.json 으로 만든다).
// 0.5 = 윤곽, 안쪽 < 0.5. 거리(m) = (값 - 0.5) * 2 * sdf_range. 그림 영역 = 수면 원점 기준 ±sdf_half.
uniform bool use_outline = false;
uniform sampler2D outline_sdf : filter_linear, repeat_disable;
uniform vec2 sdf_half = vec2(16.0, 16.0);
uniform float sdf_range = 4.0;
uniform vec4 shallow_color : source_color = vec4(0.55, 0.85, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.24, 0.55, 0.74, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
// 여울: (가운데 x, z, 절반 x, 절반 z) — 수면 원점 기준. 절반이 0 이면 없음.
uniform vec4 shallow_a = vec4(0.0);
uniform vec4 shallow_b = vec4(0.0);
uniform vec4 sand_color : source_color = vec4(0.86, 0.9, 0.72, 1.0);
uniform vec4 abyss_color : source_color = vec4(0.1, 0.32, 0.52, 1.0);

varying vec2 local_xz;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 여울 안이면 1, 가장자리에서 1.4m 에 걸쳐 0 으로.
float shallow_of(vec4 rect, vec2 p) {
	if (rect.z <= 0.0) {
		return 0.0;
	}
	vec2 d = abs(p - rect.xy) - rect.zw;
	float outside = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
	return 1.0 - smoothstep(-0.6, 1.4, outside);
}

void vertex() {
	local_xz = VERTEX.xz;
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
}

void fragment() {
	float r;
	float edge_dist = 0.0; // 윤곽에서 안쪽으로 얼마나 들어왔는지(m), 윤곽 호수만.
	if (use_outline) {
		vec2 suv = local_xz / (2.0 * sdf_half) + 0.5;
		float sd = (texture(outline_sdf, suv).r - 0.5) * 2.0 * sdf_range;
		if (sd > 0.0) {
			discard;
		}
		edge_dist = -sd;
		// 둥근 호수의 1 - r 와 비슷한 값 (물가 0 → 안쪽 1, 3.5m 에 걸쳐).
		r = 1.0 - clamp(edge_dist / 3.5, 0.0, 1.0);
	} else {
		vec2 q = abs(local_xz) / half_extent;
		r = pow(pow(q.x, shape_power) + pow(q.y, shape_power), 1.0 / shape_power);
		if (r > 1.0) {
			discard;
		}
	}
	float t = TIME;
	float shallow = max(shallow_of(shallow_a, local_xz), shallow_of(shallow_b, local_xz));
	float depth = smoothstep(0.0, 0.55, 1.0 - r) * (1.0 - shallow);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, depth);
	// 깊은 물: 여울이 있는 호수는 가운데를 더 짙게 (얕은 곳과 한눈에 구분).
	float has_shallow = step(0.001, shallow_a.z + shallow_b.z);
	color = mix(color, abyss_color.rgb, smoothstep(0.25, 0.75, 1.0 - r) * (1.0 - shallow) * has_shallow * 0.75);
	// 여울: 모래 바닥이 비치고, 햇빛이 물결에 꺾여 바닥에 그물 무늬(코스틱)를 그린다.
	if (shallow > 0.001) {
		vec2 c = local_xz * 1.7;
		float caustic = abs(sin(c.x + sin(c.y * 1.3 + t * 0.9)) * sin(c.y + sin(c.x * 1.1 - t * 0.7)));
		vec3 bed = sand_color.rgb + vec3(0.1) * smoothstep(0.75, 0.98, caustic);
		color = mix(color, mix(shallow_color.rgb, bed, 0.6), shallow * 0.85);
	}
	// 잔물결: 서로 다른 방향의 사인 물결 둘을 곱해 반짝이는 줄무늬.
	float wave = sin(local_xz.x * 1.6 + local_xz.y * 0.7 + t * 1.3) * sin(local_xz.y * 1.9 - local_xz.x * 0.4 - t * 1.05);
	color += vec3(0.08, 0.1, 0.1) * smoothstep(0.55, 0.95, wave);
	// 물가 거품 띠: 둘레를 따라 출렁인다.
	float angle = atan(local_xz.y, local_xz.x);
	float foam_edge = 0.94 + 0.02 * sin(angle * 14.0 + t * 1.6) + 0.015 * sin(angle * 31.0 - t * 2.3);
	float foam = smoothstep(foam_edge - 0.02, foam_edge + 0.01, r);
	if (use_outline) {
		// 윤곽 따라 출렁이는 거품 띠 (물가 0.45m 안쪽에서 시작).
		float wob = 0.08 * sin(local_xz.x * 2.1 + local_xz.y * 1.3 + t * 1.6) + 0.06 * sin(local_xz.x * 4.7 - local_xz.y * 3.9 - t * 2.3);
		foam = 1.0 - smoothstep(0.12 + wob, 0.42 + wob, edge_dist);
	}
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
