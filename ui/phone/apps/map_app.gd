class_name MapApp
extends PhoneApp
## 지도 (v16, v0.21 시내 / 도시 전체): 도시 지도(바닥 색 지도 ground_map) 위에 내 위치 · 친구 · 주민 · 상점 · 식당 · 낚시터 등을 표시한다.
## 표시를 누르면 아래에 이름과 설명, 친구면 "놀러 가기"(그 친구 집으로 바로). 위치는 화면에 그리는 값 그대로라 판정과 상관없다.
## v0.28.1: 내 자리를 가운데 두고(따라가기) ＋ · － 단추 · 두 손가락 벌리기 · 휠로 확대 · 축소, 끌면 지도를 옮기고 "내 위치"로 돌아온다.
## 빈 곳을 누르면 그 자리에 웨이포인트(Waypoint)가 놓이고 마을에 빛기둥 · 방향 화살표로 보인다.

const GROUND_MAP: String = "res://assets/packs/low/ground_map.png"
const SEA: Color = Color("#8FD0EC")
const SEA_DEEP: Color = Color("#6FB8DE")
## 표시 종류 → 색.
const COLORS: Dictionary[String, Color] = {
	"me": Color("#FF7A3D"), "friend": Color("#3D8BFF"), "npc": Color("#F2A6C0"),
	"place": Color("#FFFFFF"), "spot": Color("#2F7FD0"), "house": Color("#F7D98B"),
	"supply": Color("#FF4A3A"), "gate": Color("#7A4AE0"),
}
const FILTERS: PackedStringArray = ["사람", "장소", "낚시터"]
const WAYPOINT: Color = Color("#22C3E6")

## 지도 위 표시 하나.
class Marker:
	var kind: String = ""
	var key: String = ""
	var title: String = ""
	var about: String = ""
	var at: Vector2 = Vector2.ZERO
	## 글자 표시 (가게 첫 글자 등).
	var glyph: String = ""


var _canvas: Control = null
var _info: VBoxContainer = null
var _markers: Array[Marker] = []
var _picked: String = ""
var _shown: Dictionary[String, bool] = {"사람": true, "장소": true, "낚시터": true}
var _ground: Texture2D = null
var _extent: float = 104.0
## 보이는 범위 (가운데 · 반 너비, m). 따라가기면 가운데 = 내 자리.
var _view_center: Vector2 = Vector2.ZERO
var _view_half: float = 90.0
var _follow: bool = true
## 확대 · 축소 범위 (반 너비 m) · 단추 한 번 배율.
const ZOOM_MIN: float = 25.0
const ZOOM_STEP: float = 0.7
## 처음 여는 반 너비 (앱을 닫았다 열어도 이어진다).
static var last_half: float = 90.0
## 누른 손가락 (index → 자리) · 끌기 시작점 · 끌었는지.
var _touches: Dictionary[int, Vector2] = {}
var _press_at: Vector2 = Vector2.INF
var _dragged: bool = false
var _pinch_dist: float = 0.0
const TAP_SLOP: float = 18.0
var _pulse: float = 0.0
var _refresh: float = 0.0


func _ready() -> void:
	_ground = load(GROUND_MAP) if ResourceLoader.exists(GROUND_MAP) else null
	if GameData.layout != null:
		_extent = GameData.layout.map_extent
	_view_half = clampf(last_half, ZOOM_MIN, _extent)
	_recenter()
	_build()


## 내 자리로 (따라가기).
func _recenter() -> void:
	_follow = true
	var me: Vector2 = _my_spot()
	_view_center = me if me != Vector2.INF else Vector2(-60.0, 40.0)


## 확대(k < 1) · 축소(k > 1). focus = 지도 좌표의 그 자리를 그대로 두고.
func zoom_by(k: float, focus: Vector2 = Vector2.INF) -> void:
	var before: float = _view_half
	_view_half = clampf(_view_half * k, ZOOM_MIN, _extent)
	last_half = _view_half
	if focus != Vector2.INF and not _follow and _canvas != null:
		var world: Vector2 = _from_map(focus)
		_view_center = world + (_view_center - world) * (_view_half / before)
	if _canvas != null:
		_canvas.queue_redraw()


## 지금 반 너비 (테스트용).
func view_half() -> float:
	return _view_half


