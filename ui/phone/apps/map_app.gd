class_name MapApp
extends PhoneApp
## 지도 (v16): 섬 전체 지도(바닥 색 지도 ground_map) 위에 내 위치 · 친구 · 주민 · 상점 · 식당 · 낚시터 등을 표시한다.
## 표시를 누르면 아래에 이름과 설명, 친구면 "놀러 가기"(그 친구 집으로 바로). 위치는 화면에 그리는 값 그대로라 판정과 상관없다.

const GROUND_MAP: String = "res://assets/packs/low/ground_map.png"
const SEA: Color = Color("#8FD0EC")
const SEA_DEEP: Color = Color("#6FB8DE")
## 표시 종류 → 색.
const COLORS: Dictionary[String, Color] = {
	"me": Color("#FF7A3D"), "friend": Color("#3D8BFF"), "npc": Color("#F2A6C0"),
	"place": Color("#FFFFFF"), "spot": Color("#2F7FD0"), "house": Color("#F7D98B"),
}
const FILTERS: PackedStringArray = ["사람", "장소", "낚시터"]

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
var _pulse: float = 0.0
var _refresh: float = 0.0


func _ready() -> void:
	_ground = load(GROUND_MAP) if ResourceLoader.exists(GROUND_MAP) else null
	if GameData.layout != null:
		_extent = GameData.layout.map_extent
	_build()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.2, TAU)
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
	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	var side: float = minf(view_width() - 6.0, view_height() - 120.0)
	_canvas.custom_minimum_size = Vector2(side, maxf(420.0, side))
	_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
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
	var me: Vector2 = _my_spot()
	if me != Vector2.INF:
		_add("me", "me", "나 (%s)" % GameData.player_name(Net.my_id), "지금 내가 있는 곳" if not Home.is_inside() else "집 안 (%s)" % Home.unit, me, "")


func _add_places() -> void:
	var econ: EconData = GameData.econ
	_add("place", "plaza", "마을 광장", "마을 한가운데. 거울과 꽃밭이 있어요.", Vector2.ZERO, "광")
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
				_add("place", "apt:%s" % str(b.get("id", "")), "솔바람 아파트 %s동" % str(b.get("id", "")), "공동 현관에서 집에 들어가요.", Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0))), "아")
	for npc: NpcInfo in GameData.npcs.values():
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
	return Vector2((world.x / (2.0 * _extent) + 0.5) * s.x, (world.y / (2.0 * _extent) + 0.5) * s.y)


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
		_canvas.draw_texture_rect(_ground, Rect2(Vector2.ZERO, s), false)
	# 낚시터 물 (사각형 수역).
	for spot: SpotInfo in GameData.spots.values():
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
	# 북쪽 표시.
	_canvas.draw_string(font, Vector2(s.x - 54.0, 44.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(s.x - 44.0, 52.0), Vector2(s.x - 36.0, 70.0), Vector2(s.x - 52.0, 70.0)]), INK)


func _draw_marker(m: Marker, font: Font) -> void:
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


## 누른 자리에서 가장 가까운 표시를 고른다 (34px 안).
func _on_canvas_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not pressed:
		return
	var at: Vector2 = (event as InputEventMouseButton).position if event is InputEventMouseButton else (event as InputEventScreenTouch).position
	pick_at(at)


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
	var m: Marker = null
	for x: Marker in _markers:
		if x.key == _picked:
			m = x
	if m == null:
		_info.add_child(label("표시를 누르면 무엇인지 알려 줘요.", 26, SOFT))
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
		_info.add_child(label("바다 낚시는 섬 둘레 바닷가 어디서나 할 수 있어요.", 22, SOFT))
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
