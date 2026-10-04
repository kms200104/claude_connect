extends Node
## 화질 설정 (data/quality/presets.json): 절약(갤럭시 S24 기준) · 고화질(갤럭시 Z 폴드7 기준).
## 처음엔 기기 모델명으로 추천 설정을 고르고("자동"), 플레이어가 바꾸면 user://settings.cfg 에 기억한다.
## 바꾸는 것: 3D 해상도(화면 픽셀이 pixel_budget 을 넘으면 그만큼 낮춘다 — 폴드7 을 펼치거나 접으면 다시 계산),
## 계단 현상 줄이기(MSAA), 그림자 크기·부드러움·거리, 풀·들꽃·야자수 수, 캐릭터 머리·얼굴 촘촘함, 리소스팩(바닥 텍스처 해상도).

signal changed

const PRESETS_PATH: String = "res://data/quality/presets.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const PACK_DIR: String = "res://assets/packs"
const GROUND_MATERIAL: String = "res://assets/materials/ground.tres"
const AUTO: String = "auto"

## 지금 쓰는 설정 id (low / high) 와 그 값.
var preset_id: String = "low"
var preset: Dictionary = {}
## 플레이어가 고른 것 (auto = 기기 추천).
var choice: String = AUTO
## 기기 추천 설정과 알아낸 기기 이름 (모르는 기기면 빈 문자열).
var recommended: String = "low"
var device_name: String = ""

var _presets: Dictionary = {}
var _order: PackedStringArray = []


func _ready() -> void:
	var file: FileAccess = FileAccess.open(PRESETS_PATH, FileAccess.READ)
	var data: Dictionary = {}
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			data = parsed
	_presets = data.get("presets", {})
	_order = PackedStringArray(_presets.keys())
	_detect(data)
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		choice = str(cfg.get_value("graphics", "preset", AUTO))
	# 시험·도구 실행에서 고르기: -- --quality=low|high
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			choice = arg.trim_prefix("--quality=")
	get_tree().root.size_changed.connect(_apply_resolution)
	_apply(false)


## 고를 수 있는 설정 id (절약, 고화질 순).
func preset_ids() -> PackedStringArray:
	return _order


func preset_name(id: String) -> String:
	return str((_presets.get(id, {}) as Dictionary).get("name", id))


func preset_about(id: String) -> String:
	return str((_presets.get(id, {}) as Dictionary).get("about", ""))


## 설정 고르기 (auto = 기기 추천). 기억해 두고 바로 적용한다.
func choose(id: String) -> void:
	if id != AUTO and not _presets.has(id):
		return
	choice = id
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "preset", choice)
	cfg.save(SETTINGS_PATH)
	_apply(true)


## 설정 값 하나 (없으면 fallback).
func value(key: String, fallback: Variant) -> Variant:
	return preset.get(key, fallback)


## 개수 배율 (grass / wild_flowers / palms).
func density(key: String) -> float:
	return clampf(float(preset.get(key, 1.0)), 0.1, 1.0)


## 3D 를 그리는 해상도 배율 (1 = 화면 그대로).
func render_scale() -> float:
	return get_tree().root.scaling_3d_scale


func _detect(data: Dictionary) -> void:
	recommended = str(data.get("default", "low"))
	var model: String = OS.get_model_name()
	for entry: Variant in data.get("devices", []):
		if not entry is Dictionary:
			continue
		var re: RegEx = RegEx.create_from_string(str(entry.get("match", "^$")))
		if re != null and re.search(model) != null:
			recommended = str(entry.get("preset", recommended))
			device_name = str(entry.get("name", model))
			return
	# 목록에 없는 기기: 메모리가 넉넉하면(11GB 이상) 고화질. 컴퓨터(편집기·도구)도 고화질.
	if OS.has_feature("mobile"):
		var memory: Dictionary = OS.get_memory_info()
		if int(memory.get("physical", 0)) >= 11 * 1024 * 1024 * 1024:
			recommended = "high" if _presets.has("high") else recommended
	elif _presets.has("high"):
		recommended = "high"


func _apply(notify: bool) -> void:
	preset_id = recommended if choice == AUTO or not _presets.has(choice) else choice
	preset = _presets.get(preset_id, {})
	var root: Window = get_tree().root
	root.msaa_3d = _msaa(int(preset.get("msaa", 2)))
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if str(preset.get("scaling", "bilinear")) == "fsr" else Viewport.SCALING_3D_MODE_BILINEAR
	_apply_resolution()
	RenderingServer.directional_shadow_atlas_set_size(int(preset.get("shadow_size", 2048)), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if bool(preset.get("shadow_soft", false)) else RenderingServer.SHADOW_QUALITY_HARD)
	var detail: int = int(preset.get("character_detail", 1))
	if CharacterModel.detail != detail:
		CharacterModel.detail = detail
		CharacterModel.clear_cache()
	_apply_pack(str(preset.get("pack", preset_id)))
	if notify:
		# 이미 서 있는 캐릭터들도 새 촘촘함으로 다시 빚는다.
		for rig: Node in get_tree().get_nodes_in_group(&"character_rigs"):
			(rig as CharacterRig).set_look((rig as CharacterRig).look)
		changed.emit()


## 화면 픽셀이 예산을 넘으면 3D 해상도를 낮춘다 (UI 는 그대로 선명).
func _apply_resolution() -> void:
	var root: Window = get_tree().root
	root.scaling_3d_scale = scale_for(root.size, int(preset.get("pixel_budget", 2000000)))


## 화면 크기와 픽셀 예산으로 정한 3D 해상도 배율 (0.05 단위, 0.5~1).
static func scale_for(screen: Vector2i, budget: int) -> float:
	var pixels: float = float(maxi(screen.x, 1) * maxi(screen.y, 1))
	return clampf(snappedf(sqrt(float(budget) / pixels), 0.05), 0.5, 1.0)


## 리소스팩: 바닥 색 지도·잔결 텍스처를 그 팩 해상도로.
func _apply_pack(pack: String) -> void:
	var material: ShaderMaterial = load(GROUND_MATERIAL)
	if material == null:
		return
	for pair: Array in [["map_texture", "ground_map.png"], ["detail_texture", "ground_detail.png"]]:
		var path: String = "%s/%s/%s" % [PACK_DIR, pack, pair[1]]
		if ResourceLoader.exists(path):
			material.set_shader_parameter(pair[0], load(path))


static func _msaa(samples: int) -> Viewport.MSAA:
	match samples:
		2:
			return Viewport.MSAA_2X
		4:
			return Viewport.MSAA_4X
		8:
			return Viewport.MSAA_8X
	return Viewport.MSAA_DISABLED