func view_center() -> Vector2:
	return _view_center


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.2, TAU)
	if _follow:
		var me: Vector2 = _my_spot()
		if me != Vector2.INF:
			_view_center = me
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_collect()
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_redraw()


func go_back() -> bool:
	if _picked.is_empty():
		return false
	_picked = ""
	_show_info()
	return true


func _build() -> void:
	clear()
	var filters: HBoxContainer = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	add_child(filters)
	for f: String in FILTERS:
		var b: Button = button(f, 26, INK, _shown[f])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_shown[f] = not _shown[f]
			Audio.play_ui(Audio.SFX_CLICK)
			_build())
		filters.add_child(b)
	# 확대 · 축소 · 내 위치.
	var zoom_row: HBoxContainer = HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 8)
	add_child(zoom_row)
	for spec: Array in [["ZoomOut", "－", 1.0 / ZOOM_STEP], ["ZoomIn", "＋", ZOOM_STEP]]:
		var zb: Button = button(str(spec[1]), 34, INK, false)
		zb.name = str(spec[0])
		zb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var k: float = float(spec[2])
		zb.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			zoom_by(k))
		zoom_row.add_child(zb)
	var mine: Button = button("◎ 내 위치", 26, INK, false)
	mine.name = "CenterMe"
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		_recenter())
	zoom_row.add_child(mine)
	if Waypoint.is_set():
		var clear: Button = button("웨이포인트 지우기", 24, WARN, false)
		clear.name = "ClearWaypoint"
		clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clear.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Waypoint.clear()
			_picked = ""
			_build())
		zoom_row.add_child(clear)
	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	var side: float = minf(view_width() - 6.0, view_height() - 120.0)
	_canvas.custom_minimum_size = Vector2(side, maxf(420.0, side))
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.add_to_group(&"no_touch_scroll")
	add_child(_canvas)
	_info = card()
	_collect()
	_show_info()
	_build_visits()


## 지도에 올릴 것들을 모은다 (사람은 움직이니 자주).
func _collect() -> void:
	_markers.clear()
	if _shown["장소"]:
		_add_places()
	if _shown["낚시터"]:
		for spot: SpotInfo in GameData.spots.values():
			_add("spot", "spot:" + spot.id, spot.display_name, "낚시터 · %s" % ", ".join(_fish_names(spot)), spot.center, "")
	if _shown["사람"]:
		for npc: NetNpcState in Net.npc_states:
			var info: NpcInfo = GameData.npcs.get(npc.id)
			if info != null and _on_map(npc.position):
				_add("npc", "npc:" + npc.id, info.display_name, info.about, Vector2(npc.position.x, npc.position.z), info.display_name.left(1))
		var rep: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
		for slot: int in Net.names.keys() + Net.faces.keys():
			if slot == Net.my_id or rep == null or _markers.any(func(m: Marker) -> bool: return m.key == "pl:%d" % slot):
				continue
			var p: Vector3 = rep.remote_position(slot)
			if p != Vector3.INF and _on_map(p):
				_add("friend", "pl:%d" % slot, Journal.display_name(slot), "같은 마을 친구", Vector2(p.x, p.z), GameData.player_name(slot).left(1))
	# v0.28 게이트 (등급 · 브레이크).
	for gid: String in Net.gates:
		var g: Dictionary = Net.gates[gid]
		var gst: String = str(g["st"])
		_add("gate", "gate:" + gid, "%s급 게이트 · %s" % [str(g["rank"]), str(g["name"])], "던전 브레이크! 크리처가 쏟아져요. 피하세요." if gst == "break" else ("헌터가 공략 중이에요." if gst == "raid" else "공략하지 않으면 던전 브레이크가 일어나요. 헌터 등급이 한 단계 아래까지 들어갈 수 있어요."), Vector2(float(g["x"]), float(g["z"])), str(g["rank"]))
	# v0.27 보급 상자 (밤, 먼저 연 사람이 갖는다).
	for sid: String in Net.supply:
		_add("supply", "supply:" + sid, "보급 상자", "헬기가 떨어뜨린 상자. 먼저 여는 사람이 가져요 — 둘레에 크리처가 있을지도.", Vector2(float(Net.supply[sid]["x"]), float(Net.supply[sid]["z"])), "보")
	var me: Vector2 = _my_spot()
	if me != Vector2.INF:
		_add("me", "me", "나 (%s)" % GameData.player_name(Net.my_id), "지금 내가 있는 곳" if not Home.is_inside() else "집 안 (%s)" % Home.unit, me, "")


