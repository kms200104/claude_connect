shader_type spatial;
// 아파트 창유리 너머 바깥 풍경 (v0.12): 집에 들어갈 때 마을의 그 집 자리에서 여섯 방향으로 찍은 사진(HomeView)을
// "카메라 → 유리" 방향으로 읽는다. 진짜 창처럼 보는 각도에 따라 바깥이 달라 보이고, 매 프레임은 텍스처 한 번 읽기.
// 사진마다 찍은 카메라 축(face_dir · face_right · face_up)으로 방향 → 사진 좌표를 직접 계산한다 (시야각 90°).
render_mode unshaded, cull_disabled;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

uniform sampler2DArray faces : source_color, filter_linear, repeat_disable;
uniform vec3 face_dir[6];
uniform vec3 face_right[6];
uniform vec3 face_up[6];
// 사진을 아직 못 찍었으면 하늘색 유리.
uniform float has_view = 0.0;
uniform vec3 sky_color : source_color = vec3(0.72, 0.86, 0.98);
// 1인칭 창밖 보기 (v0.13.5): 마을의 그 집 자리에 같은 방향으로 둔 카메라가 찍는 실시간 화면(HomeFirstPerson).
// 메인 카메라와 화각·비율이 같으므로 화면 좌표(SCREEN_UV) 그대로 읽으면 창 너머가 맞아떨어진다.
uniform float use_live = 0.0;
uniform sampler2D live_view : source_color, filter_linear, repeat_disable;
// 유리 빛깔과 가장자리 반사.
uniform vec3 tint : source_color = vec3(0.96, 0.99, 1.0);
uniform float reflect = 0.22;

varying vec3 world_pos;

void vertex() {
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 outside_color(vec3 dir) {
	int best = 0;
	float best_d = -2.0;
	for (int i = 0; i < 6; i++) {
		float d = dot(dir, face_dir[i]);
		if (d > best_d) {
			best_d = d;
			best = i;
		}
	}
	vec2 xy = vec2(dot(dir, face_right[best]), dot(dir, face_up[best])) / max(best_d, 0.0001);
	vec2 uv = vec2(0.5 + 0.5 * xy.x, 0.5 - 0.5 * xy.y);
	return texture(faces, vec3(clamp(uv, vec2(0.001), vec2(0.999)), float(best))).rgb;
}

void fragment() {
	vec3 dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 outside = has_view > 0.5 ? outside_color(dir) : mix(sky_color, vec3(1.0), clamp(-dir.y, 0.0, 1.0) * 0.3);
	if (use_live > 0.5) {
		outside = texture(live_view, SCREEN_UV).rgb;
	}
	float edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = mix(outside * tint, vec3(1.0), edge * reflect);
}
