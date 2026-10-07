shader_type spatial;
// 호수 물: 둥근 사각(초타원) 모양 — 또는 실제 윤곽(거리 그림, use_outline) — 으로 잘라 내고, 물가는 옅은 청록 → 가운데는 깊은 파랑, 물가에 흔들리는 거품 띠,
// 잔물결 반짝임. v0.9: 여울(얕은 물, 최대 2곳)은 모래 바닥이 비치는 맑은 물빛 + 햇빛 무늬, 그 밖의 가운데는 더 짙은 깊은 물.
// 비가 오면(world_wetness) 빗방울 동심원이 퍼진다. 텍스처 없음, 알파 블렌드 없음(가장자리만 discard).
// v0.13.5 물빛 다듬기:
//   - 윤곽 호수는 물가에서 실제 거리(m)로 깊어진다 (얕은 청록 → 깊은 파랑 → 가운데 짙은 남색). 물가 1m 는 모래 바닥이 비친다.
//   - 잔물결 법선(사인 물결 넷): 비스듬히 볼수록 하늘빛 반사, 먼 물결에 반짝이는 윤슬(낮에만).
//     카메라는 늘 북쪽을 보고 해는 대개 남쪽(카메라 뒤)이라 진짜 햇빛 반사로는 윤슬이 거의 안 보인다 → '카메라 앞 하늘'을 비추는 물결에서 반짝이게 한다.
//   - 깊은 물 위로 천천히 흐르는 물결 무늬(잡음 등고선), 물가로 밀려왔다 빠지는 두 번째 거품 줄.
//   멀리서는 무늬가 화소보다 촘촘해지므로 fwidth 로 흐리게 해 반짝임(계단)이 없다.
render_mode diffuse_toon, specular_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;
// 밤 정도(0~1, 가로등이 켜지는 만큼): 하늘 반사를 밤하늘 빛으로.
global uniform float night_light;