func _add_places() -> void:
	var econ: EconData = GameData.econ
	var plaza: Vector2 = GameData.layout.plaza_center if GameData.layout != null else Vector2.ZERO
	_add("place", "plaza", "마을 광장", "시내 상점가 한가운데. 거울과 꽃밭이 있어요.", plaza, "광")
	if GameData.shop != null:
		_add("place", "shop", "솔바람 상점", "물건을 사고팔아요. 상점이 크면 파는 것도 늘어요.", Vector2(GameData.shop.door.x, GameData.shop.door.z - 3.0), "상")
	if GameData.museum != null:
		_add("place", "museum", GameData.museum.display_name, "물고기를 기증하면 수족관이 채워져요.", Vector2(GameData.museum.building_position.x, GameData.museum.building_position.z), "박")
	if GameData.airport != null:
		_add("place", "airport", GameData.airport.display_name, "기념품 가게와 조종사가 있어요.", Vector2(GameData.airport.building_position.x, GameData.airport.building_position.z), "공")
	if econ != null:
		var rest: Dictionary = econ.restaurant.get("building", {})
		if not rest.is_empty():
			_add("place", "restaurant", "식당", "같이 요리해서 손님을 받아요.", Vector2(float(rest.get("x", 0.0)), float(rest.get("z", 0.0))), "식")
		var civic: Dictionary = econ.civic.get("building", {})
		if not civic.is_empty():
			_add("place", "civic", "동사무소", "전입 · 지원금 · 정책대출 · 혼인신고.", Vector2(float(civic.get("x", 0.0)), float(civic.get("z", 0.0))), "동")
		for b: Variant in econ.buildings():
			if b is Dictionary:
				_add("place", "apt:%s" % str(b.get("id", "")), "%s %s동" % [econ.complex_name(), str(b.get("id", ""))], "공동 현관에서 집에 들어가요.", Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0))), "아")
		# 둘레 단지 (겉모습만): 단지 가운데에 이름.
		for complex: Variant in econ.apartments.get("samples", []):
			if not complex is Dictionary or (complex.get("buildings", []) as Array).is_empty():
				continue
			var c: Vector2 = Vector2.ZERO
			for b2: Dictionary in complex["buildings"]:
				c += Vector2(float(b2.get("x", 0.0)), float(b2.get("z", 0.0)))
			c /= float((complex["buildings"] as Array).size())
			_add("place", "complex:%s" % str(complex.get("id", "")), str(complex.get("name", "")), "둘레 아파트 단지 (구경만).", c, "단")
	# v0.21 강변도시 이름 있는 건물 (학교 · 도서관 · 역 · 출장소) · 끊긴 다리 · 침수 구역.
	var city: CityData = GameData.city
	if city != null:
		for cb: CityData.Building in city.buildings:
			if not cb.name.is_empty():
				_add("place", "city:%s" % cb.id, cb.name, "탕정 제2지구 강변도시.", cb.center, cb.name.left(1))
		if city.flood_polygon.size() >= 3:
			var fc: Vector2 = Vector2.ZERO
			for pt: Vector2 in city.flood_polygon:
				fc += pt
			_add("place", "flood", "강 건너 구시가지 (침수)", "지난 장마에 둑이 터져 잠겼어요. 강을 건너갈 수는 없어요.", fc / float(city.flood_polygon.size()), "침")
	for npc: NpcInfo in GameData.npcs.values():
		if not npc.has_house:
			continue
		_add("house", "house:" + npc.id, "%s네 집" % npc.display_name, npc.about, Vector2(npc.house_position.x, npc.house_position.z), "")


func _add(kind: String, key: String, title: String, about: String, at: Vector2, glyph: String) -> void:
	var m: Marker = Marker.new()
	m.kind = kind
	m.key = key
	m.title = title
	m.about = about
	m.at = at
	m.glyph = glyph
	_markers.append(m)


func _on_map(p: Vector3) -> bool:
	return absf(p.x) <= _extent and absf(p.z) <= _extent


