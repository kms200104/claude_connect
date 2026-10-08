class_name VehicleApp
extends PhoneApp
## 탈것 · 차고 (v19): 자전거 · 전기오토바이 매장(실제 시세에 가까운 값)과 내 차고(어디 있는지 · 부르기), 꾸미기.
## 부르면 동네 주민이 타고 와서 내 곁에 세워 두고 간다 (GarageRider.call_vehicle).
## 꾸미기는 칸(도색 · 포인트 색 · 전조등 · 미등 · 빛 장식 · 구동 · 브레이크 · 타이어 · 시트 · 앞/뒤 장착 · 장식)마다 부품을 골라
## 처음이면 사서 끼우고, 산 부품은 공짜로 다시 끼운다. 위에서 3D 미리보기가 돌며 끼운 모양을 바로 보여 준다 (밤이면 전조등 · 빛 장식도).
## 사기 · 끼우기 · 팔기 · 타기는 서버가 정한다 (Net.request → veh_result · veh_ride).

const BIKE: Color = Color("#2FA0A8")
const SPEED: Color = Color("#E8594A")
const ACCEL: Color = Color("#F2B53A")
const BRAKE_C: Color = Color("#4C8FE0")
## 막대 그래프 끝 (가장 빠른 오토바이 + 업그레이드 여유).
const TOP_MAX: float = 19.0
const ACCEL_MAX: float = 6.5
const BRAKE_MAX: float = 11.0

enum Mode { SHOP, GARAGE, MODEL, CUSTOM }

var _mode: Mode = Mode.SHOP
## 매장에서 들여다보는 모델 · 꾸미는 내 탈것.
var _model_id: String = ""
var _vehicle_id: String = ""
var _slot: String = "paint"
## 사기 · 팔기는 한 번 더 눌러 확인한다 (그 단추 id).
var _confirm: String = ""
var _note: String = ""
var _note_good: bool = true
var _preview: SubViewport = null
var _preview_model: VehicleModel = null
var _preview_pivot: Node3D = null


func _ready() -> void:
	_mode = Mode.GARAGE if not Net.vehicles.is_empty() else Mode.SHOP
	_build()
	Net.vehicles_changed.connect(_rebuild)
	Net.vehicle_done.connect(_on_done)
	Net.request_failed.connect(_on_failed)
	Net.mount_changed.connect(func(_m: Dictionary) -> void: _rebuild())
	Net.parked_changed.connect(func() -> void:
		if _mode == Mode.GARAGE:
			_rebuild())


func _process(delta: float) -> void:
	if _preview_pivot != null and is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y += delta * 0.6


func go_back() -> bool:
	match _mode:
		Mode.MODEL:
			_mode = Mode.SHOP
		Mode.CUSTOM:
			_mode = Mode.GARAGE
		_:
			return false
	_confirm = ""
	_build()
	return true


func _rebuild() -> void:
	if is_inside_tree():
		_build.call_deferred()


func _rider() -> GarageRider:
	return get_tree().get_first_node_in_group(&"garage_rider") as GarageRider if is_inside_tree() else null


func _on_done(result: Dictionary) -> void:
	var kind: String = str(result.get("kind", ""))
	var cost: int = int(result.get("cost", 0))
	match kind:
		"call":
			return
		"buy":
			var m: VehicleCatalog.Model = GameData.garage.model(str(result.get("model", "")))
			_note = "%s 을(를) 샀어요! 차고에 넣어 뒀어요 (%s)." % [m.name if m != null else "탈것", Money.short(cost)]
			_mode = Mode.CUSTOM
			_vehicle_id = str(result.get("v", ""))
			_slot = "paint"
			Audio.play_sfx("coin", -4.0)
		"part":
			var p: VehicleCatalog.Part = GameData.garage.part(str(result.get("part", "")))
			_note = ("%s 끼웠어요 (%s)." % [p.name, Money.short(cost)]) if cost > 0 else "%s 다시 끼웠어요." % (p.name if p != null else "")
		"unfit":
			_note = "기본 부품으로 돌렸어요."
		"sell":
			_note = "중고로 팔았어요 (+%s)." % Money.short(-cost)
			_mode = Mode.GARAGE
	_note_good = true
	_confirm = ""
	_rebuild()


func _on_failed(kind: String, code: String) -> void:
	if not kind.begins_with("veh_"):
		return
	_note_good = false
	match code:
		NetProtocol.ERR_NOT_ENOUGH_SOL:
			_note = "솔이 모자라요."
		NetProtocol.ERR_GARAGE_FULL:
			_note = "차고가 가득 찼어요 (%d대). 한 대를 팔아야 해요." % GameData.garage.max_owned
		NetProtocol.ERR_CANT_RIDE:
			_note = "지금은 탈 수 없어요 (실내 · 낚시 중)."
		_:
			_note = "할 수 없어요 (%s)." % code
	_rebuild()


