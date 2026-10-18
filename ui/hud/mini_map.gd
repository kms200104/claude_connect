class_name MiniMap
extends Control
## 화면 오른쪽 위 작은 지도 (설정 "지도 항상 보기", Prefs.MINIMAP): 내 자리를 가운데 두고 둘레 radius m 를 북쪽 위로 그린다.
## 바닥 색 지도(ground_map) · 호수 윤곽 · 장소 글자 · 세워 둔 내 탈것 · 친구 · 주민 · 내 방향 화살표. 누르면 휴대폰 지도 앱.
## 집 안 · 휴대폰을 연 동안 · 마을 밖(접속 전)에는 감춘다. 그리는 값일 뿐 판정과 상관없다.

const GROUND_MAP: String = "res://assets/packs/low/ground_map.png"
const SEA: Color = Color("#8FD0EC")
const WATER: Color = Color("#7CC4EA")
const EDGE: Color = Color(0.36, 0.3, 0.28)
const INK: Color = Color(0.36, 0.24, 0.14)
const ME: Color = Color("#FF7A3D")
const FRIEND: Color = Color("#3D8BFF")
const NPC: Color = Color("#F2A6C0")
## 틀 모서리 반지름 (테두리와 지도 가리개가 같은 값).
const CORNER: int = 22

## 지도 한 변 (UI 픽셀, 1080×1920 기준).
@export var side: float = 230.0
## 오른쪽 단추 줄(휴대폰 단추 1010) 위, 위쪽 알림 줄 아래.
@export var top: float = 410.0
## 가운데에서 가장자리까지 보이는 거리 (m).
@export_range(10.0, 120.0) var radius: float = 38.0

var phone: PhoneWindow = null
var player: Player = null

var _ground: Texture2D = null
var _extent: float = 104.0
var _refresh: float = 0.0
## 장소 [글자, 자리] (한 번 모은다).
var _places: Array[Array] = []
## 둥근 틀 모양 가리개 (그 안의 지도만 보인다) · 지도 · 테두리.
var _mask: Panel = null
var _map: Control = null
var _frame: Control = null


func _ready() -> void:
	name = "MiniMap"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"blocks_joystick")
	HudLayout.right_top(self, Vector2(side, side), 24.0, top)
	# 테두리는 모서리가 둥근데 지도는 네모라, 둥근 가리개 안에만 지도를 그린다 (모서리 밖으로 삐져나오지 않게).
	_mask = Panel.new()
	var shape: StyleBoxFlat = StyleBoxFlat.new()
	shape.bg_color = Color.WHITE
	shape.set_corner_radius_all(CORNER)
	shape.anti_aliasing = true
	_mask.add_theme_stylebox_override("panel", shape)
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(_mask)
	_map = Control.new()
	_mask.add_child(_map)
	_frame = Control.new()
	add_child(_frame)
	for c: Control in [_mask, _map, _frame]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_frame.draw.connect(_draw_frame)
	_ground = load(GROUND_MAP) if ResourceLoader.exists(GROUND_MAP) else null
	if GameData.layout != null:
		_extent = GameData.layout.map_extent
	_collect_places()
	Prefs.events.changed.connect(func(_k: String) -> void: _update_visible())
	_update_visible()


func _process(delta: float) -> void:
	_update_visible()
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1
		_redraw()


func _gui_input(event: InputEvent) -> void:
	var tap: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tap and phone != null:
		Audio.play_ui(Audio.SFX_CLICK)
		phone.open(PhoneWindow.Tab.MAP)
		accept_event()


## 지금 보여야 하는지 (설정 · 마을 안 · 휴대폰 닫힘 · 집 밖).
func should_show() -> bool:
	return Prefs.minimap() and Net.state == Net.State.ONLINE and player != null and not Home.is_inside() and (phone == null or not phone.visible)


func _update_visible() -> void:
	var want: bool = should_show()
	if visible != want:
		visible = want
		if want:
			_redraw()


func _redraw() -> void:
	if _map != null:
		_map.queue_redraw()
		_frame.queue_redraw()