## 내 자리 (집 안이면 그 아파트 동 앞).
func _my_spot() -> Vector2:
	if Home.is_inside() and GameData.econ != null:
		var u: EconData.Unit = GameData.econ.unit(Home.unit)
		for b: Variant in GameData.econ.buildings():
			if u != null and b is Dictionary and str(b.get("id", "")) == u.building:
				return Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
	if phone == null or phone.player == null:
		return Vector2.INF
	var p: Vector3 = phone.player.global_position
	return Vector2(p.x, p.z) if _on_map(p) else Vector2.INF


func _fish_names(spot: SpotInfo) -> PackedStringArray:
	var names: PackedStringArray = []
	for id: String in spot.fish_ids:
		names.append(GameData.fish_name(id) if Journal.dex_fish.has(id) else "?")
	return names


# ---- 그리기 ----

func _to_map(world: Vector2) -> Vector2:
	var s: Vector2 = _canvas.size
	var q: Vector2 = world - _view_center
	return Vector2((q.x / (2.0 * _view_half) + 0.5) * s.x, (q.y / (2.0 * _view_half) + 0.5) * s.y)


## 지도 좌표 → 월드 (x, z).
func _from_map(at: Vector2) -> Vector2:
	var s: Vector2 = _canvas.size
	return _view_center + Vector2((at.x / s.x - 0.5) * 2.0 * _view_half, (at.y / s.y - 0.5) * 2.0 * _view_half)


## 보이는 범위 안인지 (지도 칸 밖 표시는 그리지 않는다).
func _in_view(world: Vector2) -> bool:
	var q: Vector2 = (world - _view_center).abs()
	return q.x <= _view_half and q.y <= _view_half


func _draw_map() -> void:
	var s: Vector2 = _canvas.size
	var sea: StyleBoxFlat = StyleBoxFlat.new()
	sea.bg_color = SEA
	sea.set_corner_radius_all(26)
	sea.border_color = SEA_DEEP
	sea.set_border_width_all(4)
	_canvas.draw_style_box(sea, Rect2(Vector2.ZERO, s))
	# 물결 무늬.
	for i: int in 9:
		var y: float = s.y * (0.08 + i * 0.11)
		_canvas.draw_arc(Vector2(s.x * (0.1 + fmod(i * 0.37, 0.8)), y), 10.0, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.35), 2.0, true)
	if _ground != null:
		# 바닥 지도(±_extent)와 보이는 범위가 겹치는 곳만 잘라 그린다 (가장자리 밖은 물).
		var lo: Vector2 = (_view_center - Vector2.ONE * _view_half).max(Vector2.ONE * -_extent)
		var hi: Vector2 = (_view_center + Vector2.ONE * _view_half).min(Vector2.ONE * _extent)
		if hi.x > lo.x and hi.y > lo.y:
			var tex: Vector2 = _ground.get_size()
			var src: Rect2 = Rect2((lo + Vector2.ONE * _extent) / (2.0 * _extent) * tex, (hi - lo) / (2.0 * _extent) * tex)
			var a: Vector2 = _to_map(lo)
			_canvas.draw_texture_rect_region(_ground, Rect2(a, _to_map(hi) - a), src)
	# 낚시터 물 (사각형 수역, 윤곽이 있는 호수는 윤곽 그대로).
	for spot: SpotInfo in GameData.spots.values():
		if spot.is_sea:
			continue
		if spot.has_outline():
			var shape: PackedVector2Array = PackedVector2Array()
			for pt: Vector2 in spot.outline:
				shape.append(_to_map(pt))
			_canvas.draw_colored_polygon(shape, Color("#7CC4EA"))
			continue
		var a: Vector2 = _to_map(spot.center - spot.half_extent)
		var b: Vector2 = _to_map(spot.center + spot.half_extent)
		var water: StyleBoxFlat = StyleBoxFlat.new()
		water.bg_color = Color("#7CC4EA")
		water.set_corner_radius_all(int(minf(b.x - a.x, b.y - a.y) * 0.3))
		_canvas.draw_style_box(water, Rect2(a, b - a))
	var font: Font = _canvas.get_theme_default_font()
	# 장소 · 집 · 낚시터 먼저, 사람은 위에.
	for pass_kind: Array in [["house", "place", "spot"], ["npc", "friend"], ["me"]]:
		for m: Marker in _markers:
			if m.kind in pass_kind:
				_draw_marker(m, font)
	_draw_waypoint(font)
	# 축척 (아래 왼쪽): 반 너비에 맞는 둥근 길이.
	var meters: float = 10.0
	for m_len: float in [10.0, 20.0, 50.0, 100.0, 200.0]:
		if m_len <= _view_half * 0.6:
			meters = m_len
	var px: float = meters / (2.0 * _view_half) * s.x
	_canvas.draw_line(Vector2(24.0, s.y - 26.0), Vector2(24.0 + px, s.y - 26.0), INK, 4.0)
	_canvas.draw_string(font, Vector2(24.0, s.y - 36.0), "%dm" % roundi(meters), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	# 북쪽 표시.
	_canvas.draw_string(font, Vector2(s.x - 54.0, 44.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(s.x - 44.0, 52.0), Vector2(s.x - 36.0, 70.0), Vector2(s.x - 52.0, 70.0)]), INK)


