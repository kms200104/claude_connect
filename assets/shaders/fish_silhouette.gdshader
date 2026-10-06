// 물 밑 물고기 그림자 (v0.13). 한 장짜리 납작한 물고기를 정점 셰이더로 헤엄치게 한다:
// 머리(-Z)는 거의 그대로, 꼬리 쪽으로 갈수록 크게 좌우로 휘는 물결(등뼈 마디가 차례로 와리가리) — 잉어·붕어 같은 몸통 헤엄.
// 물결 위상(phase)과 세기(amp)는 물고기마다 스크립트가 instance uniform 으로 준다. 헤엄을 멈추면 amp 가 작아져 살랑만.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec3 shadow_color : source_color = vec3(0.03, 0.08, 0.12);
instance uniform float phase = 0.0;
instance uniform float amp = 0.04;
instance uniform float alpha = 1.0;

// 머리 끝 · 꼬리 끝 (FishSchool.fish_mesh 와 같은 값).
const float HEAD_Z = -0.36;
const float TAIL_Z = 0.58;

void vertex() {
	float u = clamp((VERTEX.z - (HEAD_Z + 0.12)) / (TAIL_Z - HEAD_Z - 0.12), 0.0, 1.0);
	// 꼬리 쪽으로 커지는 진폭 (머리는 반대로 아주 살짝 — 몸 전체가 S 자로).
	float swing = sin(phase - VERTEX.z * 6.5) * amp * (u * u * 1.6 + 0.06);
	float head = (1.0 - u) * (1.0 - u) * sin(phase + 2.2) * amp * 0.25;
	VERTEX.x += swing + head;
}

void fragment() {
	ALBEDO = shadow_color;
	ALPHA = alpha;
}
