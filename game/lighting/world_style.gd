class_name WorldStyle
extends Node
## 월드의 룩(툰 셰이딩 · 따뜻한 조명 · 월드 커브 · 그림자)을 한 곳에서 켜고 끈다.
## 실행 중 인스펙터(원격 트리)에서 값을 바꾸면 즉시 반영된다.
## 월드 커브/툰 부드러움은 전역 셰이더 파라미터로 모든 머티리얼에 공유된다.
## SkyController 가 있으면 해·주변광 색과 세기, 그림자 on/off 를 시각·날씨에 맞춰 매 프레임 다시 정한다
## (따뜻한 조명 값은 한낮의 기준색, shadows_enabled 는 "그림자를 써도 되는지" 설정으로 쓰인다).

@export_group("References")
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## 월드 커브의 기준점(보통 플레이어). 이 위치 주변이 평평하다.
@export var focus: Node3D
@export var toon_shader: Shader
@export var lit_shader: Shader
## 툰/일반 셰이더를 맞바꿀 머티리얼들 (같은 파라미터 이름을 공유해야 한다).
@export var materials: Array[ShaderMaterial] = []

@export_group("Toon")
@export var toon_enabled: bool = true:
	set(value):
		toon_enabled = value
		_apply_toon()
## 툰 명암 경계의 부드러움. 0 = 칼같이 딱 떨어짐, 1 = 아주 부드러움.
@export_range(0.0, 1.0, 0.01) var toon_softness: float = 0.35:
	set(value):
		toon_softness = value
		_apply_toon()

@export_group("World Curve")
@export var curve_enabled: bool = true:
	set(value):
		curve_enabled = value
		_apply_curve()
## 기준점에서 d미터 떨어진 곳이 strength × d² 미터 가라앉는다.
@export_range(0.0, 0.02, 0.0001) var curve_strength: float = 0.004:
	set(value):
		curve_strength = value
		_apply_curve()

@export_group("Warm Lighting")
@export var warm_light_enabled: bool = true:
	set(value):
		warm_light_enabled = value
		_apply_lighting()
@export var warm_sun_color: Color = Color(1.0, 0.86, 0.66, 1.0):
	set(value):
		warm_sun_color = value
		_apply_lighting()
@export_range(0.0, 4.0, 0.05) var warm_sun_energy: float = 0.8:
	set(value):
		warm_sun_energy = value
		_apply_lighting()
@export var warm_ambient_color: Color = Color(0.98, 0.84, 0.72, 1.0):
	set(value):
		warm_ambient_color = value
		_apply_lighting()
@export_range(0.0, 4.0, 0.05) var warm_ambient_energy: float = 0.4:
	set(value):
		warm_ambient_energy = value
		_apply_lighting()
@export var neutral_sun_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 4.0, 0.05) var neutral_sun_energy: float = 0.75
@export var neutral_ambient_color: Color = Color(0.75, 0.78, 0.82, 1.0)
@export_range(0.0, 4.0, 0.05) var neutral_ambient_energy: float = 0.35

@export_group("Shadows")
## 방향광 그림자. 모바일 규칙상 캐스케이드는 항상 1단계(ORTHOGONAL)로 고정한다.
@export var shadows_enabled: bool = true:
	set(value):
		shadows_enabled = value
		_apply_shadows()
@export_range(5.0, 100.0, 0.5, "suffix:m") var shadow_distance: float = 28.0:
	set(value):
		shadow_distance = value
		_apply_shadows()


func _ready() -> void:
	# 그림자 거리는 화질 설정을 따른다 (절약 22m · 고화질 32m).
	shadow_distance = float(Quality.value("shadow_distance", shadow_distance))
	Quality.changed.connect(func() -> void: shadow_distance = float(Quality.value("shadow_distance", shadow_distance)))
	_apply_all()


func _process(_delta: float) -> void:
	if focus != null:
		RenderingServer.global_shader_parameter_set("world_curve_origin", focus.global_position)


func _apply_all() -> void:
	_apply_toon()
	_apply_curve()
	_apply_lighting()
	_apply_shadows()


func _apply_toon() -> void:
	if not is_node_ready():
		return
	RenderingServer.global_shader_parameter_set("toon_softness", toon_softness)
	var shader: Shader = toon_shader if toon_enabled else lit_shader
	if shader == null:
		return
	for material: ShaderMaterial in materials:
		if material != null and material.shader != shader:
			material.shader = shader


func _apply_curve() -> void:
	if not is_node_ready():
		return
	RenderingServer.global_shader_parameter_set("world_curve_strength", curve_strength if curve_enabled else 0.0)


func _apply_lighting() -> void:
	if not is_node_ready():
		return
	if sun != null:
		sun.light_color = warm_sun_color if warm_light_enabled else neutral_sun_color
		sun.light_energy = warm_sun_energy if warm_light_enabled else neutral_sun_energy
	if world_environment != null and world_environment.environment != null:
		var env: Environment = world_environment.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = warm_ambient_color if warm_light_enabled else neutral_ambient_color
		env.ambient_light_energy = warm_ambient_energy if warm_light_enabled else neutral_ambient_energy


func _apply_shadows() -> void:
	if not is_node_ready() or sun == null:
		return
	sun.shadow_enabled = shadows_enabled
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = shadow_distance