func _draw_marker(m: Marker, font: Font) -> void:
	if not _in_view(m.at):
		return
	var p: Vector2 = _to_map(m.at)
	var picked: bool = m.key == _picked
	var color: Color = COLORS.get(m.kind, Color.WHITE)
	match m.kind:
		"me":
			var r: float = 15.0 + sin(_pulse) * 3.0
			_canvas.draw_circle(p, r + 10.0, Color(color, 0.25))
			_canvas.draw_circle(p, r, Color.WHITE)
			_canvas.draw_circle(p, r - 4.0, color)
			if phone != null and phone.player != null and not Home.is_inside():
				var facing: Node3D = phone.player.body if phone.player.body != null else phone.player
				var f: Vector3 = -facing.global_basis.z
				var dir: Vector2 = Vector2(f.x, f.z).normalized()
				if dir != Vector2.ZERO:
					var tip: Vector2 = p + dir * (r + 14.0)
					var side: Vector2 = dir.orthogonal() * 9.0
					_canvas.draw_colored_polygon(PackedVector2Array([tip, p + dir * (r + 2.0) + side, p + dir * (r + 2.0) - side]), color)
		"friend", "npc":
			var r: float = 15.0 if m.kind == "friend" else 11.0
			_canvas.draw_circle(p + Vector2(0, 2), r + 2.0, Color(0, 0, 0, 0.2))
			_canvas.draw_circle(p, r + 2.0, Color.WHITE)
			_canvas.draw_circle(p, r, color)
			var fs: int = 18 if m.kind == "friend" else 14
			var w: float = font.get_string_size(m.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_canvas.draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), m.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		"house":
			_canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -2), p + Vector2(0, -13), p + Vector2(11, -2)]), Color("#E8594A"))
			_canvas.draw_rect(Rect2(p + Vector2(-8, -2), Vector2(16, 12)), color)
		"spot":
			_canvas.draw_circle(p, 14.0, Color.WHITE)
			_canvas.draw_arc(p + Vector2(0, -2), 7.0, 0.0, PI, 10, color, 3.0, true)
			_canvas.draw_line(p + Vector2(7, -2), p + Vector2(7, -10), color, 3.0, true)
		_:
			var box: StyleBoxFlat = StyleBoxFlat.new()
			box.bg_color = Color.WHITE
			box.border_color = Color(0.45, 0.36, 0.26)
			box.set_border_width_all(2)
			box.set_corner_radius_all(9)
			_canvas.draw_style_box(box, Rect2(p - Vector2(19, 19), Vector2(38, 38)))
			var w2: float = font.get_string_size(m.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			_canvas.draw_string(font, p + Vector2(-w2 * 0.5, 9.0), m.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	if picked or m.kind == "me" or m.kind == "friend":
		var tag: String = m.title if picked else ("나" if m.kind == "me" else GameData.player_name(int(m.key.trim_prefix("pl:"))))
		var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var bubble: StyleBoxFlat = StyleBoxFlat.new()
		bubble.bg_color = Color(1, 1, 1, 0.92)
		bubble.set_corner_radius_all(10)
		var at: Vector2 = p + Vector2(-tw * 0.5 - 8.0, -48.0)
		_canvas.draw_style_box(bubble, Rect2(at, Vector2(tw + 16.0, 28.0)))
		_canvas.draw_string(font, at + Vector2(8.0, 21.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	if picked:
		_canvas.draw_arc(p, 24.0, 0.0, TAU, 32, Color("#FF7A3D"), 3.0, true)


## 웨이포인트: 깃발 + 나에게서 점선.
func _draw_waypoint(font: Font) -> void:
	if not Waypoint.is_set():
		return
	var p: Vector2 = _to_map(Waypoint.at)
	var me: Vector2 = _my_spot()
	if me != Vector2.INF:
		var a: Vector2 = _to_map(me)
		var n: int = int(a.distance_to(p) / 16.0)
		for i: int in n:
			if i % 2 == 0:
				_canvas.draw_line(a.lerp(p, float(i) / float(maxi(n, 1))), a.lerp(p, float(i + 1) / float(maxi(n, 1))), WAYPOINT, 4.0, true)
	if not Rect2(Vector2.ZERO, _canvas.size).grow(20.0).has_point(p):
		return
	_canvas.draw_line(p, p + Vector2(0.0, -40.0), INK, 4.0, true)
	_canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -40.0), p + Vector2(28.0, -31.0), p + Vector2(0.0, -22.0)]), WAYPOINT)
	_canvas.draw_circle(p, 7.0, WAYPOINT)
	_canvas.draw_arc(p, 14.0 + sin(_pulse) * 3.0, 0.0, TAU, 24, WAYPOINT, 3.0, true)


