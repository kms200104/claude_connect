// 월드 커브: 기준점(world_curve_origin)에서 멀어질수록 월드 Y로 거리²에 비례해 가라앉아
// 지평선이 둥글게 휘어 보인다. 전역 셰이더 파라미터라 모든 머티리얼이 한 번에 켜고 끈다.
// 강도 0이면 효과 없음. 그림자 패스에서도 같은 값을 쓰므로 그림자도 같이 휜다.
global uniform float world_curve_strength;
global uniform vec3 world_curve_origin;

// 로컬 정점에 더할 변위 (월드 -Y 방향 이동을 로컬 공간으로 환산).
vec3 world_curve_local_offset(mat4 model_matrix, vec3 local_vertex) {
	vec3 world_pos = (model_matrix * vec4(local_vertex, 1.0)).xyz;
	vec2 d = world_pos.xz - world_curve_origin.xz;
	float drop_amount = world_curve_strength * dot(d, d);
	return inverse(mat3(model_matrix)) * vec3(0.0, -drop_amount, 0.0);
}