// 수면 절반 크기 (FishingSpot 이 spots.json 값으로 넣는다).
uniform vec2 half_extent = vec2(9.0, 7.0);
// 모양 지수: 2 = 타원, 클수록 사각형에 가깝다. village_layout.json 의 lake_shape_power 와 같아야 한다.
uniform float shape_power = 4.0;
// 실제 윤곽 호수: 윤곽까지의 부호 있는 거리 그림 (FishingSpot 이 data/fish/sdf/<id>.json 으로 만든다).
// 0.5 = 윤곽, 안쪽 < 0.5. 거리(m) = (값 - 0.5) * 2 * sdf_range. 그림 영역 = 수면 원점 기준 ±sdf_half.
// sdf_far_range > 0 이면 G 채널에 같은 거리를 ±sdf_far_range m 로 (큰 호수 가운데까지의 깊이).
uniform bool use_outline = false;
uniform sampler2D outline_sdf : filter_linear, repeat_disable;
uniform vec2 sdf_half = vec2(16.0, 16.0);
uniform float sdf_range = 4.0;
uniform float sdf_far_range = 0.0;
uniform vec4 shallow_color : source_color = vec4(0.55, 0.85, 0.84, 1.0);
uniform vec4 deep_color : source_color = vec4(0.24, 0.55, 0.74, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
// 여울: (가운데 x, z, 절반 x, 절반 z) — 수면 원점 기준. 절반이 0 이면 없음.
uniform vec4 shallow_a = vec4(0.0);
uniform vec4 shallow_b = vec4(0.0);
uniform vec4 sand_color : source_color = vec4(0.86, 0.9, 0.72, 1.0);
uniform vec4 abyss_color : source_color = vec4(0.1, 0.32, 0.52, 1.0);
// 윤곽 호수: 이 거리(m)에 걸쳐 깊은 물 → 가운데 짙은 물.
uniform vec2 abyss_range = vec2(6.0, 26.0);
// 하늘 반사 (낮 · 밤)와 세기, 윤슬 세기 · 윤슬이 비추는 하늘 높이(rad).
uniform vec4 sky_day : source_color = vec4(0.8, 0.92, 1.0, 1.0);
uniform vec4 sky_night : source_color = vec4(0.12, 0.17, 0.3, 1.0);
uniform float reflect_strength = 0.55;
uniform float glint = 1.1;
uniform float glint_elevation = 0.42;
// 물결 무늬 · 잔물결 크기.
uniform float ripple_scale = 1.0;

varying vec2 local_xz;
varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 값 잡음 (0~1).
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
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

// 잔물결 높이의 기울기 (방향 · 파장 · 빠르기가 다른 사인 물결 넷의 합).
vec2 ripple_slope(vec2 p, float t) {
	vec2 g = vec2(0.0);
	const vec2 D[4] = vec2[4](vec2(0.8, 0.6), vec2(-0.45, 0.9), vec2(0.97, -0.26), vec2(-0.7, -0.71));
	const float K[4] = float[4](1.1, 1.7, 2.9, 4.3);
	const float W[4] = float[4](1.2, 1.5, 2.1, 2.7);
	const float A[4] = float[4](0.05, 0.035, 0.02, 0.012);
	for (int i = 0; i < 4; i++) {
		float k = K[i] * ripple_scale;
		g += D[i] * (A[i] * k * cos(dot(D[i], p) * k + t * W[i]));
	}
	return g;
}

void vertex() {
	local_xz = VERTEX.xz;
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r;
	float edge_dist = 0.0; // 윤곽에서 안쪽으로 얼마나 들어왔는지(m), 윤곽 호수만.
	if (use_outline) {
		vec2 suv = local_xz / (2.0 * sdf_half) + 0.5;
		vec2 field = texture(outline_sdf, suv).rg;
		float sd = (field.r - 0.5) * 2.0 * sdf_range;
		if (sd > 0.0) {
			discard;
		}
		edge_dist = -sd;
		// 물가 range 넘어서는 촘촘한 값이 끝나므로 깊이용 채널로 잇는다 (물가 쪽은 촘촘한 값 그대로 — 깊이 채널은 0.25m 계단이라).
		if (sdf_far_range > 0.0) {
			float far_dist = -(field.g - 0.5) * 2.0 * sdf_far_range;
			edge_dist = mix(edge_dist, max(edge_dist, far_dist), smoothstep(sdf_range - 1.0, sdf_range - 0.1, edge_dist));
		}
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
	float cam_dist = length(CAMERA_POSITION_WORLD - world_pos);
	float shallow = max(shallow_of(shallow_a, local_xz), shallow_of(shallow_b, local_xz));
	float depth = smoothstep(0.0, 0.55, 1.0 - r) * (1.0 - shallow);
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, depth);
	// 깊은 물: 여울이 있는 호수는 가운데를 더 짙게 (얕은 곳과 한눈에 구분).
	float has_shallow = step(0.001, shallow_a.z + shallow_b.z);
	color = mix(color, abyss_color.rgb, smoothstep(0.25, 0.75, 1.0 - r) * (1.0 - shallow) * has_shallow * 0.75);
	if (use_outline) {
		// 큰 호수: 물가에서 멀어질수록 실제 거리로 더 짙어진다 (윤곽 호수는 3.5m 에서 끝나던 깊이를 수십 m 까지).
		float far = smoothstep(abyss_range.x, abyss_range.y, edge_dist) * (1.0 - shallow);
		color = mix(color, abyss_color.rgb, far * 0.7);
		// 물가 1m: 모래 바닥이 비친다.
		color = mix(mix(sand_color.rgb, shallow_color.rgb, 0.45), color, smoothstep(0.05, 1.1, edge_dist));
	}
	// 여울: 모래 바닥이 비치고, 햇빛이 물결에 꺾여 바닥에 그물 무늬(코스틱)를 그린다.
	if (shallow > 0.001) {
		vec2 c = local_xz * 1.7;
		float caustic = abs(sin(c.x + sin(c.y * 1.3 + t * 0.9)) * sin(c.y + sin(c.x * 1.1 - t * 0.7)));
		vec3 bed = sand_color.rgb + vec3(0.1) * smoothstep(0.75, 0.98, caustic);
		color = mix(color, mix(shallow_color.rgb, bed, 0.6), shallow * 0.85);
	}
	// 깊은 물 위를 천천히 흐르는 물결 무늬: 잡음의 등고선 (멀어 촘촘해지면 흐리게).
	// 한쪽(바람 방향)으로 늘인 잡음이라 닫힌 고리보다 길게 이어지는 물결 줄이 된다.
	vec2 flow = local_xz * vec2(0.16, 0.42) * ripple_scale + vec2(t * 0.03, t * 0.05);
	float n = noise2(flow + vec2(noise2(flow * 0.7 - t * 0.02) * 1.6, 0.0)) * 3.5;
	float line_w = fwidth(n) * 1.2 + 0.03;
	// 등고선(정수 값)까지의 거리: 0 이면 줄 위.
	float to_line = 0.5 - abs(fract(n) - 0.5);
	float lines = 1.0 - smoothstep(0.015, 0.015 + line_w, to_line);
	lines *= (1.0 - smoothstep(18.0, 45.0, cam_dist)) * smoothstep(0.6, 2.5, use_outline ? edge_dist : (1.0 - r) * 6.0) * (1.0 - shallow);
	color += vec3(0.07, 0.09, 0.1) * lines;
	// 잔물결: 서로 다른 방향의 사인 물결 둘을 곱해 반짝이는 줄무늬. 바둑판처럼 보이지 않게 천천히 흐르는 잡음으로 듬성듬성.
	float wave = sin(local_xz.x * 1.6 + local_xz.y * 0.7 + t * 1.3) * sin(local_xz.y * 1.9 - local_xz.x * 0.4 - t * 1.05);
	float patch = smoothstep(0.45, 0.8, noise2(local_xz * 0.22 + vec2(-t * 0.04, t * 0.06)));
	color += vec3(0.07, 0.09, 0.09) * smoothstep(0.6, 0.95, wave) * patch * (1.0 - smoothstep(25.0, 60.0, cam_dist) * 0.7);
	// 물가 거품 띠: 둘레를 따라 출렁인다.
	float angle = atan(local_xz.y, local_xz.x);
	float foam_edge = 0.94 + 0.02 * sin(angle * 14.0 + t * 1.6) + 0.015 * sin(angle * 31.0 - t * 2.3);
	float foam = smoothstep(foam_edge - 0.02, foam_edge + 0.01, r);
	if (use_outline) {
		// 윤곽 따라 출렁이는 거품 띠 (물가 0.45m 안쪽에서 시작).
		float wob = 0.08 * sin(local_xz.x * 2.1 + local_xz.y * 1.3 + t * 1.6) + 0.06 * sin(local_xz.x * 4.7 - local_xz.y * 3.9 - t * 2.3);
		foam = 1.0 - smoothstep(0.12 + wob, 0.42 + wob, edge_dist);
		// 밀려왔다 빠지는 두 번째 거품 줄: 물가에서 0.5~1.1m 를 오가고, 바깥으로 갈수록(빠질 때) 옅어진다.
		float phase = t * 0.55 + noise2(local_xz * 0.18) * 6.2831;
		float lap = 0.8 + 0.3 * sin(phase);
		float lap_w = 0.07 + fwidth(edge_dist);
		float lap_line = 1.0 - smoothstep(lap_w * 0.4, lap_w, abs(edge_dist - lap));
		foam = max(foam, lap_line * (0.35 + 0.35 * cos(phase)) * (1.0 - smoothstep(20.0, 40.0, cam_dist)));
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
	// 잔물결 법선: 하늘 반사(비스듬히 볼수록) · 윤슬.
	vec2 slope = ripple_slope(local_xz, t) * (1.0 - smoothstep(30.0, 70.0, cam_dist) * 0.7);
	vec3 wave_n = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fres = pow(1.0 - clamp(dot(wave_n, to_cam), 0.0, 1.0), 4.0);
	vec3 sky = mix(sky_day.rgb, sky_night.rgb, clamp(night_light, 0.0, 1.0));
	color = mix(color, sky, clamp(fres * reflect_strength * (1.0 - foam) * (1.0 - world_wetness * 0.5), 0.0, 0.8));
	// 윤슬: 물결에 비친 방향이 카메라 앞쪽 하늘(glint_elevation 높이)과 맞는 물결 위에서만, 작은 점들이 반짝였다 사라진다.
	vec3 refl = reflect(-to_cam, wave_n);
	vec3 ahead = normalize(vec3(-to_cam.x, 0.0, -to_cam.z) + vec3(0.0001, 0.0, 0.0));
	ahead = ahead * cos(glint_elevation) + vec3(0.0, sin(glint_elevation), 0.0);
	float zone = smoothstep(0.96, 0.997, dot(refl, ahead));
	vec2 sp = local_xz * 4.0;
	float twinkle = noise2(sp + vec2(t * 0.9, -t * 0.7)) * noise2(sp * 1.7 - vec2(t * 0.6, t * 0.8));
	float sparkle = zone * smoothstep(0.6, 0.66, twinkle) * (1.0 - smoothstep(22.0, 45.0, cam_dist));
	sparkle *= (1.0 - foam) * (1.0 - shallow * 0.6) * (1.0 - world_wetness * 0.8) * (1.0 - clamp(night_light, 0.0, 1.0));
	ALBEDO = color;
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
	EMISSION = vec3(1.0, 0.97, 0.88) * sparkle * glint;
}