## 누르기 · 끌기(지도 옮기기) · 두 손가락 벌리기 · 휠(확대 · 축소). 끌지 않고 뗀 자리에서 표시를 고르거나, 빈 곳이면 웨이포인트.
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_press(0, mb.position, mb.pressed)
		_canvas.accept_event()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and _touches.has(0) and not DisplayServer.is_touchscreen_available():
		_drag(0, (event as InputEventMouseMotion).position)
		_canvas.accept_event()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		_press(st.index, st.position, st.pressed)
		_canvas.accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_drag(sd.index, sd.position)
		_canvas.accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01), (event as InputEventMagnifyGesture).position)
		_canvas.accept_event()


func _press(index: int, at: Vector2, down: bool) -> void:
	if down:
		_touches[index] = at
		if _touches.size() == 1:
			_press_at = at
			_dragged = false
		else:
			_dragged = true
			_pinch_dist = _pinch_span()
		return
	_touches.erase(index)
	if _touches.is_empty():
		if not _dragged and _press_at != Vector2.INF and at.distance_to(_press_at) <= TAP_SLOP:
			tap_at(at)
		_press_at = Vector2.INF
	elif _touches.size() == 1:
		_pinch_dist = 0.0


func _drag(index: int, at: Vector2) -> void:
	if not _touches.has(index):
		return
	var before: Vector2 = _touches[index]
	_touches[index] = at
	if _touches.size() >= 2:
		var span: float = _pinch_span()
		if _pinch_dist > 1.0 and span > 1.0:
			zoom_by(_pinch_dist / span)
		_pinch_dist = span
		return
	if _press_at.distance_to(at) > TAP_SLOP:
		_dragged = true
	if _dragged and _canvas != null:
		_follow = false
		_view_center -= (at - before) / _canvas.size.x * 2.0 * _view_half
		_canvas.queue_redraw()


func _pinch_span() -> float:
	var pts: Array[Vector2] = _touches.values()
	return pts[0].distance_to(pts[1]) if pts.size() >= 2 else 0.0


## 지도 위 자리(지도 좌표)를 눌렀다: 표시면 고르고, 빈 곳이면 웨이포인트를 놓는다 (테스트용으로도).
func tap_at(at: Vector2) -> void:
	pick_at(at)
	if not _picked.is_empty():
		return
	# 웨이포인트 깃발 곁이면 고른 것으로.
	if Waypoint.is_set() and _to_map(Waypoint.at).distance_to(at) < 34.0:
		_picked = "waypoint"
		_show_info()
		return
	Waypoint.place(_from_map(at))
	_picked = "waypoint"
	Audio.play_ui(Audio.SFX_CLICK)
	_build()


