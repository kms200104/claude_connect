class_name Kickboard
extends Node3D
## 접이식 킥보드 모형 (v0.16). 캐릭터 리그(Body)에 붙고, 좌표는 땅 기준 (y 0 = 바닥, 앞 = -Z).
## 움직이는 부분: 손잡이 기둥이 앞쪽 경첩에서 뒤로 접히고(fold), 손잡이 양쪽이 아래로 접히며, 앞바퀴 · 기둥은 조향(steer)으로 돌고,
## 두 바퀴는 달린 거리만큼 굴러간다(roll). 모두 정점 색 점토 머티리얼 하나 (드로우콜 = 부품 수 7).

## 바퀴 반지름 · 앞뒤 바퀴 자리 (m).
const WHEEL_R: float = 0.055
const FRONT_Z: float = -0.27
const REAR_Z: float = 0.27
## 경첩 높이 (앞바퀴 축 위) · 손잡이 높이 (바닥에서).
const HINGE_Y: float = 0.115
const BAR_Y: float = 0.74
## 접었을 때 기둥 각도 (뒤로 눕는다, rad) · 손잡이가 아래로 접히는 각도.
const FOLD_ANGLE: float = 1.43
const GRIP_FOLD: float = PI * 0.5
## 꺼내고 넣을 때 킥보드가 놓이는 자리 (캐릭터 앞).
const AHEAD: float = -0.55

const DECK_COLOR: Color = Color("#4FA3E0")
const TAPE_COLOR: Color = Color("#2B3038")
const METAL: Color = Color("#C9CFD8")
const ACCENT: Color = Color("#E9822E")
const TYRE: Color = Color("#3A3F47")
const HUB: Color = Color("#F4F4F2")

## 0 = 펼침, 1 = 접힘.
var fold: float = 0.0:
	set(value):
		fold = clampf(value, 0.0, 1.0)
		_apply_fold()
## 조향 각도 (rad, 양수 = 왼쪽으로 꺾음).
var steer: float = 0.0:
	set(value):
		steer = value
		if _steer != null:
			_steer.rotation.y = steer

var _steer: Node3D = null
var _hinge: Node3D = null
var _grip_l: Node3D = null
var _grip_r: Node3D = null
var _wheels: Array[Node3D] = []

static var _meshes: Dictionary[String, ArrayMesh] = {}


## material: 캐릭터와 같은 점토 머티리얼 (정점 색).
func build(material: Material) -> void:
	name = "Kickboard"
	_add_mesh(self, "deck", Vector3.ZERO, material)
	var rear: Node3D = _pivot(self, "RearWheel", Vector3(0.0, WHEEL_R, REAR_Z))
	_add_mesh(rear, "wheel", Vector3.ZERO, material)
	_wheels.append(rear)
	_steer = _pivot(self, "Steer", Vector3(0.0, 0.0, FRONT_Z))
	_add_mesh(_steer, "fork", Vector3.ZERO, material)
	var front: Node3D = _pivot(_steer, "FrontWheel", Vector3(0.0, WHEEL_R, 0.0))
	_add_mesh(front, "wheel", Vector3.ZERO, material)
	_wheels.append(front)
	_hinge = _pivot(_steer, "Hinge", Vector3(0.0, HINGE_Y, 0.0))
	_add_mesh(_hinge, "stem", Vector3.ZERO, material)
	var bar: Node3D = _pivot(_hinge, "Bar", Vector3(0.0, BAR_Y - HINGE_Y, 0.0))
	_grip_l = _pivot(bar, "GripL", Vector3(-0.035, 0.0, 0.0))
	_add_mesh(_grip_l, "grip_l", Vector3.ZERO, material)
	_grip_r = _pivot(bar, "GripR", Vector3(0.035, 0.0, 0.0))
	_add_mesh(_grip_r, "grip_r", Vector3.ZERO, material)
	_apply_fold()


