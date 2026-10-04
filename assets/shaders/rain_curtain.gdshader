shader_type spatial;
// 카메라 앞에 붙인 반투명 판 하나로 빗줄기를 그린다 (입자 대신 사각형 1장 = 드로우콜 1, 오버드로우 1겹).
// 텍스처 없이 열마다 다른 속도·위상으로 짧은 줄을 흘려 보낸다.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

// 0 = 안 보임, 1 = 큰비. SkyController가 날씨에 맞춰 바꾼다.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rain_color : source_color = vec4(0.82, 0.88, 0.98, 1.0);
// 가로 방향 빗줄기 열 수.
uniform float columns = 64.0;
uniform float fall_speed = 2.2;
// 바람에 기울어진 정도 (UV x 이동량).
uniform float slant = 0.08;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	uv.x += uv.y * slant;
	float column = floor(uv.x * columns);
	float r = hash(column);
	// 열마다 30%는 비워 두어 균일한 격자처럼 보이지 않게 한다.
	float present = step(0.3, r);
	float y = fract(uv.y * (1.5 + r) - TIME * fall_speed * (0.7 + r * 0.6) + r * 7.0);
	float streak = smoothstep(0.0, 0.03, y) * (1.0 - smoothstep(0.03, 0.18, y));
	float across = abs(fract(uv.x * columns) - 0.5);
	float line = 1.0 - smoothstep(0.04, 0.12, across);
	ALBEDO = rain_color.rgb;
	ALPHA = streak * line * present * intensity * 0.6;
}
