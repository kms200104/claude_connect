shader_type spatial;
// 마을 바닥: 색 지도(잔디·길·모래톱 · v0.21 도시 도로, 도시 0.43m/px · 시내 0.2m/px) 위에 세부 잔결을 겹치고,
// 비/뇌우 시에는 사실적인 젖은 반사광(Wet Specular), 절차적 물 웅덩이(Puddles), 빗방울 파문(Ripples), 번개 반사를 추가.
render_mode diffuse_toon, specular_schlick_ggx;

#include "res://assets/shaders/include/world_curve.gdshaderinc"

global uniform float toon_softness;
global uniform float world_wetness;
global uniform float night_light;
global uniform float lightning_flash;

uniform sampler2D map_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// v0.21 강변도시: 시내(±town_extent)는 촘촘한 색 지도를 따로 쓴다 (0 이면 없음). 가장자리 4m 에서 도시 지도와 섞는다.
uniform sampler2D town_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float town_extent = 0.0;
// 색 지도가 덮는 범위 (마을 가운데 ±map_extent 미터). village_layout.json 의 map_extent 와 같아야 한다.
uniform float map_extent = 64.0;
uniform float detail_tile = 3.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;

// 물 웅덩이 및 반사 설정
uniform float puddle_depth : hint_range(0.0, 1.0) = 0.65;
uniform vec4 puddle_water_color : source_color = vec4(0.12, 0.22, 0.32, 1.0);

varying vec3 world_pos;
varying vec3 v_normal;

float hash2_g(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 웅덩이에 떨어지는 빗방울 파문 고리
float ground_rain_ripple(vec2 cell, vec2 p, float t) {
	vec2 center = (cell + 0.3 + 0.4 * vec2(hash2_g(cell), hash2_g(cell + 7.1))) * 1.8;
	float phase = fract(t * 1.1 + hash2_g(cell + 3.3));
	float ring = abs(length(p - center) - phase * 0.6);
	return smoothstep(0.045, 0.0, ring) * (1.0 - phase);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += world_curve_local_offset(MODEL_MATRIX, VERTEX);
}

void fragment() {
	vec4 map = texture(map_texture, world_pos.xz / (2.0 * map_extent) + 0.5);
	if (town_extent > 0.0) {
		vec2 inner = town_extent - abs(world_pos.xz);
		float town = smoothstep(0.0, 4.0, min(inner.x, inner.y));
		if (town > 0.0) {
			map = mix(map, texture(town_texture, world_pos.xz / (2.0 * town_extent) + 0.5), town);
		}
	}
	float fine = texture(detail_texture, world_pos.xz / detail_tile).r - 0.5;
	float broad = texture(detail_texture, world_pos.xz / (detail_tile * 4.3) + vec2(0.37, 0.11)).r - 0.5;
	
	// 잔디(알파 1)는 잔결을 세게, 흙길·모래는 약하게.
	float grain = fine * detail_strength * mix(0.45, 1.0, map.a) + broad * 0.12;
	vec3 base = map.rgb * (1.0 + grain);
	
	// =========================================================================
	// 비/뇌우 날씨: 젖은 땅, 절차적 물 웅덩이 및 빛 반사 효과 (Wetness & Reflection)
	// =========================================================================
	float wet = clamp(world_wetness, 0.0, 1.0);
	
	// 웅덩이 마스크: 지형 잔결(broad)과 노이즈를 결합하여 낮은 지대에 물이 고임 (특히 길과 공터에 잘 생김)
	float puddle_noise = broad + 0.5; // 0 ~ 1 범위
	float road_factor = (1.0 - map.a * 0.6); // 흙길·모래톱에서 웅덩이가 더 쉽게 고임
	float puddle_thresh = 1.0 - wet * (0.45 + road_factor * 0.3);
	float puddle = smoothstep(puddle_thresh, puddle_thresh + 0.08, puddle_noise) * step(0.12, wet);
	
	// 빗방울 파문: 웅덩이 수면 위에서 빗방울이 떨어져 퍼짐
	vec3 normal_mod = NORMAL;
	if (wet > 0.15 && puddle > 0.05) {
		vec2 p_cell = floor(world_pos.xz * 0.55);
		float ripple = 0.0;
		for (int dx = -1; dx <= 1; dx++) {
			for (int dz = -1; dz <= 1; dz++) {
				ripple += ground_rain_ripple(p_cell + vec2(float(dx), float(dz)), world_pos.xz, TIME);
			}
		}
		// 파문으로 인한 노멀 왜곡
		normal_mod.xz += (fract(world_pos.xz * 2.0) - 0.5) * ripple * puddle * 0.25;
		normal_mod = normalize(normal_mod);
	}
	NORMAL = normal_mod;
	
	// 기본 알베도: 젖으면 물기를 머금어 짙어짐 (Wet Darkening)
	vec3 wet_base = base * mix(1.0, 0.65, wet);
	
	// 웅덩이 영역: 맑은 물빛과 깊이감 합성
	vec3 final_albedo = mix(wet_base, puddle_water_color.rgb * 0.7, puddle * 0.6);
	
	// 거울 같은 하늘/주변광 프레넬 반사 (Fresnel Reflection)
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.5);
	
	// 하늘빛 (낮/밤/뇌우에 따른 반사 색상)
	vec3 sky_reflect = mix(vec3(0.55, 0.68, 0.85), vec3(0.12, 0.18, 0.32), night_light);
	sky_reflect = mix(sky_reflect, vec3(0.35, 0.42, 0.52), wet * 0.8); // 비 오는 날 잿빛 하늘 반사
	
	// 번개 섬광 시 젖은 바닥과 웅덩이가 순간적으로 강렬하게 번쩍임
	float flash_reflect = lightning_flash * 2.2;
	sky_reflect += vec3(0.85, 0.95, 1.0) * flash_reflect;
	
	// 물 웅덩이 거울 반사 + 젖은 지면의 은은한 광택(Sheen)
	float reflect_amount = (puddle * 0.75 + wet * (1.0 - puddle) * 0.18) * (0.15 + fresnel * 0.85);
	final_albedo += sky_reflect * reflect_amount * (0.8 + flash_reflect * 0.5);
	
	ALBEDO = final_albedo;
	
	// 러프니스 & 스펙큘러:
	// - 마른 땅: 거칠고 매트함 (ROUGHNESS 높음, SPECULAR 낮음)
	// - 젖은 땅: 매끄러워짐 (ROUGHNESS 감소, SPECULAR 증가)
	// - 물 웅덩이: 극도로 매끄러움 (ROUGHNESS ~0.04, SPECULAR ~0.95)
	float dry_roughness = toon_softness;
	float wet_roughness = mix(dry_roughness, 0.32, wet * 0.65);
	float final_roughness = mix(wet_roughness, 0.04, puddle);
	
	ROUGHNESS = final_roughness;
	SPECULAR = mix(0.1, 0.88, wet * 0.5 + puddle * 0.5);
	METALLIC = puddle * 0.12; // 웅덩이에 미세한 금속성(거울 반사감) 부여
}