## 달린 거리만큼 바퀴를 굴린다 (앞으로 = 양수).
func roll(distance: float) -> void:
	for w: Node3D in _wheels:
		w.rotation.x = wrapf(w.rotation.x - distance / WHEEL_R, -PI, PI)


## 꺼내서 펼치고 올라타기 (≈1.3초, 내 캐릭터 · 친구 캐릭터 같다). 끝나면 done.
## 주머니를 뒤적여 → 접힌 킥보드가 앞에 톡 나오고 → 기둥이 철컥 서고 손잡이가 펴지면 → 폴짝 올라탄다 (킥보드가 발밑으로 들어온다).
func play_unfold(rig: CharacterRig, done: Callable, sound: bool) -> Tween:
	fold = 1.0
	scale = Vector3.ONE * 0.01
	position.z = AHEAD
	visible = true
	rig.set_rummaging(true)
	var tw: Tween = create_tween()
	tw.tween_interval(0.28)
	tw.tween_callback(func() -> void:
		rig.set_rummaging(false)
		if sound:
			Audio.play_sfx("emote_pop", -6.0, 1.2))
	tw.tween_property(self, "scale", Vector3.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fold", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		if sound:
			Audio.play_sfx("kick_latch", -3.0, 1.0))
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void: rig.set_riding("kick"))
	tw.tween_property(self, "position:z", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(done)
	return tw


## 내려서 접고 가방에 넣기 (≈1.2초). 폴짝 내리면 킥보드가 앞으로 빠지고 → 손잡이 · 기둥이 접히고(철컥) → 주머니에 쏙.
func play_fold(rig: CharacterRig, done: Callable, sound: bool) -> Tween:
	steer = 0.0
	rig.set_riding("")
	var tw: Tween = create_tween()
	tw.tween_property(self, "position:z", AHEAD, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "fold", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if sound:
			Audio.play_sfx("kick_latch", -3.0, 0.85)
		rig.set_rummaging(true))
	tw.tween_interval(0.15)
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		rig.set_rummaging(false)
		visible = false)
	tw.tween_interval(0.12)
	tw.tween_callback(done)
	return tw


## 손잡이 가운데 (월드, 손이 잡는 곳 확인용).
func bar_position() -> Vector3:
	return _hinge.get_node("Bar").global_position if _hinge != null else global_position


