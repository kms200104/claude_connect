shader_type spatial;
// 카메라 앞에 붙인 반투명 판 하나로 빗줄기와 안개, 물안개를 그린다 (드로우콜 1, 폴리곤 1장).
// 3중 시차 레이어(근경 빠른 빗줄기 · 중경 빗줄기 · 원경 미세 비안개)와 바람 요동, 번개 산란광을 구현.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

// 0 = 안 보임, 1 = 큰비. SkyController가 날씨에 맞춰 바꾼다.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rain_color : source_color = vec4(0.82, 0.89, 0.98, 1.0);
uniform vec4 mist_color : source_color = vec4(0.75, 0.82, 0.92, 0.4);
// 기본 낙하 속도 및 바람 기울기
uniform float fall_speed = 2.4;
uniform float slant = 0.08;

// SkyController 또는 전역에서 전달되는 번개 섬광
global uniform float lightning_flash;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 빗줄기 레이어 계산 함수
// col_count: 열 수, speed_mult: 속도 배율, length_mult: 빗줄기 길이, empty_ratio: 빈 공간 비율
float rain_layer(vec2 uv, float col_count, float speed_mult, float length_mult, float empty_ratio, float t) {
	float col = floor(uv.x * col_count);
	float r = hash1(col);
	float present = step(empty_ratio, r);
	
	// 낙하 위치 계산 (열마다 위상과 속도 차이)
	float speed = fall_speed * speed_mult * (0.8 + r * 0.4);
	float y = fract(uv.y * (1.2 + r * 0.5) - t * speed + r * 13.0);
	
	// 빗줄기 형태: 머리는 가늘고 꼬리는 서서히 흩어지는 물방울 유선형
	float head = 0.02 * length_mult;
	float tail = 0.22 * length_mult;
	float streak = smoothstep(0.0, head, y) * (1.0 - smoothstep(head, tail, y));
	
	// 가로 굵기: 가운데가 가장 진함
	float across = abs(fract(uv.x * col_count) - 0.5);
	float line = 1.0 - smoothstep(0.03, 0.16, across);
	
	return streak * line * present;
}

void fragment() {
	if (intensity <= 0.001) {
		discard;
	}
	
	// 시간에 따른 바람 요동 (돌풍 효과)
	float wind_sway = sin(TIME * 1.5) * 0.025 + sin(TIME * 3.7) * 0.01;
	float total_slant = slant + wind_sway;
	
	vec2 uv = UV;
	uv.x += uv.y * total_slant;
	
	float t = TIME;
	
	// 1. 원경 비안개 / 흩날리는 미세 빗줄기 (촘촘하고 은은함)
	float layer_far = rain_layer(uv, 110.0, 0.7, 0.8, 0.2, t);
	
	// 2. 중경 메인 빗줄기
	float layer_mid = rain_layer(uv + vec2(0.37, 0.15), 68.0, 1.0, 1.0, 0.28, t);
	
	// 3. 근경 굵고 빠른 빗줄기 (시차 체감 극대화)
	float layer_near = rain_layer(uv * 0.75 + vec2(0.81, 0.53), 32.0, 1.45, 1.35, 0.45, t);
	
	// 전체 빗줄기 밀도 조합
	float streaks = layer_far * 0.35 + layer_mid * 0.65 + layer_near * 0.85;
	
	// 배경 물안개(Mist / Fog) 은은한 농도: 비가 거셀수록 대기가 뿌옇게
	float mist_noise = sin(uv.x * 4.0 + t * 0.8) * cos(uv.y * 3.0 - t * 0.5) * 0.5 + 0.5;
	float mist = mist_noise * 0.12 * intensity * (1.0 - uv.y * 0.4);
	
	// 번개 칠 때 빗방울이 빛을 산란하여 백색으로 번쩍임
	float flash_boost = 1.0 + lightning_flash * 3.5;
	vec3 final_color = mix(rain_color.rgb, vec3(1.0, 1.0, 1.0), min(lightning_flash * 0.85, 1.0)) * flash_boost;
	
	float final_alpha = (streaks * 0.75 + mist) * intensity;
	// 번개 시 빗줄기 가시성 대폭 증가
	final_alpha *= (1.0 + lightning_flash * 0.8);
	
	ALBEDO = final_color;
	ALPHA = clamp(final_alpha, 0.0, 0.95);
}
