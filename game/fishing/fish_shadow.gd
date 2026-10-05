class_name FishShadow
extends Node3D
## 물 밑에서 찌로 다가오는 물고기 그림자 (v0.11). 크기는 서버가 알려 준 shadow 값(희귀하고 클수록 크다).
##   appear → 멀리서 천천히 맴돌며 다가온다 → nibble(가짜 입질): 쏙 다가와 찌를 건드리고 물러난다
##   → bite(진짜 입질): 확 달려들어 찌를 물고 들어간다 → struggle(끌어올리기): 찌 밑에서 버둥거린다 → leave / hide_shadow
## 어떤 물고기인지는 모른다. 그림자 모양은 모두 같고 크기만 다르다.

## 그림자가 닿았다 (가짜 입질·진짜 입질 모두). 찌 연출·진동을 여기에 맞춘다.
signal touched(strong: bool)

@export_range(0.5, 6.0, 0.1, "suffix:m") var start_distance: float = 3.4
@export_range(0.3, 3.0, 0.05, "suffix:m") var circle_distance: float = 1.05
## 몇 초에 걸쳐 맴도는 거리까지 다가오는지.
@export_range(0.5, 20.0, 0.5, "suffix:s") var approach_time: float = 5.0
@export_range(0.05, 1.0, 0.05) var opacity: float = 0.55
@export var color: Color = Color(0.03, 0.08, 0.12)

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
var _material: StandardMaterial3D = null
var _prev: Vector3 = Vector3.ZERO
static var _fish_mesh: ArrayMesh = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(color, 0.0)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 2
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _shape()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## 찌(center) 주변 멀리서 나타나 천천히 맴돌며 다가온다. size: 0.6~1.7.
func appear(center: Vector3, size: float) -> void:
	_center = center
	_size = clampf(size, 0.5, 1.8)
	_mesh.scale = Vector3.ONE * _size
	_angle = randf() * TAU
	_swim_dir = 1.0 if randf() < 0.5 else -1.0
	_distance = start_distance
	_time = 0.0
	_set_mode(Mode.APPROACH)
	_material.albedo_color.a = 0.0
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
	_set_mode(Mode.STRUGGLE)


## 놓쳤을 때: 휙 돌아 멀리 달아나며 사라진다.
func leave() -> void:
	if mode == Mode.HIDDEN:
		return
	_set_mode(Mode.LEAVE)


func hide_shadow() -> void:
	_set_mode(Mode.HIDDEN)
	visible = false


func _set_mode(m: Mode) -> void:
	mode = m
	_mode_time = 0.0


func _process(delta: float) -> void:
	if mode == Mode.HIDDEN:
		return
	_time += delta
	_mode_time += delta
	var alpha: float = opacity * (0.75 + 0.25 * _size / 1.35)
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


func _fade_to(a: float, delta: float) -> void:
	_material.albedo_color.a = lerpf(_material.albedo_color.a, a, 1.0 - exp(-delta * 6.0))


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
	_mesh.rotation.y = sin(_time * (6.0 + speed * 4.0)) * clampf(0.08 + speed * 0.05, 0.08, 0.3)


## 위에서 본 물고기 모양 (몸통 타원 + 꼬리 + 지느러미). 머리가 -Z.
static func _shape() -> ArrayMesh:
	if _fish_mesh != null:
		return _fish_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var ring: PackedVector3Array = PackedVector3Array()
	var n: int = 20
	for i: int in n:
		var a: float = TAU * float(i) / n
		var z: float = cos(a) * 0.36
		# 머리 쪽(-Z)이 조금 더 통통하다.
		var w: float = sin(a) * (0.13 if z < 0.0 else 0.1)
		ring.append(Vector3(w, 0.0, z))
	for i: int in n:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % n])
	# 꼬리 (두 갈래)
	for side: float in [-1.0, 1.0]:
		st.add_vertex(Vector3(0.0, 0.0, 0.3))
		st.add_vertex(Vector3(0.17 * side, 0.0, 0.58))
		st.add_vertex(Vector3(0.03 * side, 0.0, 0.5))
	# 가슴지느러미
	for side: float in [-1.0, 1.0]:
		st.add_vertex(Vector3(0.1 * side, 0.0, -0.08))
		st.add_vertex(Vector3(0.21 * side, 0.0, 0.02))
		st.add_vertex(Vector3(0.09 * side, 0.0, 0.06))
	_fish_mesh = st.commit()
	return _fish_mesh
