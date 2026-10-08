class_name FishShadow
extends Node3D
## 물 밑에서 찌로 다가오는 물고기 그림자 (v0.11). 크기는 서버가 알려 준 shadow 값(희귀하고 클수록 크다).
##   appear → 멀리서 천천히 맴돌며 다가온다 → nibble(가짜 입질): 쏙 다가와 찌를 건드리고 물러난다
##   → bite(진짜 입질): 확 달려들어 찌를 물고 들어간다 → struggle(끌어올리기): 찌 밑에서 버둥거린다 → leave / hide_shadow
## 어떤 물고기인지는 모른다. 그림자 모양은 모두 같고 크기만 다르다.
## v13 겨눠 던지기: appear_from — 물 밑에 보이던 그 물고기(FishSchool)가 찌 쪽으로 몸을 돌려 곧장 헤엄쳐 와
##   찌 앞에 멈춘다(line). 찌를 바라본 채로 톡·톡 건드렸다 물러나고(dart), 문다(bite). 둘레의 아우라도 그대로 따라온다.

## 그림자가 닿았다 (가짜 입질·진짜 입질 모두). 찌 연출·진동을 여기에 맞춘다.
signal touched(strong: bool)

@export_range(0.5, 6.0, 0.1, "suffix:m") var start_distance: float = 3.4
@export_range(0.3, 3.0, 0.05, "suffix:m") var circle_distance: float = 1.05
## 몇 초에 걸쳐 맴도는 거리까지 다가오는지.
@export_range(0.5, 20.0, 0.5, "suffix:s") var approach_time: float = 5.0
## v0.13.1: 그림자는 불투명 (1.0). 나타나고 사라질 때만 옅어진다.
@export_range(0.05, 1.0, 0.05) var opacity: float = 1.0

enum Mode { HIDDEN, APPROACH, DART, BITE, STRUGGLE, LEAVE }

var mode: Mode = Mode.HIDDEN
var _center: Vector3 = Vector3.ZERO
var _angle: float = 0.0
var _distance: float = 0.0
var _time: float = 0.0
var _mode_time: float = 0.0
var _size: float = 1.0
var _swim_dir: float = 1.0
var _mesh: MeshInstance3D = null
## 지금 불투명도 (나타남·사라짐), 꼬리 물결의 위상·세기 (fish_silhouette 셰이더).
var _alpha: float = 0.0
var _phase: float = 0.0
var _amp: float = 0.04
var _prev: Vector3 = Vector3.ZERO
## v13: 찌를 향해 곧장 다가오는 모드. _dir = 물고기 → 찌 방향 (찌를 바라본다).
var _line: bool = false
var _dir: Vector3 = Vector3.FORWARD
var _hover: float = 0.35
var _aura: Node3D = null
var _line_speed: float = 0.8
## 다가오는 기본 속도 (서버 swimmers.js approachSpeed 와 같다).
const LINE_SPEED: float = 0.8


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = FishSchool.fish_mesh()
	_mesh.material_override = FishSchool.body_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## v13: 보이던 물고기(start, 몸 크기 size_code, 희귀도 rarity)가 찌(center)를 알아채고 곧장 다가온다.
## approach_ms: 서버가 정한 다가오는 시간 (멀리서 알아챈 물고기는 더 빨리 헤엄친다).
func appear_from(center: Vector3, start: Vector3, size_code: String, rarity: String, approach_ms: int = 0, kind: String = "") -> void:
	_line = true
	_center = center
	var d: Vector3 = Vector3(center.x - start.x, 0.0, center.z - start.z)
	_dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	_size = float(FishSchool.SIZE_SCALE.get(size_code, 1.0))
	_mesh.scale = Vector3.ONE * _size
	_set_kind(kind)
	_hover = 0.28 + 0.12 * _size
	_distance = maxf(d.length(), _hover)
	_line_speed = LINE_SPEED
	if approach_ms > 0:
		_line_speed = maxf(LINE_SPEED, (_distance - _hover) / (approach_ms / 1000.0))
	_time = 0.0
	_set_aura(rarity)
	_set_mode(Mode.APPROACH)
	_alpha = opacity
	visible = true
	global_position = Vector3(start.x, center.y, start.z)
	_prev = global_position


## 겨눈 찌에 아직 아무도 안 왔을 때: 그림자 없이 기다린다 (fish_found 가 오면 appear_from).
func is_line() -> bool:
	return _line and mode != Mode.HIDDEN


