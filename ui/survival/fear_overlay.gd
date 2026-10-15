class_name FearOverlay
extends Control
## v0.28.4 공포 연출 (저레벨, 그림 · 소리만): 헌터 레벨이 낮을 때 크리처가 다가오면 —
## 세상의 채도가 빠지고 어두워지며 (WorldEnvironment 보정), 화면 가장자리가 검게 조여 오고 심장 박동에 맞춰 맥동한다.
## 심장 소리가 가까울수록 빨라지고 커지며 (세면 짧은 진동), 크리처가 처음 다가오면 섬뜩한 소리 · 화면이 움찔.
## 세기 = 레벨 몫 (Lv.1 가장 셈 → fear_max_level 에서 약함 → 그 위 없음) × 가까움 (fear_range m 밖 0 → 2.5m 안 1).
## 터치는 통과. 판정과는 상관없다.

var player: Node3D = null
## 지금 세기 (0~1, 부드럽게 따라간다).
var level: float = 0.0
var _edge: TextureRect = null
var _env: Environment = null
var _env_retry_at: int = 0
var _beat_in: float = 0.0
var _beat_pulse: float = 0.0
var _sting_ready_at: float = 0.0
var _armed: bool = true
var _time: float = 0.0
var _adjusted: bool = false


func _ready() -> void:
	name = "FearOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge = TextureRect.new()
	_edge.name = "Edge"
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	var dark: Color = Color(0.03, 0.0, 0.0)
	var g: Gradient = Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(dark, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(dark, 1.0))
	g.add_point(0.42, Color(dark, 0.0))
	g.add_point(0.72, Color(dark, 0.62))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_edge.texture = tex
	_edge.modulate.a = 0.0
	add_child(_edge)
	resized.connect(func() -> void: _edge.pivot_offset = size * 0.5)


## 레벨 몫: Lv.1 = 1, fear_max_level = 0.2 쯤, 그 위 0.
static func level_factor(lv: int, max_level: int) -> float:
	if lv > max_level or max_level <= 0:
		return 0.0
	return clampf(float(max_level + 1 - lv) / float(max_level), 0.0, 1.0)


## 가까움: range 밖 0 → 2.5m 안 1.
static func closeness(d: float, range_m: float) -> float:
	return clampf((range_m - d) / maxf(range_m - 2.5, 0.1), 0.0, 1.0)


func target_level() -> float:
	if player == null or Net.state != Net.State.ONLINE or Net.creatures.is_empty():
		return 0.0
	var rules: SurvivalRules = GameData.survival
	var lf: float = level_factor(int(Net.hunter.get("lv", 1)), rules.fear_max_level)
	if lf <= 0.0:
		return 0.0
	var p: Vector3 = player.global_position
	var best: float = INF
	for id: String in Net.creatures:
		var c: Dictionary = Net.creatures[id]
		best = minf(best, Vector2(float(c.get("x", 0.0)) - p.x, float(c.get("z", 0.0)) - p.z).length())
	var k: float = closeness(best, rules.fear_range)
	return lf * k * k * (3.0 - 2.0 * k)


func _process(delta: float) -> void:
	_time += delta
	var goal: float = target_level()
	level = move_toward(level, goal, delta * (1.4 if goal > level else 0.5))
	# 처음 다가오면 섬뜩한 소리 · 화면 움찔.
	if level > 0.22 and _armed and _time >= _sting_ready_at:
		_armed = false
		_sting_ready_at = _time + GameData.survival.fear_sting_cooldown
		Audio.play_sfx("fear_sting", lerpf(-10.0, -2.0, level), 1.0, 0.04)
		_beat_pulse = 1.0
		var cam: FollowCamera = get_viewport().get_camera_3d().get_parent() as FollowCamera if get_viewport().get_camera_3d() != null else null
		if cam != null:
			cam.shake(0.08, 0.35)
	if level < 0.05:
		_armed = true
	# 심장: 가까울수록 빨라지고 커진다.
	if level > 0.04:
		_beat_in -= delta
		if _beat_in <= 0.0:
			_beat_in = 60.0 / lerpf(68.0, 150.0, level)
			_beat_pulse = 1.0
			Audio.play_sfx("heartbeat", lerpf(-20.0, -1.0, level), 1.0, 0.0)
			if level > 0.55:
				Prefs.vibrate(25, 0.25 + level * 0.3)
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 4.0)
	# 가장자리: 세질수록 안쪽으로 조여 오고, 박동마다 한 번 더.
	var squeeze: float = level + _beat_pulse * 0.12 * level
	_edge.modulate.a = clampf(level * 0.9, 0.0, 0.72)
	_edge.scale = Vector2.ONE * lerpf(1.4, 1.05, clampf(squeeze, 0.0, 1.0))
	_apply_world(level + _beat_pulse * 0.06 * level)


## 세상 색: 채도를 빼고, 대비를 올리고, 조금 어둡게.
func _apply_world(f: float) -> void:
	if _env == null:
		# 무서울 때만, 1초에 한 번만 찾는다 (매 프레임 나무 전체를 뒤지지 않게).
		if f <= 0.005 or Time.get_ticks_msec() < _env_retry_at:
			return
		_env_retry_at = Time.get_ticks_msec() + 1000
		var we: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we == null or we.environment == null:
			return
		_env = we.environment
	if f <= 0.005:
		if _adjusted:
			_adjusted = false
			_env.adjustment_saturation = 1.0
			_env.adjustment_contrast = 1.0
			_env.adjustment_brightness = 1.0
			_env.adjustment_enabled = false
		return
	_adjusted = true
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.0 - 0.82 * clampf(f, 0.0, 1.0)
	_env.adjustment_contrast = 1.0 + 0.1 * clampf(f, 0.0, 1.0)
	_env.adjustment_brightness = 1.0 - 0.05 * clampf(f, 0.0, 1.0)


## 무서운 중에 사라져도 세상 색을 되돌린다 (Environment 는 장면끼리 나눠 쓸 수 있다).
func _exit_tree() -> void:
	if _env != null and _adjusted:
		_adjusted = false
		_env.adjustment_saturation = 1.0
		_env.adjustment_contrast = 1.0
		_env.adjustment_brightness = 1.0
		_env.adjustment_enabled = false