func _apply_fold() -> void:
	if _hinge == null:
		return
	# 기둥이 먼저 접히기 시작하면 손잡이도 같이 내려간다 (접을 때: 손잡이 → 기둥 순, 펼 때 반대). 한 값으로 두 구간을 나눈다.
	var grip_k: float = clampf(fold / 0.3, 0.0, 1.0)
	var stem_k: float = clampf((fold - 0.2) / 0.8, 0.0, 1.0)
	_hinge.rotation.x = FOLD_ANGLE * _ease(stem_k)
	_grip_l.rotation.z = GRIP_FOLD * _ease(grip_k)
	_grip_r.rotation.z = -GRIP_FOLD * _ease(grip_k)


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _pivot(parent: Node3D, node_name: String, at: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	n.name = node_name
	n.position = at
	parent.add_child(n)
	return n


static func _add_mesh(parent: Node3D, key: String, at: Vector3, material: Material) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh_of(key)
	mi.material_override = material
	mi.position = at
	parent.add_child(mi)


## 부품 메시 (부품마다 한 번만 만든다).
static func mesh_of(key: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var parts: Array = []
	var stem_len: float = BAR_Y - HINGE_Y
	match key:
		"deck":
			parts = [
				{"s": "rbox", "size": [0.13, 0.032, 0.46], "at": [0, 0.074, -0.005], "c": ["#3C8BC8", "#5BB0EC"], "r": 0.45},
				{"s": "rbox", "size": [0.112, 0.006, 0.38], "at": [0, 0.091, 0.0], "c": "#2B3038", "r": 0.5},
				{"s": "rbox", "size": [0.07, 0.05, 0.07], "at": [0, 0.085, -0.24], "c": "#3C8BC8", "r": 0.4},
				{"s": "box", "size": [0.012, 0.05, 0.08], "at": [0.03, 0.065, 0.25], "c": "#C9CFD8"},
				{"s": "box", "size": [0.012, 0.05, 0.08], "at": [-0.03, 0.065, 0.25], "c": "#C9CFD8"},
				{"s": "sphere", "size": [0.05, 0.02, 0.09], "at": [0, 0.122, 0.275], "c": "#2B3038", "rot": [-12, 0, 0]},
				{"s": "rbox", "size": [0.04, 0.012, 0.02], "at": [0, 0.08, 0.232], "c": "#E9822E", "r": 0.4},
			]
		"wheel":
			parts = [
				{"s": "cyl", "size": [WHEEL_R, 0.034], "at": [0, 0, 0], "c": "#3A3F47", "rot": [0, 0, 90], "r": 0.012},
				{"s": "cyl", "size": [0.032, 0.038], "at": [0, 0, 0], "c": "#F4F4F2", "rot": [0, 0, 90], "r": 0.006},
				{"s": "cyl", "size": [0.011, 0.044], "at": [0, 0, 0], "c": "#E9822E", "rot": [0, 0, 90]},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [0.02, 0.021, 0], "c": "#3A3F47"},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [0.02, -0.0105, 0.0182], "c": "#3A3F47"},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [0.02, -0.0105, -0.0182], "c": "#3A3F47"},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [-0.02, 0.021, 0], "c": "#3A3F47"},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [-0.02, -0.0105, 0.0182], "c": "#3A3F47"},
				{"s": "sphere", "size": [0.006, 0.008, 0.008], "at": [-0.02, -0.0105, -0.0182], "c": "#3A3F47"},
			]
		"fork":
			parts = [
				{"s": "cap", "size": [0.011], "at": [0.028, WHEEL_R, 0], "to": [0.026, HINGE_Y, 0.0], "c": "#C9CFD8"},
				{"s": "cap", "size": [0.011], "at": [-0.028, WHEEL_R, 0], "to": [-0.026, HINGE_Y, 0.0], "c": "#C9CFD8"},
				{"s": "rbox", "size": [0.068, 0.045, 0.06], "at": [0, HINGE_Y, 0], "c": "#2B3038", "r": 0.4},
				{"s": "sphere", "size": [0.05, 0.016, 0.075], "at": [0, WHEEL_R + 0.052, -0.005], "c": "#3C8BC8", "rot": [8, 0, 0]},
			]
		"stem":
			parts = [
				{"s": "cyl", "size": [0.017, stem_len], "at": [0, stem_len * 0.5, 0], "c": ["#B9C0CA", "#E2E6EC"], "r": 0.004},
				{"s": "cyl", "size": [0.024, 0.05], "at": [0, 0.05, 0], "c": "#E9822E", "r": 0.008},
				{"s": "cyl", "size": [0.021, 0.03], "at": [0, stem_len * 0.55, 0], "c": "#2B3038", "r": 0.006},
				{"s": "rbox", "size": [0.08, 0.034, 0.04], "at": [0, stem_len, 0], "c": "#2B3038", "r": 0.4},
				{"s": "sphere", "size": [0.016], "at": [0, stem_len + 0.022, 0], "c": "#E9822E"},
			]
		"grip_l", "grip_r":
			var side: float = -1.0 if key == "grip_l" else 1.0
			parts = [
				{"s": "cyl", "size": [0.013, 0.085], "at": [side * 0.042, 0, 0], "c": "#C9CFD8", "rot": [0, 0, 90]},
				{"s": "cyl", "size": [0.021, 0.11], "at": [side * 0.14, 0, 0], "c": "#2B3038", "rot": [0, 0, 90], "r": 0.008},
				{"s": "sphere", "size": [0.017], "at": [side * 0.198, 0, 0], "c": "#E9822E"},
			]
	var mesh: ArrayMesh = PartMesh.build(parts)
	_meshes[key] = mesh
	return mesh