## v0.16 상어(shark · hammer)면 상어 모양 그림자 + 물 위로 솟은 등지느러미, 아니면 보통 물고기 그림자.
func _set_kind(kind: String) -> void:
	_mesh.mesh = FishSchool.shark_mesh(kind == "hammer") if not kind.is_empty() else FishSchool.fish_mesh()
	var old: Node = get_node_or_null(^"Fin")
	if old != null:
		old.name = "FinOld"
		old.queue_free()
	if not kind.is_empty():
		add_child(FishSchool.make_fin(_size))


func _set_aura(rarity: String) -> void:
	if _aura != null:
		_aura.queue_free()
		_aura = null
	_aura = FishSchool.make_aura(rarity, _size)
	if _aura != null:
		add_child(_aura)


## 찌(center) 주변 멀리서 나타나 천천히 맴돌며 다가온다. size: 0.6~1.7.
func appear(center: Vector3, size: float) -> void:
	_line = false
	_set_aura("")
	_set_kind("")
	_center = center
	_size = clampf(size, 0.5, 1.8)
	_mesh.scale = Vector3.ONE * _size
	_angle = randf() * TAU
	_swim_dir = 1.0 if randf() < 0.5 else -1.0
	_distance = start_distance
	_time = 0.0
	_set_mode(Mode.APPROACH)
	_alpha = 0.0
	visible = true
	_place(0.0)
	_prev = global_position


## 가짜 입질: 쏙 다가와 찌를 툭 건드리고 다시 물러난다. 닿는 순간 touched(false).
func nibble() -> void:
	if mode == Mode.HIDDEN:
		return
	_set_mode(Mode.DART)


## 진짜 입질: 확 달려들어 찌를 물고 아래로 들어간다. 닿는 순간 touched(true).
func bite() -> void:
	if mode == Mode.HIDDEN:
		return
	_set_mode(Mode.BITE)


## 끌어올리는 동안 찌 밑에서 좌우로 버둥거린다.
func struggle() -> void:
	if mode == Mode.HIDDEN:
		return
	_to_circle()
	_set_mode(Mode.STRUGGLE)


## 놓쳤을 때: 휙 돌아 멀리 달아나며 사라진다.
func leave() -> void:
	if mode == Mode.HIDDEN:
		return
	_to_circle()
	_set_mode(Mode.LEAVE)


## 곧장 다가오기(line)에서 찌 둘레 맴돌기 좌표로 (버둥거리기 · 달아나기는 맴돌기 식으로 그린다).
func _to_circle() -> void:
	if not _line:
		return
	_line = false
	_angle = atan2(-_dir.z, -_dir.x)


func hide_shadow() -> void:
	_set_mode(Mode.HIDDEN)
	visible = false
	_line = false


func _set_mode(m: Mode) -> void:
	mode = m
	_mode_time = 0.0


func _process(delta: float) -> void:
	if mode == Mode.HIDDEN:
		return
	_time += delta
	_mode_time += delta
	var alpha: float = opacity
	if _line:
		_process_line(delta, alpha)
		return
	match mode:
		Mode.APPROACH:
			# 멀리서 원을 그리며 천천히 가까워진다 (처음엔 빨리, 가까워질수록 느리게).
			var k: float = 1.0 - exp(-_time / maxf(approach_time * 0.45, 0.1))
			_distance = lerpf(start_distance, circle_distance, k) + sin(_time * 1.3) * 0.12
			_angle += delta * _swim_dir * (0.35 + 0.25 / maxf(_distance, 0.3))
			_fade_to(alpha * clampf(_time / 1.2, 0.0, 1.0), delta)
		Mode.DART:
			# 0.18초 만에 찌에 닿고 → 0.5초 동안 물러난다.
			if _mode_time < 0.18:
				_distance = lerpf(_distance, 0.12 * _size, 1.0 - exp(-delta * 22.0))
			else:
				if _mode_time - delta < 0.18:
					touched.emit(false)
				_distance = lerpf(_distance, circle_distance * 0.9, 1.0 - exp(-delta * 5.0))
				_angle += delta * _swim_dir * 0.6
				if _mode_time > 0.7:
					_set_mode(Mode.APPROACH)
					_time = approach_time
			_fade_to(alpha, delta)
		Mode.BITE:
			_distance = lerpf(_distance, 0.02, 1.0 - exp(-delta * 26.0))
			if _mode_time >= 0.12 and _mode_time - delta < 0.12:
				touched.emit(true)
			# 물고 들어가며 그림자가 짙어졌다가 조금 흐려진다 (깊이 들어감).
			_fade_to(alpha * (1.25 if _mode_time < 0.3 else 0.8), delta)
		Mode.STRUGGLE:
			_distance = 0.25 + 0.15 * absf(sin(_time * 7.0))
			_angle += delta * _swim_dir * (5.0 + 3.0 * sin(_time * 3.1))
			if randf() < delta * 1.5:
				_swim_dir = -_swim_dir
			_fade_to(alpha, delta)
		Mode.LEAVE:
			_distance += delta * 5.0
			_fade_to(0.0, delta * 1.6)
			if _mode_time > 0.9:
				hide_shadow()
				return
	_place(delta)