func _collect_places() -> void:
	_places.clear()
	var layout: VillageLayout = GameData.layout
	if layout != null:
		_places.append(["광", layout.plaza_center])
	if GameData.shop != null:
		_places.append(["상", Vector2(GameData.shop.door.x, GameData.shop.door.z - 3.0)])
	if GameData.museum != null:
		_places.append(["박", Vector2(GameData.museum.building_position.x, GameData.museum.building_position.z - 3.0)])
	if GameData.airport != null:
		_places.append(["공", Vector2(GameData.airport.building_position.x, GameData.airport.building_position.z - 3.0)])
	var econ: EconData = GameData.econ
	if econ != null:
		var rest: Dictionary = econ.restaurant.get("building", {})
		if not rest.is_empty():
			_places.append(["식", Vector2(float(rest.get("x", 0.0)), float(rest.get("z", 0.0)))])
		var civic: Dictionary = econ.civic.get("building", {})
		if not civic.is_empty():
			_places.append(["동", Vector2(float(civic.get("x", 0.0)), float(civic.get("z", 0.0)) - 3.0)])
		var gate: Variant = econ.apartments.get("gate")
		if gate is Dictionary:
			_places.append(["아", Vector2(float(gate.get("x", 0.0)), float(gate.get("z", 0.0)))])


func _me() -> Vector2:
	var p: Vector3 = player.global_position if player != null else Vector3.ZERO
	return Vector2(p.x, p.z)


func _to_mini(world: Vector2, me: Vector2) -> Vector2:
	return size * 0.5 + (world - me) * (size.x * 0.5 / radius)