func _build() -> void:
	clear()
	_preview = null
	_preview_model = null
	_preview_pivot = null
	if _mode == Mode.SHOP or _mode == Mode.GARAGE:
		tabs(PackedStringArray(["매장", "내 차고 (%d)" % Net.vehicles.size()]), 0 if _mode == Mode.SHOP else 1, func(i: int) -> void:
			_mode = Mode.SHOP if i == 0 else Mode.GARAGE
			_confirm = ""
			_build())
	if not _note.is_empty():
		var n: Label = label(_note, 26, GOOD if _note_good else WARN)
		n.name = "Note"
		add_child(n)
		_note = ""
	match _mode:
		Mode.SHOP:
			_build_shop()
		Mode.GARAGE:
			_build_garage()
		Mode.MODEL:
			_build_model()
		Mode.CUSTOM:
			_build_custom()


# ---- 매장 ----

func _build_shop() -> void:
	var head: VBoxContainer = card()
	head.add_child(label("솔바람 모빌리티", 34, INK))
	head.add_child(label("자전거 · 전기오토바이를 실제 시세에 가깝게 팔아요. 사면 차고에 들어가고, HUD 의 탈것 단추로 바로 탈 수 있어요.", 24, SOFT))
	head.add_child(label("가진 솔 %s · 차고 %d / %d" % [Money.short(Net.sol), Net.vehicles.size(), GameData.garage.max_owned], 26, INK))
	for kind: String in ["bike", "moto"]:
		add_child(label(GameData.garage.kind_name(kind), 30, INK))
		for m: VehicleCatalog.Model in GameData.garage.models:
			if m.kind != kind:
				continue
			var b: Button = row_button(150.0)
			b.name = "Model_%s" % m.id
			var line: HBoxContainer = fill_row(b)
			var col: VBoxContainer = VBoxContainer.new()
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(col)
			col.add_child(label("%s · %s" % [m.name, m.type_name], 28, INK, false))
			col.add_child(label("최고 %d km/h · %s" % [roundi(m.base.top * 3.6), m.spec], 22, SOFT, false))
			var price: Label = label(Money.short(m.price), 28, INK, false)
			price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(price)
			b.pressed.connect(func() -> void:
				Audio.play_ui(Audio.SFX_CLICK)
				_model_id = m.id
				_mode = Mode.MODEL
				_confirm = ""
				_build())
			add_child(b)


func _build_model() -> void:
	var m: VehicleCatalog.Model = GameData.garage.model(_model_id)
	if m == null:
		_mode = Mode.SHOP
		_build()
		return
	_add_preview(m.id, {})
	var c: VBoxContainer = card()
	c.add_child(label(m.name, 34, INK))
	c.add_child(label("%s · %s" % [m.type_name, m.spec], 24, SOFT))
	c.add_child(label(m.desc, 26, INK))
	_add_stats(c, GameData.garage.stats(m.id, {}), null)
	c.add_child(label("값 %s (%s)" % [Money.sol(m.price), Money.short(m.price)], 30, INK))
	var full: bool = Net.vehicles.size() >= GameData.garage.max_owned
	var key: String = "buy:" + m.id
	var buy: Button = button("차고가 가득 찼어요" if full else ("정말 살까요? %s" % Money.short(m.price) if _confirm == key else "사기"), 30, Color.WHITE if not full else INK)
	buy.name = "BuyButton"
	buy.disabled = full or Net.sol < m.price
	if not buy.disabled:
		buy.add_theme_stylebox_override("normal", EventHud._box(BIKE, EDGE, 22, 3, 10))
	if Net.sol < m.price and not full:
		buy.text = "솔이 모자라요 (%s 더 필요)" % Money.short(m.price - Net.sol)
	buy.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		if _confirm != key:
			_confirm = key
			_build()
			return
		_confirm = ""
		Net.request("veh_buy", {"model": m.id}))
	c.add_child(buy)


# ---- 차고 ----

