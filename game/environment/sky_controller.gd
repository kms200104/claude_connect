class_name SkyController
extends Node
## 낮과 밤 · 날씨 연출. 서버의 마을 시계(Net.game_hour)와 날씨(Net.weather)를 받아 매 프레임
## 해/달 방향·색·세기, 주변광, 배경색, 안개, 비, 젖은 땅, 밤 조명, 번개 섬광을 맞춘다.
## WorldStyle 의 따뜻한 조명 값은 낮의 기준색으로 쓰고, 그림자 on/off 설정도 존중한다.
##
## 모바일 비용: 하늘 셰이더 대신 단색 배경(반사 맵 재계산 없음), 비는 카메라 앞 사각형 1장,
## 흐림·비·밤에는 그림자를 꺼서 오히려 가볍게 만든다.

## 지금 밤 조명 세기 (0~1, 셰이더 전역 값 night_light 와 같다). 탈것 전조등처럼 스크립트가 읽는다 (전역 셰이더 값은 실행 중에 읽을 수 없다).
static var night_light: float = 0.0

@export_group("References")
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var world_style: WorldStyle
## 카메라 앞에 붙인 비 판 (rain_curtain.gdshader).
@export var rain: MeshInstance3D
## 밤에 켜는 가로등 불빛 (그림자 없음, 2개 이하 권장).
@export var lamp_lights: Array[OmniLight3D] = []

@export_group("Time")
## 서버에 접속하기 전에 보여 줄 시각.
@export_range(0.0, 24.0, 0.25) var offline_hour: float = 13.0
## 0이 아니면 서버 시각 대신 이 시각을 쓴다 (연출 확인용).
@export_range(0.0, 24.0, 0.25) var debug_hour: float = 0.0

@export_group("Palette")
@export var dawn_sun_color: Color = Color(1.0, 0.62, 0.42)
@export var moon_color: Color = Color(0.55, 0.66, 1.0)
@export_range(0.0, 2.0, 0.05) var moon_energy: float = 0.3
@export var day_sky: Color = Color(0.62, 0.79, 0.93)
@export var dusk_sky: Color = Color(0.96, 0.66, 0.5)
@export var night_sky: Color = Color(0.09, 0.12, 0.24)
@export var storm_sky: Color = Color(0.5, 0.54, 0.6)
@export var night_ambient: Color = Color(0.42, 0.48, 0.78)
## 밤에도 폰 화면에서 보이도록 주변광을 이만큼은 남긴다.
@export_range(0.0, 2.0, 0.05) var night_ambient_energy: float = 0.7

@export_group("Weather")
## 날씨가 바뀔 때 하늘·빛이 따라가는 속도 (클수록 빠름).
@export_range(0.05, 5.0, 0.05) var weather_blend_speed: float = 0.6
## 비가 오면 땅이 젖는 속도와 그친 뒤 마르는 속도 (초당 0~1).
@export_range(0.01, 1.0, 0.01) var wet_speed: float = 0.08
@export_range(0.01, 1.0, 0.01) var dry_speed: float = 0.03

@export_group("Accessibility")
## 번개 섬광을 약하게 (빛 번쩍임에 민감한 사람을 위해).
@export var reduce_flashes: bool = false

## 0 = 밤, 1 = 한낮. 시계로 정해진다.
var daylight: float = 1.0
## 구름 양(0~1), 비 세기(0~1). 날씨를 향해 천천히 따라간다.
var clouds: float = 0.0
var rain_amount: float = 0.0
var wetness: float = 0.0
var flash: float = 0.0
## 실내(상점 안)에 있으면 비·안개·젖은 땅을 보이지 않는다. ShopController 가 켜고 끈다.
var indoor: bool = false

var _flash_tween: Tween = null


func _ready() -> void:
	if world_environment != null and world_environment.environment != null:
		# 시간마다 하늘 셰이더를 바꾸면 반사 맵을 다시 구워야 해서 모바일에서 비싸다. 단색 배경으로 그린다.
		world_environment.environment.background_mode = Environment.BG_COLOR
	Net.lightning_struck.connect(strike)
	_apply(0.0, true)


func _process(delta: float) -> void:
	_apply(delta, false)


func current_hour() -> float:
	if debug_hour > 0.0:
		return debug_hour
	return Net.game_hour() if Net.state == Net.State.ONLINE else offline_hour


## 번개 섬광. 두 번 번쩍인다.
func strike(power: float = 1.0) -> void:
	var peak: float = power * (0.25 if reduce_flashes else 1.0)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "flash", peak, 0.04)
	_flash_tween.tween_property(self, "flash", 0.1, 0.09)
	_flash_tween.tween_property(self, "flash", peak * 0.7, 0.05)
	_flash_tween.tween_property(self, "flash", 0.0, 0.35)