## 지도 위 자리(지도 좌표)에서 표시 고르기 (테스트용으로도).
func pick_at(at: Vector2) -> void:
	var best: Marker = null
	var best_d: float = 34.0
	for m: Marker in _markers:
		var d: float = _to_map(m.at).distance_to(at)
		if d < best_d:
			best_d = d
			best = m
	_picked = best.key if best != null else ""
	if best != null:
		Audio.play_ui(Audio.SFX_CLICK)
	_show_info()


## 지금 고른 표시 (테스트용).
func picked() -> String:
	return _picked


func _show_info() -> void:
	if _info == null:
		return
	for c: Node in _info.get_children():
		c.queue_free()
	if _picked == "waypoint" and Waypoint.is_set():
		_info.add_child(label("웨이포인트", 32, INK))
		var mine: Vector2 = _my_spot()
		_info.add_child(label("마을에 빛기둥과 방향 화살표로 보여요.%s 가까이 가면 저절로 지워져요." % (" 나에게서 %dm." % roundi(mine.distance_to(Waypoint.at)) if mine != Vector2.INF else ""), 24, SOFT))
		return
	var m: Marker = null
	for x: Marker in _markers:
		if x.key == _picked:
			m = x
	if m == null:
		_info.add_child(label("표시를 누르면 무엇인지 알려 줘요. 빈 곳을 누르면 웨이포인트를 놓아요. 끌어서 옮기고, ＋ · － 나 두 손가락으로 확대 · 축소.", 26, SOFT))
		var legend: HBoxContainer = HBoxContainer.new()
		legend.add_theme_constant_override("separation", 14)
		_info.add_child(legend)
		for pair: Array in [["me", "나"], ["friend", "친구"], ["npc", "주민"], ["spot", "낚시터"]]:
			var dot: ColorRect = ColorRect.new()
			dot.color = COLORS[str(pair[0])]
			dot.custom_minimum_size = Vector2(22, 22)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			legend.add_child(dot)
			legend.add_child(label(str(pair[1]), 22, INK, false))
		_info.add_child(label("곡교천은 둔치 물가 어디서나 낚시할 수 있어요. 보 아래 하류에는 바다 물고기도 올라와요.", 22, SOFT))
		return
	_info.add_child(label(m.title, 32, INK))
	if not m.about.is_empty():
		_info.add_child(label(m.about, 24, SOFT))
	var here: Vector2 = _my_spot()
	if here != Vector2.INF and m.kind != "me":
		_info.add_child(label("나에게서 %dm" % roundi(here.distance_to(m.at)), 22, SOFT))
	if m.kind == "friend":
		var slot: int = int(m.key.trim_prefix("pl:"))
		var unit: String = _home_of(slot)
		if not unit.is_empty():
			var go: Button = button("%s 님 집에 놀러 가기" % GameData.player_name(slot), 28, GOOD)
			go.pressed.connect(_visit.bind(unit))
			_info.add_child(go)


## 친구 집 목록 (지도 아래): 친구가 가진 집마다 "놀러 가기".
func _build_visits() -> void:
	var homes: Array[Array] = []
	for unit: String in Economy.home_owners:
		var slot: int = Economy.home_owners[unit]
		if slot != Net.my_id and slot > 0:
			homes.append([unit, slot])
	add_child(label("친구 집 놀러 가기", 32, INK))
	if homes.is_empty():
		add_child(label("아직 집을 산 친구가 없어요. 친구가 부동산 앱에서 집을 사면 여기서 바로 놀러 갈 수 있어요.", 24, SOFT))
		return
	for h: Array in homes:
		var row: Button = row_button(100.0)
		row.name = "Visit_%s" % str(h[0])
		var line: HBoxContainer = fill_row(row)
		var t: Label = label("%s 님 집 · %s" % [GameData.player_name(int(h[1])), str(h[0])], 28, INK, false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(t)
		var go: Label = label("놀러 가기 →", 26, GOOD, false)
		go.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(go)
		row.pressed.connect(_visit.bind(str(h[0])))
		add_child(row)


func _home_of(slot: int) -> String:
	for unit: String in Economy.home_owners:
		if Economy.home_owners[unit] == slot:
			return unit
	return ""


func _visit(unit: String) -> void:
	Audio.play_ui(Audio.SFX_CONFIRM)
	Journal.visit(unit)
	if phone != null:
		phone.close()