func _build_garage() -> void:
	if Net.vehicles.is_empty():
		var c: VBoxContainer = card()
		c.add_child(label("아직 탈것이 없어요.", 30, INK))
		c.add_child(label("매장에서 자전거나 전기오토바이를 사 보세요.", 24, SOFT))
		return
	var rider: GarageRider = _rider()
	for v: Dictionary in Net.vehicles:
		var id: String = str(v.get("id", ""))
		var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", "")))
		if m == null:
			continue
		var fit: Dictionary = v.get("fit", {}) as Dictionary
		var c: VBoxContainer = card()
		c.get_parent().name = "Vehicle_%s" % id
		var riding: bool = rider != null and rider.is_active() and rider.vehicle_id == id
		c.add_child(label("%s%s" % [m.name, " · 타는 중" if riding else ""], 30, INK))
		var parts: PackedStringArray = []
		for slot: Dictionary in GameData.garage.slots:
			var p: VehicleCatalog.Part = GameData.garage.part(str(fit.get(str(slot.get("id", "")), "")))
			if p != null:
				parts.append(p.name)
		c.add_child(label("꾸밈: %s" % (", ".join(parts) if not parts.is_empty() else "기본 그대로"), 22, SOFT))
		var s: VehicleCatalog.Stats = GameData.garage.stats(m.id, fit)
		c.add_child(label("최고 %d km/h · 가속 %.1f · 브레이크 %.1f" % [roundi(s.top * 3.6), s.accel, s.brake], 22, SOFT))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		c.add_child(row)
		# 어디 있나: 타는 중 · 주민이 가져오는 중 · 세워 둠(거리) · 차고.
		var spot: Dictionary = Net.parked_of(id)
		var coming: bool = not spot.is_empty() and float(spot.get("t", 0.0)) > Net.server_time_ms()
		var where: String = "차고에 있어요"
		if riding:
			where = "타는 중"
		elif coming:
			where = "%s님이 가져오는 중" % GameData.npc_name(str(spot.get("npc", "")))
		elif not spot.is_empty() and phone != null and phone.player != null:
			var d: float = Vector2(float(spot.get("x", 0.0)) - phone.player.global_position.x, float(spot.get("z", 0.0)) - phone.player.global_position.z).length()
			where = "세워 둠 · %dm 떨어져 있어요" % roundi(d)
		c.add_child(label(where, 24, GOOD if riding or coming else SOFT))
		var call: Button = button("타는 중" if riding else ("오는 중" if coming else "부르기"), 28, INK, riding or coming)
		call.name = "Call_%s" % id
		call.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		call.disabled = riding or coming
		call.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			var r: GarageRider = _rider()
			if r != null and r.call_vehicle(id) and phone != null:
				phone.close())
		row.add_child(call)
		var custom: Button = button("꾸미기", 28)
		custom.name = "Custom_%s" % id
		custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			_vehicle_id = id
			_mode = Mode.CUSTOM
			_build())
		row.add_child(custom)
		var owned: PackedStringArray = PackedStringArray(Array(v.get("owned", [])).map(func(x: Variant) -> String: return str(x)))
		var back: int = GameData.garage.resale_value(m.id, owned)
		var key: String = "sell:" + id
		var sell: Button = button("정말 팔까요? +%s" % Money.short(back) if _confirm == key else "팔기", 24, WARN if _confirm == key else SOFT)
		sell.name = "Sell_%s" % id
		sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sell.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			if _confirm != key:
				_confirm = key
				_build()
				return
			_confirm = ""
			Net.request("veh_sell", {"v": id}))
		row.add_child(sell)


# ---- 꾸미기 ----

func _build_custom() -> void:
	var v: Dictionary = Net.vehicle(_vehicle_id)
	var m: VehicleCatalog.Model = GameData.garage.model(str(v.get("model", ""))) if not v.is_empty() else null
	if m == null:
		_mode = Mode.GARAGE
		_build()
		return
	var fit: Dictionary = v.get("fit", {}) as Dictionary
	var owned: Array = v.get("owned", [])
	add_child(label("%s 꾸미기 · 가진 솔 %s" % [m.name, Money.short(Net.sol)], 28, INK))
	_add_preview(m.id, fit)
	var head: VBoxContainer = card()
	_add_stats(head, GameData.garage.stats(m.id, fit), GameData.garage.stats(m.id, {}))
	# 칸 고르기 (네 줄).
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for slot: Dictionary in GameData.garage.slots:
		var sid: String = str(slot.get("id", ""))
		if GameData.garage.parts_for(m.kind, sid).is_empty():
			continue
		var b: Button = button(str(slot.get("name", sid)), 22, INK, sid == _slot)
		b.name = "Slot_%s" % sid
		b.custom_minimum_size = Vector2(0, 70)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			_slot = sid
			_build())
		grid.add_child(b)
	# 기본 부품 (빼기).
	var stock: Button = row_button(90.0)
	stock.name = "Stock"
	var stock_line: HBoxContainer = fill_row(stock)
	var stock_label: Label = label("기본 (부품 없음)", 26, INK, false)
	stock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_line.add_child(stock_label)
	stock_line.add_child(label("끼움" if not fit.has(_slot) else "", 24, GOOD, false))
	stock.disabled = not fit.has(_slot)
	stock.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		Net.request("veh_unfit", {"v": _vehicle_id, "slot": _slot}))
	add_child(stock)
	for p: VehicleCatalog.Part in GameData.garage.parts_for(m.kind, _slot):
		add_child(_part_row(p, m.kind, fit, owned))


