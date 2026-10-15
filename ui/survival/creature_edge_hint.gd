class_name CreatureEdgeHint
extends Control
## v0.28.2 다가오는 크리처 방향 (HUD 맨 뒤, 터치는 통과): 화면 밖(또는 화면 가장자리 가까이)에서 RANGE m 안으로 들어온 크리처마다
## 그쪽 화면 가장자리에 붉은 빛이 은은하게 번진다 — 가까울수록 진하고 크게, 나를 쫓는 중이면 천천히 맥동.
## 방해되지 않게 가장자리 얇은 띠에만, 가장 진해도 반투명. 그리는 값일 뿐 판정과 상관없다.

const RANGE: float = 30.0
## 화면 안이어도 가장자리 이만큼(비율) 안에 있으면 띄운다.
const EDGE_IN: float = 0.08
const COLOR: Color = Color(0.85, 0.12, 0.1)
const MAX_ALPHA: float = 0.5

var player: Node3D = null
var _time: float = 0.0
## 이번 프레임에 그릴 것 [[가장자리 자리, 세기 0~1, 쫓는 중]].
var _hints: Array[Array] = []
static var _glow: GradientTexture2D = null


func _ready() -> void:
	name = "CreatureEdgeHint"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 지금 띄운 표시 수 (테스트용).
func hint_count() -> int:
	return _hints.size()


func _process(delta: float) -> void:
	_time += delta
	_hints.clear()
	if player == null or Net.state != Net.State.ONLINE or Net.creatures.is_empty() or Home.is_inside():
		queue_redraw()
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var s: Vector2 = size
	var center: Vector2 = s * 0.5
	var me: Vector3 = player.global_position
	for id: String in Net.creatures:
		var c: Dictionary = Net.creatures[id]
		var at: Vector3 = Vector3(float(c.get("x", 0.0)), 1.0, float(c.get("z", 0.0)))
		var d: float = Vector2(at.x - me.x, at.z - me.z).length()
		if d > RANGE:
			continue
		var on: Vector2 = cam.unproject_position(at)
		var behind: bool = cam.is_position_behind(at)
		var inside: bool = not behind and Rect2(s * EDGE_IN, s * (1.0 - 2.0 * EDGE_IN)).has_point(on)
		if inside:
			continue
		var dir: Vector2 = (on - center) if not behind else (center - on)
		if dir.length() < 1.0:
			continue
		# 가운데에서 그쪽으로 뻗어 화면 가장자리와 만나는 점.
		var k: float = minf(center.x / maxf(absf(dir.x), 0.001), center.y / maxf(absf(dir.y), 0.001))
		var edge: Vector2 = center + dir * k
		var strength: float = clampf(1.0 - d / RANGE, 0.0, 1.0)
		_hints.append([edge, strength, int(c.get("a", 0)) == 1 or d < 10.0])
	queue_redraw()


func _draw() -> void:
	if _hints.is_empty():
		return
	var tex: GradientTexture2D = _texture()
	for h: Array in _hints:
		var at: Vector2 = h[0]
		var strength: float = h[1]
		var pulse: float = 0.85 + 0.15 * sin(_time * 4.0) if bool(h[2]) else 1.0
		var r: float = lerpf(70.0, 180.0, strength)
		var a: float = MAX_ALPHA * (0.25 + 0.75 * strength) * pulse
		draw_texture_rect(tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, a))


## 가운데가 붉고 바깥으로 사라지는 둥근 빛 (모두 같이 쓴다).
static func _texture() -> GradientTexture2D:
	if _glow == null:
		var g: Gradient = Gradient.new()
		g.set_color(0, Color(COLOR, 1.0))
		g.set_color(1, Color(COLOR, 0.0))
		g.add_point(0.4, Color(COLOR, 0.55))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 64
		_glow.height = 64
	return _glow
