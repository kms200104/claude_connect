// 툰 / 일반 라이팅 셰이더가 공유하는 본문. render_mode만 다르다.
#include "res://assets/shaders/include/world_curve.gdshaderinc"

// 툰 경계의 부드러움. diffuse_toon에서는 ROUGHNESS가 경계 블러를 결정한다.
global uniform float toon_softness;
// 비에 젖은 정도(0~1). SkyController가 날씨에 따라 천천히 올리고 내린다. 젖으면 색이 어두워진다.
global uniform float world_wetness;
// 밤 조명 세기(0~1). 가로등·창문처럼 emission 이 있는 머티리얼만 밤에 빛난다.
global uniform float night_light;

// 가림 비추기 (v0.13.5): 카메라와 캐릭터 사이를 가리는 건물·나무는 캐릭터 둘레만 점점이(디더) 비워 캐릭터가 비쳐 보인다.
// xyz = 캐릭터 가슴 높이(월드), w = 세기(0 = 끔). FollowCamera 가 매 프레임 넣는다. 건물·나무 머티리얼(building_clay · building_window)만 이 셰이더를 쓴다.
// 알파 블렌드 없이 discard 만 쓰므로 불투명 그대로 그려지고 그림자는 그대로 남는다.
// discard 가 든 셰이더는 모바일에서 조기 깊이 검사를 잃으므로, SEE_THROUGH 를 정의한 셰이더(toon_world_see)에서만 켠다.
#ifdef SEE_THROUGH
global uniform vec4 see_through_target;
// 화면에서 비우는 원의 반지름 (캐릭터 자리에서의 m).
global uniform float see_through_radius;
#endif

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// 밤에만 켜지는 자체 발광 (가로등 갓, 창문).
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

// 머리카락 결 (v0.11.1): 정점 색 알파가 0.5 인 면(캐릭터 머리카락, CharacterModel._hair_paint)에만
// 머리 둘레를 따라 가는 세로 결을 그린다. 폴리곤을 늘리지 않고 매끈한 껍질이 머리카락처럼 보이게.
const vec3 HAIR_CENTER = vec3(0.0, 0.43, 0.02);
varying vec3 v_local;
varying float v_hair;

void vertex() {
	v_local = VERTEX;
	v_hair = 1.0 - step(0.02, abs(COLOR.a - 0.5));
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
	// 정점 색(메시·MultiMesh 인스턴스 색)은 sRGB 로 칠해 두었다. 조명 계산은 선형 공간이라 여기서 바꾼다 (정점마다 한 번).
	COLOR.rgb = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb));
}

#ifdef SEE_THROUGH
// 4×4 바이어 무늬 (0~1) — 화면 화소마다 비울지 정하는 문턱.
float see_through_dither(vec2 frag) {
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	int i = x + y * 4;
	const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (BAYER[i] + 0.5) / 16.0;
}

// 이 화소가 카메라 → 캐릭터 사이에서 캐릭터를 가리는 자리면, 가운데일수록 많이 비운다 (최대 85% — 건물 윤곽은 남는다).
void see_through_clip(vec3 view_vertex, mat4 inv_view, vec3 cam, vec2 frag) {
	vec3 world = (inv_view * vec4(view_vertex, 1.0)).xyz;
	vec3 to_target = see_through_target.xyz - cam;
	float len = length(to_target);
	vec3 dir = to_target / max(len, 0.001);
	float along = dot(world - cam, dir);
	// 캐릭터보다 0.8m 이상 앞(카메라 쪽)에 있는 것만. 캐릭터 둘레 가구·땅은 건드리지 않는다.
	if (along <= 0.0 || along >= len - 0.8) {
		return;
	}
	// 카메라 꼭짓점의 원뿔: 캐릭터 자리에서 반지름 see_through_radius 인 원이 화면에서 같은 크기로 보이게.
	float cone = see_through_radius * along / len;
	float off = length(world - (cam + dir * along)) / max(cone, 0.001);
	float amount = (1.0 - smoothstep(0.55, 1.0, off)) * 0.85 * see_through_target.w;
	// 캐릭터에 아주 가까운 앞면(0.8~2m)은 서서히 — 캐릭터 바로 앞 낮은 담장이 갑자기 뚫리지 않게.
	amount *= smoothstep(0.8, 2.0, len - along);
	if (amount > see_through_dither(frag)) {
		discard;
	}
}
#endif

void fragment() {
#ifdef SEE_THROUGH
	if (!IN_SHADOW_PASS && see_through_target.w > 0.001) {
		see_through_clip(VERTEX, INV_VIEW_MATRIX, CAMERA_POSITION_WORLD, FRAGCOORD.xy);
	}
#endif
	// 정점 색이 없는 메시는 COLOR가 흰색이라 그대로다. 나무처럼 부위별 색을 정점 색으로 칠한 메시는 머티리얼 하나로 그린다.
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb * COLOR.rgb;
	if (v_hair > 0.5) {
		vec3 d = v_local - HAIR_CENTER;
		float around = atan(d.x, -d.z);
		// 결이 조금씩 휘고 굵기가 다르게. 멀어서 결이 화소보다 촘촘해지면 흐리게 해 반짝이지 않게 한다.
		float phase = around * 41.0 + sin(around * 5.0 + d.y * 9.0) * 2.2;
		float phase2 = around * 67.0 + d.y * 14.0 + sin(around * 3.0) * 4.0;
		float aa = clamp(1.4 - fwidth(phase2) * 0.45, 0.0, 1.0);
		float s1 = sin(phase) * 0.5 + 0.5;
		float s2 = sin(phase2) * 0.5 + 0.5;
		float strand = 0.6 * s1 * s1 * s1 + 0.4 * s2 * s2;
		base *= 1.0 - 0.11 * aa * strand;
	}
	ALBEDO = base * mix(1.0, 0.72, world_wetness);
	ROUGHNESS = toon_softness;
	METALLIC = 0.0;
	EMISSION = emission * emission_energy * night_light;
}