func _part_row(p: VehicleCatalog.Part, kind: String, fit: Dictionary, owned: Array) -> Button:
	var fitted: bool = str(fit.get(p.slot, "")) == p.id
	var have: bool = p.id in owned
	var price: int = p.price_for(kind)
	var b: Button = row_button(116.0)
	b.name = "Part_%s" % p.id
	var line: HBoxContainer = fill_row(b)
	if p.color.a > 0.0:
		var chip: ColorRect = ColorRect.new()
		chip.color = p.color
		chip.custom_minimum_size = Vector2(56, 56)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(chip)
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)
	col.add_child(label(p.name, 26, INK, false))
	var effect: String = _effect_text(p)
	col.add_child(label(effect if not effect.is_empty() else p.desc, 20, SOFT, false))
	var tag: Label = label("끼움" if fitted else ("가진 부품" if have else Money.short(price)), 24, GOOD if fitted or have else INK, false)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tag)
	b.disabled = fitted or (not have and Net.sol < price)
	b.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		Net.request("veh_part", {"v": _vehicle_id, "part": p.id}))
	return b


## 부품 효과 한 줄 ("최고 속도 +12% · 가속 +20%", "밤길 17m 비춤" …).
static func _effect_text(p: VehicleCatalog.Part) -> String:
	var out: PackedStringArray = []
	var names: Dictionary[String, String] = {"top": "최고 속도", "accel": "가속", "brake": "브레이크", "turn": "회전", "wade": "물가 주행"}
	for k: String in names:
		if p.stats.has(k):
			out.append("%s +%d%%" % [names[k], roundi((p.stats[k] - 1.0) * 100.0)])
	if not p.light.is_empty():
		out.append("밤길 %dm 비춤" % roundi(float(p.light.get("range", 0.0))))
	if not p.glow.is_empty():
		out.append("밤에 빛나요")
	return " · ".join(out)


## 성능 막대 (base 가 있으면 늘어난 만큼 함께).
func _add_stats(parent: VBoxContainer, s: VehicleCatalog.Stats, base: VehicleCatalog.Stats) -> void:
	for row: Array in [["최고 속도", s.top, TOP_MAX, SPEED, "%d km/h" % roundi(s.top * 3.6), base.top if base != null else s.top],
			["가속", s.accel, ACCEL_MAX, ACCEL, "%.1f m/s²" % s.accel, base.accel if base != null else s.accel],
			["브레이크", s.brake, BRAKE_MAX, BRAKE_C, "%.1f m/s²" % s.brake, base.brake if base != null else s.brake]]:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		parent.add_child(line)
		var name_label: Label = label(str(row[0]), 22, INK, false)
		name_label.custom_minimum_size = Vector2(130, 0)
		line.add_child(name_label)
		var bar: Control = meter(float(row[1]) / float(row[2]), row[3])
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		var gain: float = float(row[1]) - float(row[5])
		line.add_child(label("%s%s" % [row[4], " (+%d%%)" % roundi(gain / maxf(float(row[5]), 0.01) * 100.0) if gain > 0.001 else ""], 22, GOOD if gain > 0.001 else SOFT, false))


## 돌아가는 3D 미리보기 (휴대폰 화면 안 작은 무대).
func _add_preview(model_id: String, fit: Dictionary) -> void:
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.name = "Preview"
	holder.stretch = true
	holder.custom_minimum_size = Vector2(0, 380)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = false
	_preview.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_preview)
	# 마을이 밤이면 미리보기도 밤 (빛나는 부품은 마을의 밤 조명 값으로 빛난다).
	var night: bool = SkyController.night_light > 0.5
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.2) if night else Color(0.93, 0.9, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.98, 0.92, 0.84)
	env.ambient_light_energy = 0.2 if night else 0.6
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_preview.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 0.1 if night else 1.0
	_preview.add_child(sun)
	# 받침 (점토 머티리얼 하나로 — 셰이더를 늘리지 않는다).
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_lathe(st, ClayMesh.rounded_cylinder_profile(1.3, 1.3, -0.04, 0.0, 0.02, 1), 32, Transform3D(), Color(0.82, 0.78, 0.72))
	floor_mesh.mesh = ClayMesh.commit(st)
	floor_mesh.material_override = load("res://assets/materials/foliage.tres")
	_preview.add_child(floor_mesh)
	_preview_pivot = Node3D.new()
	_preview_pivot.rotation.y = deg_to_rad(-60.0)
	_preview.add_child(_preview_pivot)
	_preview_model = VehicleModel.new()
	_preview_pivot.add_child(_preview_model)
	_preview_model.build(model_id, fit)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 36.0
	_preview.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.3, 2.9), Vector3(0.0, 0.4, 0.0))
