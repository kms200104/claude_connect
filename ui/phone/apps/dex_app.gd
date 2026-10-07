class_name DexApp
extends PhoneApp
## 도감 (v16): 잡은 물고기 · 모은 가구와 옷 · 박물관 기증 현황을 한눈에.
## 값은 서버가 보낸 것(Journal.dex_fish · dex_items, Net.museum_fish)만 보여 준다. 아직 못 본 것은 그림자로.

const TAB_NAMES: PackedStringArray = ["물고기", "가구 · 옷", "박물관"]
const RARITY: Dictionary[String, String] = {"common": "흔함", "uncommon": "조금 귀함", "rare": "귀함", "legendary": "전설"}
const RARITY_COLOR: Dictionary[String, Color] = {"common": Color("#7A8A6A"), "uncommon": Color("#3E8E9E"), "rare": Color("#9B6AD8"), "legendary": Color("#E0A020")}
const WEATHER: Dictionary[String, String] = {"clear": "맑음", "cloudy": "흐림", "rain": "비", "thunder": "천둥번개"}
const SIZE: Dictionary[String, String] = {"XS": "아주 작음", "S": "작음", "M": "보통", "L": "큼", "XL": "아주 큼"}
const COLUMNS: int = 4

var _tab: int = 0
## 물고기 · 아이템 칸을 눌러 본 것 (위에 자세히).
var _picked: String = ""


func _ready() -> void:
	_build()
	Journal.changed.connect(_rebuild_later)
	Net.museum_changed.connect(func(_f: String, _b: int) -> void: _rebuild_later())


func go_back() -> bool:
	if _picked.is_empty():
		return false
	_picked = ""
	_build()
	return true


func _rebuild_later() -> void:
	if is_inside_tree():
		_build.call_deferred()


func _build() -> void:
	clear()
	tabs(TAB_NAMES, _tab, func(i: int) -> void:
		_tab = i
		_picked = ""
		_build())
	match _tab:
		0:
			_build_fish()
		1:
			_build_items()
		2:
			_build_museum()


# ---- 물고기 ----

func _build_fish() -> void:
	var total: int = GameData.fish.size()
	var have: int = Journal.dex_fish.size()
	var head: VBoxContainer = card()
	head.add_child(label("물고기 %d / %d 종 · 낚은 수 %d마리" % [have, total, Journal.stat("fish")], 32, INK))
	head.add_child(meter(float(have) / maxf(1.0, float(total)), GOOD))
	if not _picked.is_empty() and GameData.fish.has(_picked):
		_fish_detail(GameData.fish[_picked])
	var grid: GridContainer = _grid()
	for f: FishInfo in GameData.fish.values():
		var known: bool = Journal.dex_fish.has(f.id)
		var cell: Button = _cell(f.id, f.display_name if known else "???", not known, ("%d마리" % Journal.dex_fish[f.id]) if known else "")
		if f.rarity in ["rare", "legendary"]:
			cell.add_theme_stylebox_override("normal", EventHud._box(Color(1, 1, 1, 0.75), RARITY_COLOR[f.rarity], 18, 3, 6))
		grid.add_child(cell)


func _fish_detail(f: FishInfo) -> void:
	var c: VBoxContainer = card()
	var known: bool = Journal.dex_fish.has(f.id)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	c.add_child(top)
	top.add_child(item_chip(f.id, 128.0, not known))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(col)
	col.add_child(label(f.display_name if known else "아직 못 낚은 물고기", 36, INK))
	col.add_child(label("%s · 크기 %s" % [RARITY.get(f.rarity, f.rarity), SIZE.get(f.size, f.size)], 24, RARITY_COLOR.get(f.rarity, SOFT)))
	if known:
		col.add_child(label("낚은 수 %d마리%s" % [Journal.dex_fish[f.id], " · 박물관에 있어요" if Net.museum_fish.has(f.id) else ""], 24, GOOD))
	if known and not f.description.is_empty():
		c.add_child(label(f.description, 24, SOFT))
	# 언제 · 어디서 (힌트는 못 낚은 물고기도 보여 준다).
	c.add_child(label("어디서: %s" % ", ".join(GameData.fish_places(f.id)), 24, INK))
	c.add_child(label("언제: %s · %s · %s" % [_hours_text(f.hours), _seasons_text(f.seasons), _weather_text(f.weathers)], 24, INK))
	var info: ItemInfo = GameData.item(f.id)
	if known and info != null and info.price > 0:
		c.add_child(label("상점에 팔면 %s" % Money.short(info.price), 24, SOFT))


static func _hours_text(hours: PackedInt32Array) -> String:
	if hours.size() != 2:
		return "하루 종일"
	return "%d시 ~ %d시" % [hours[0], hours[1]]