## 곧장 다가오기: 찌를 바라본 채로 다가와 멈추고, 톡(앞으로 쏙 → 뒤로 살짝), 문다(확 달려든다).
func _process_line(delta: float, alpha: float) -> void:
	var touch: float = 0.06 * _size
	match mode:
		Mode.APPROACH:
			_distance = move_toward(_distance, _hover, _line_speed * delta)
			_fade_to(alpha, delta)
		Mode.DART:
			if _mode_time < 0.16:
				_distance = lerpf(_distance, touch, 1.0 - exp(-delta * 24.0))
			else:
				if _mode_time - delta < 0.16:
					touched.emit(false)
				_distance = lerpf(_distance, _hover, 1.0 - exp(-delta * 7.0))
				if _mode_time > 0.6:
					_set_mode(Mode.APPROACH)
			_fade_to(alpha, delta)
		Mode.BITE:
			_distance = lerpf(_distance, 0.0, 1.0 - exp(-delta * 26.0))
			if _mode_time >= 0.12 and _mode_time - delta < 0.12:
				touched.emit(true)
			_fade_to(alpha * (1.25 if _mode_time < 0.3 else 0.8), delta)
		_:
			pass
	# 다가오는 동안 몸을 살랑 (옆으로 조금), 찌를 바라본다.
	var side: Vector3 = Vector3(-_dir.z, 0.0, _dir.x)
	var wiggle: float = sin(_time * 3.0) * 0.04 if mode == Mode.APPROACH and _distance > _hover + 0.05 else 0.0
	global_position = _center - _dir * _distance + side * wiggle
	rotation.y = lerp_angle(rotation.y, atan2(-_dir.x, -_dir.z), 1.0 - exp(-delta * 8.0))
	var speed: float = (global_position - _prev).length() / maxf(delta, 0.001)
	_prev = global_position
	_beat(delta, speed)
	if _aura != null:
		_aura.scale = Vector3.ONE * (1.0 + sin(_time * 3.0) * 0.1)


func _fade_to(a: float, delta: float) -> void:
	_alpha = lerpf(_alpha, a, 1.0 - exp(-delta * 6.0))


## 꼬리 물결: 빨리 움직일수록 세게 · 빠르게 친다 (움직임은 꼬리 치기와 함께만 보인다). 멈추면 살랑.
func _beat(delta: float, speed: float) -> void:
	var effort: float = clampf(speed / 1.2, 0.0, 1.0)
	_amp = lerpf(_amp, 0.035 + 0.13 * effort, 1.0 - exp(-6.0 * delta))
	_phase += delta * (4.0 + 12.0 * effort) / sqrt(maxf(_size, 0.3))
	_mesh.set_instance_shader_parameter("phase", _phase)
	_mesh.set_instance_shader_parameter("amp", _amp)
	_mesh.set_instance_shader_parameter("alpha", clampf(_alpha, 0.0, 1.0))
	FishSchool.update_fin(self, clampf(_alpha, 0.0, 1.0), _phase, _amp, speed, _time)


func _place(delta: float) -> void:
	var pos: Vector3 = _center + Vector3(cos(_angle), 0.0, sin(_angle)) * _distance
	global_position = pos
	var vel: Vector3 = pos - _prev
	_prev = pos
	# 헤엄치는 쪽을 바라보고, 꼬리를 흔든다 (빨리 움직일수록 크게).
	if delta > 0.0 and vel.length() > 0.0005:
		var target_yaw: float = atan2(-vel.x, -vel.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-delta * 10.0))
	var speed: float = vel.length() / maxf(delta, 0.001)
	_beat(delta, speed)


## 위에서 본 물고기 모양 (몸통 타원 + 꼬리 + 지느러미). 머리가 -Z.
static func _shape() -> ArrayMesh:
	return FishSchool.fish_mesh()