func _weather_targets() -> Vector2:
	match Net.weather if Net.state == Net.State.ONLINE else NetProtocol.WEATHER_CLEAR:
		NetProtocol.WEATHER_CLOUDY:
			return Vector2(0.6, 0.0)
		NetProtocol.WEATHER_RAIN:
			return Vector2(0.85, 0.75)
		NetProtocol.WEATHER_THUNDER:
			return Vector2(1.0, 1.0)
		_:
			return Vector2(0.0, 0.0)


func _apply(delta: float, instant: bool) -> void:
	var hour: float = current_hour()
	daylight = _daylight(hour)
	var target: Vector2 = _weather_targets()
	var k: float = 1.0 if instant else 1.0 - exp(-weather_blend_speed * delta)
	clouds = lerpf(clouds, target.x, k)
	rain_amount = lerpf(rain_amount, target.y, k)
	if instant:
		wetness = target.y
	elif rain_amount > wetness:
		wetness = minf(wetness + wet_speed * delta, rain_amount)
	else:
		wetness = maxf(wetness - dry_speed * delta, rain_amount)

	# 해 질 녘·새벽에 가까울수록 1 (노을빛).
	var golden: float = clampf(1.0 - absf(daylight - 0.5) * 2.0, 0.0, 1.0)
	var day_sun: Color = world_style.warm_sun_color if world_style != null else Color(1.0, 0.86, 0.66)
	var day_energy: float = world_style.warm_sun_energy if world_style != null else 0.8
	var day_ambient: Color = world_style.warm_ambient_color if world_style != null else Color(0.98, 0.84, 0.72)
	var day_ambient_energy: float = world_style.warm_ambient_energy if world_style != null else 0.4

	if sun != null:
		var is_day: bool = daylight > 0.05
		var sun_color: Color = day_sun.lerp(dawn_sun_color, golden * 0.8) if is_day else moon_color
		var energy: float = lerpf(moon_energy, day_energy, daylight) * (1.0 - 0.55 * clouds)
		sun.light_color = sun_color
		sun.light_energy = energy
		sun.rotation = _sun_rotation(hour, is_day)
		var shadows_allowed: bool = world_style == null or world_style.shadows_enabled
		sun.shadow_enabled = shadows_allowed and daylight > 0.5 and clouds < 0.3

	if world_environment != null and world_environment.environment != null:
		var env: Environment = world_environment.environment
		var sky: Color = night_sky.lerp(dusk_sky, golden).lerp(day_sky, clampf(daylight * 2.0 - 1.0, 0.0, 1.0))
		sky = sky.lerp(storm_sky * lerpf(0.35, 1.0, daylight), clouds * 0.8)
		env.background_color = sky.lerp(Color.WHITE, flash * 0.6)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = night_ambient.lerp(day_ambient, daylight)
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, daylight) * (1.0 - 0.2 * clouds) + flash * 1.5
		# 비·밤에는 옅은 안개로 먼 곳을 흐리게 (먼 물체가 덜 보여 그리기도 가볍다).
		var fog: float = maxf(rain_amount * 0.9, (1.0 - daylight) * 0.1)
		env.fog_enabled = fog > 0.02 and not indoor
		env.fog_light_color = sky
		env.fog_density = 0.002 + 0.01 * fog

	var lamps: float = clampf(maxf(1.0 - daylight * 1.4, clouds * rain_amount * 0.5), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("night_light", lamps)
	night_light = lamps
	RenderingServer.global_shader_parameter_set("world_wetness", 0.0 if indoor else wetness)
	for light: OmniLight3D in lamp_lights:
		if light != null:
			light.visible = lamps > 0.05
			light.light_energy = lamps * 1.4

	if rain != null:
		rain.visible = rain_amount > 0.02 and not indoor
		var material: ShaderMaterial = rain.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("intensity", rain_amount)


## 0(밤) ~ 1(낮). 5~7시에 밝아지고 17.5~19.5시에 어두워진다.
static func _daylight(hour: float) -> float:
	var rise: float = smoothstep(5.0, 7.0, hour)
	var set_: float = 1.0 - smoothstep(17.5, 19.5, hour)
	return clampf(minf(rise, set_), 0.0, 1.0)


## 해는 동(6시)에서 서(18시)로, 한낮에 가장 높다. 밤에는 달이 비스듬히 비춘다.
static func _sun_rotation(hour: float, is_day: bool) -> Vector3:
	if not is_day:
		return Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	var t: float = clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	var elevation: float = lerpf(15.0, 62.0, sin(t * PI))
	var azimuth: float = lerpf(-80.0, 80.0, t)
	return Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0)