static func _seasons_text(seasons: PackedStringArray) -> String:
	if seasons.is_empty():
		return "사계절"
	var names: PackedStringArray = []
	for s: String in seasons:
		names.append(VillageClock.season_name(s))
	return " · ".join(names)


static func _weather_text(weathers: PackedStringArray) -> String:
	if weathers.is_empty():
		return "날씨 상관없음"
	var names: PackedStringArray = []
	for w: String in weathers:
		names.append(WEATHER.get(w, w))
	return "%s일 때" % " · ".join(names)


# ---- 가구 · 옷 ----

func _build_items() -> void:
	var groups: Array[Array] = [["furniture", "가구"], ["clothing", "옷"]]
	if not _picked.is_empty() and GameData.item(_picked) != null:
		_item_detail(GameData.item(_picked))
	for g: Array in groups:
		var ids: PackedStringArray = []
		for item: ItemInfo in GameData.items.values():
			if item.kind == str(g[0]):
				ids.append(item.id)
		var have: int = 0
		for id: String in ids:
			if id in Journal.dex_items:
				have += 1
		var head: VBoxContainer = card()
		head.add_child(label("%s %d / %d" % [str(g[1]), have, ids.size()], 32, INK))
		head.add_child(meter(float(have) / maxf(1.0, float(ids.size())), Color("#E8A04A")))
		var grid: GridContainer = _grid()
		for id: String in ids:
			var known: bool = id in Journal.dex_items
			grid.add_child(_cell(id, GameData.item_name(id) if known else "???", not known, ""))
	add_child(label("가방에 넣거나 입거나 마을에 놓아 본 가구 · 옷이 도감에 올라요.", 22, SOFT))


func _item_detail(item: ItemInfo) -> void:
	var known: bool = item.id in Journal.dex_items
	var c: VBoxContainer = card()
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	c.add_child(top)
	top.add_child(item_chip(item.id, 128.0, not known))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(col)
	col.add_child(label(item.display_name if known else "아직 모은 적 없어요", 34, INK))
	if known and not item.description.is_empty():
		col.add_child(label(item.description, 24, SOFT))
	if item.buy_price > 0:
		col.add_child(label("상점 값 %s" % Money.short(item.buy_price), 24, SOFT))


# ---- 박물관 ----

func _build_museum() -> void:
	var total: int = GameData.fish.size()
	var donated: int = Net.museum_fish.size()
	var mine: int = 0
	for id: String in Net.museum_fish:
		if Net.museum_fish[id] == Net.my_id:
			mine += 1
	var head: VBoxContainer = card()
	head.add_child(label("박물관 수족관 %d / %d 종" % [donated, total], 34, INK))
	head.add_child(meter(float(donated) / maxf(1.0, float(total)), Color("#4C8FE0")))
	head.add_child(label("내가 기증한 물고기 %d 종 · 마을 친구와 함께 채워요" % mine, 24, SOFT))
	var missing: PackedStringArray = []
	for f: FishInfo in GameData.fish.values():
		if not Net.museum_fish.has(f.id) and Journal.dex_fish.has(f.id):
			missing.append(f.display_name)
	if not missing.is_empty():
		var hint: VBoxContainer = card()
		hint.add_child(label("낚아 봤지만 아직 기증하지 않은 물고기", 28, INK))
		hint.add_child(label(", ".join(missing), 24, GOOD))
	for f: FishInfo in GameData.fish.values():
		if not Net.museum_fish.has(f.id):
			continue
		var row: Button = row_button(96.0)
		var line: HBoxContainer = fill_row(row)
		line.add_child(item_chip(f.id, 72.0))
		var name_label: Label = label(f.display_name, 28, INK, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_label)
		var by: int = Net.museum_fish[f.id]
		var by_label: Label = label("나" if by == Net.my_id else GameData.player_name(by), 24, SOFT, false)
		by_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(by_label)
		row.pressed.connect(func() -> void:
			_tab = 0
			_picked = f.id
			_build())
		add_child(row)


# ---- 칸 ----

func _grid() -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	return grid


## 그림 + 이름 (+ 아래 작은 글) 칸. 누르면 위에 자세히.
func _cell(id: String, title: String, dim: bool, sub: String) -> Button:
	var b: Button = row_button(196.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.name = "Dex_%s" % id
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var chip: Control = item_chip(id, 104.0, dim)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)
	var name_label: Label = label(title, 22, INK if not dim else SOFT, false)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	if not sub.is_empty():
		var s: Label = label(sub, 18, GOOD, false)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	b.pressed.connect(func() -> void:
		_picked = "" if _picked == id else id
		Audio.play_ui(Audio.SFX_CLICK)
		_build()
		if phone != null:
			phone.scroll_to_top())
	return b