## 지도 내용 (둥근 틀 모양으로 잘린다 — _mask).
func _draw_map() -> void:
	var s: Vector2 = size
	var me: Vector2 = _me()
	_map.draw_rect(Rect2(Vector2.ZERO, s), SEA)
	# 바닥 색 지도: 보이는 범위와 지도(±extent)가 겹치는 곳만.
	if _ground != null:
		var lo: Vector2 = (me - Vector2.ONE * radius).max(Vector2.ONE * -_extent)
		var hi: Vector2 = (me + Vector2.ONE * radius).min(Vector2.ONE * _extent)
		if hi.x > lo.x and hi.y > lo.y:
			var tex: Vector2 = _ground.get_size()
			var src: Rect2 = Rect2((lo + Vector2.ONE * _extent) / (2.0 * _extent) * tex, (hi - lo) / (2.0 * _extent) * tex)
			var a: Vector2 = _to_mini(lo, me)
			_map.draw_texture_rect_region(_ground, Rect2(a, _to_mini(hi, me) - a), src)
	# 호수 · 연못 윤곽.
	for spot: SpotInfo in GameData.spots.values():
		if spot.is_sea or not spot.has_outline():
			continue
		if (spot.center - me).length() > radius + spot.half_extent.length():
			continue
		var shape: PackedVector2Array = PackedVector2Array()
		for pt: Vector2 in spot.outline:
			shape.append(_to_mini(pt, me))
		_map.draw_colored_polygon(shape, WATER)
	var font: Font = get_theme_default_font()
	for place: Array in _places:
		var p: Vector2 = _to_mini(place[1], me)
		if not Rect2(Vector2.ZERO, s).grow(-8.0).has_point(p):
			continue
		_map.draw_circle(p, 15.0, Color(1, 1, 1, 0.92))
		_map.draw_arc(p, 15.0, 0.0, TAU, 20, EDGE, 2.0, true)
		var w: float = font.get_string_size(place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_map.draw_string(font, p + Vector2(-w * 0.5, 6.5), place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	# 세워 둔 내 탈것 (v19.1, 주황 테두리 · 바퀴 둘).
	for e: Dictionary in Net.parked:
		if int(e.get("o", 0)) != Net.my_id:
			continue
		var vp: Vector2 = _to_mini(Vector2(float(e.get("x", 0.0)), float(e.get("z", 0.0))), me)
		if not Rect2(Vector2.ZERO, s).grow(-6.0).has_point(vp):
			continue
		_map.draw_circle(vp, 12.0, Color.WHITE)
		_map.draw_arc(vp, 12.0, 0.0, TAU, 18, ME, 2.5, true)
		_map.draw_arc(vp + Vector2(-4.5, 2.0), 3.5, 0.0, TAU, 10, INK, 1.8, true)
		_map.draw_arc(vp + Vector2(4.5, 2.0), 3.5, 0.0, TAU, 10, INK, 1.8, true)
		_map.draw_line(vp + Vector2(-4.5, 2.0), vp + Vector2(0.0, -3.5), INK, 1.8, true)
		_map.draw_line(vp + Vector2(0.0, -3.5), vp + Vector2(4.5, 2.0), INK, 1.8, true)
	for npc: NetNpcState in Net.npc_states:
		_map.draw_circle(_to_mini(Vector2(npc.position.x, npc.position.z), me), 6.0, NPC)
	var rep: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if rep != null:
		for slot: int in Net.names.keys():
			if slot == Net.my_id:
				continue
			var q: Vector3 = rep.remote_position(slot)
			if q != Vector3.INF:
				var f: Vector2 = _to_mini(Vector2(q.x, q.z), me)
				# v0.28.12 직업이 있으면 직업 색 점 (2차 전직이면 금빛 테두리).
				var job: String = Net.job_of(slot)
				var adv: bool = Net.advanced_of(slot)
				_map.draw_circle(f, 9.0 if adv else 8.0, JobLook.GOLD if adv and not job.is_empty() else Color.WHITE)
				_map.draw_circle(f, 6.0, FRIEND if job.is_empty() else JobLook.color_of(job, adv))
	# v0.28.5 각성 '기척 감지': 둘레 크리처가 붉은 점으로 (우두머리는 크게).
	if Net.has_awaken("sense"):
		var sense_range: float = float(GameData.hunter.awaken("sense").get("range", 40.0))
		var inside: Rect2 = Rect2(Vector2.ZERO, s).grow(-6.0)
		for cid: String in Net.creatures:
			var cr: Dictionary = Net.creatures[cid]
			var cw: Vector2 = Vector2(float(cr.get("x", 0.0)), float(cr.get("z", 0.0)))
			if cw.distance_to(me) > sense_range:
				continue
			var cp: Vector2 = _to_mini(cw, me)
			if inside.has_point(cp):
				_map.draw_circle(cp, 9.0 if cr.has("b") else 6.0, Color("#1A0606"))
				_map.draw_circle(cp, 7.0 if cr.has("b") else 4.5, Color("#FF3A2A"))
	# v0.28.1 웨이포인트 (밖이면 가장자리에 붙여 방향만).
	if Waypoint.is_set():
		var wp: Vector2 = _to_mini(Waypoint.at, me)
		var inner: Rect2 = Rect2(Vector2.ZERO, s).grow(-14.0)
		if not inner.has_point(wp):
			var dir_w: Vector2 = (wp - s * 0.5)
			var k: float = minf((s.x * 0.5 - 14.0) / maxf(absf(dir_w.x), 0.001), (s.y * 0.5 - 14.0) / maxf(absf(dir_w.y), 0.001))
			wp = s * 0.5 + dir_w * k
		_map.draw_circle(wp, 10.0, Color.WHITE)
		_map.draw_circle(wp, 7.0, Color("#22C3E6"))
	# 나: 가운데 동그라미 + 보는 쪽 화살표.
	var c: Vector2 = s * 0.5
	_map.draw_circle(c, 11.0, Color.WHITE)
	_map.draw_circle(c, 8.0, ME)
	if player != null:
		var facing: Node3D = player.body if player.body != null else player
		var fwd: Vector3 = -facing.global_basis.z
		var dir: Vector2 = Vector2(fwd.x, fwd.z).normalized()
		if dir != Vector2.ZERO:
			var tip: Vector2 = c + dir * 24.0
			var side_v: Vector2 = dir.orthogonal() * 7.0
			_map.draw_colored_polygon(PackedVector2Array([tip, c + dir * 12.0 + side_v, c + dir * 12.0 - side_v]), ME)


## 테두리 + 북쪽 표시 (지도 위에).
func _draw_frame() -> void:
	var s: Vector2 = size
	var font: Font = get_theme_default_font()
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = EDGE
	frame.set_border_width_all(5)
	frame.set_corner_radius_all(CORNER)
	_frame.draw_style_box(frame, Rect2(Vector2.ZERO, s))
	_frame.draw_string(font, Vector2(s.x - 30.0, 30.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
