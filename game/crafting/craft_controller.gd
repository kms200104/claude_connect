class_name CraftController
extends Node
## 제작 (v0.22): 공용 작업대(주민 공구 창고) 건물을 세우고, 작업대 곁에서 상황 버튼 "작업대" → 제작 창(CraftWindow).
## 가방의 "제작" 단추로도 연다 (그 자리 등급 — 맨손이면 밧줄 · 붕대 · 횃불 · 작업대 같은 기본만).
## 작업대: 공용(data/crafting/crafting.json public_benches, 2등급) · 내가 만든 작업대 가구(마을에 놓거나 집 안에 두면 1등급).
## 판정은 서버. 만들면 토닥토닥 몸짓 + 토스트, 거절되면 이유.

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var clay_material: Material
@export var inventory_window: InventoryWindow

const TARGET_PUBLIC: String = "public:"
const TARGET_PLACED: String = "placed:"
const TARGET_HOME: String = "home"

var window: CraftWindow = null


func _ready() -> void:
	window = CraftWindow.new()
	if hud != null:
		hud.add_child.call_deferred(window)
	for b: CraftingRules.Bench in GameData.crafting.benches:
		_build_shed(b)
	Net.crafted.connect(_on_crafted)
	Net.request_failed.connect(_on_failed)
	if inventory_window != null:
		inventory_window.craft_requested.connect(func() -> void: open_here())


func is_busy() -> bool:
	return window != null and window.is_open()


## 지금 자리의 작업대 등급 (집 안이면 그 집 가구).
func tier_here() -> int:
	return GameData.crafting.tier_at(player.global_position, _placed_list(), _home_items(), Home.is_inside())


## 가방 "제작" 단추: 그 자리 등급으로 연다.
func open_here() -> void:
	window.open(tier_here())


## 상황 버튼 대상: 공용 작업대 · 마을에 놓인 작업대 · 작업대가 있는 집 안. 없으면 빈 글자.
func pick_target(position: Vector3, margin: float = 0.3) -> String:
	var rules: CraftingRules = GameData.crafting
	if Home.is_inside():
		for item: String in _home_items():
			if rules.bench_items.has(item):
				return TARGET_HOME
		return ""
	for b: CraftingRules.Bench in rules.benches:
		if _flat(position, b.position) <= rules.range_m - margin:
			return TARGET_PUBLIC + b.id
	for f: PlacedInfo in Net.placed.values():
		if rules.bench_items.has(f.item) and _flat(position, f.position) <= rules.range_m - margin:
			return TARGET_PLACED + f.id
	return ""


func target_label(target: String) -> String:
	return "공구 창고" if target.begins_with(TARGET_PUBLIC) else "작업대"


func activate(target: String) -> void:
	var own: String = ""
	if target.begins_with(TARGET_PLACED):
		var f: PlacedInfo = Net.placed.get(target.trim_prefix(TARGET_PLACED))
		if f != null and f.owner == Net.my_id:
			own = f.id
	window.open(tier_here(), own)


func _placed_list() -> Array[Array]:
	var out: Array[Array] = []
	for f: PlacedInfo in Net.placed.values():
		out.append([f.item, f.position])
	return out


func _home_items() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if Home.is_inside():
		for f: Home.Furniture in Home.furniture:
			out.append(f.item)
	return out


func _on_crafted(info: Dictionary) -> void:
	if player != null:
		player.play_plant()
	Audio.play_sfx("quest_done", -8.0)
	if toast_hud != null:
		toast_hud.show_toast("%s × %d 을(를) 만들었어요" % [GameData.item_name(str(info.get("item", ""))), int(info.get("n", 1))], true)


func _on_failed(kind: String, code: String) -> void:
	if kind != "craft" or toast_hud == null:
		return
	if window != null and window.is_open():
		window.open(window.tier, window.own_bench)
	var msg: String = {
		NetProtocol.ERR_NOT_AT_BENCH: "더 좋은 작업대 곁에서 만들 수 있어요",
		NetProtocol.ERR_NOT_ENOUGH_ITEMS: "재료가 모자라요",
		NetProtocol.ERR_INVENTORY_FULL: "가방이 가득 찼어요",
	}.get(code, code)
	toast_hud.show_toast(msg, false)


## 주민 공구 창고: 콘크리트 바닥 · 뒷벽 공구판(망치 · 톱 · 렌치) · 지붕 · 기둥 · 앞 작업대(바이스 · 공구함) · 간판.
func _build_shed(b: CraftingRules.Bench) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Bench_%s" % b.id
	var world: Node = player.get_parent() if player != null else self
	world.add_child.call_deferred(root)
	root.position = b.position
	root.rotation.y = b.yaw
	var clay: BoxBatch = BoxBatch.new()
	var wood: Color = Color("#9A6A40")
	var wood_dark: Color = Color("#7A4E30")
	var metal: Color = Color("#8D959C")
	clay.box(Vector3(0.0, 0.05, -1.0), Vector3(5.4, 0.1, 4.2), Color("#B8B6B0"))
	# 뒷벽 · 옆벽 (반쯤).
	clay.box(Vector3(0.0, 1.5, -2.9), Vector3(5.0, 3.0, 0.2), Color("#C9B79A"))
	for s: float in [-1.0, 1.0]:
		clay.box(Vector3(s * 2.5, 1.5, -1.9), Vector3(0.2, 3.0, 2.2), Color("#C9B79A"))
		clay.box(Vector3(s * 2.45, 1.5, 0.55), Vector3(0.18, 3.0, 0.18), wood_dark)
	# 지붕 (앞으로 기울어진 함석).
	clay.box(Vector3(0.0, 3.15, -1.15), Vector3(5.6, 0.12, 4.0), Color("#5E8F9E"), Basis(Vector3.RIGHT, 0.08))
	# 공구판 + 공구 실루엣.
	clay.box(Vector3(0.0, 1.8, -2.78), Vector3(3.6, 1.4, 0.05), Color("#D9C29A"))
	clay.box(Vector3(-1.2, 1.8, -2.74), Vector3(0.08, 0.7, 0.04), wood_dark)
	clay.box(Vector3(-1.2, 2.1, -2.73), Vector3(0.3, 0.12, 0.05), metal)
	clay.box(Vector3(-0.3, 1.8, -2.74), Vector3(0.7, 0.18, 0.04), metal, Basis(Vector3.BACK, 0.2))
	clay.box(Vector3(0.6, 1.8, -2.74), Vector3(0.1, 0.6, 0.04), metal)
	clay.box(Vector3(1.2, 1.8, -2.74), Vector3(0.5, 0.35, 0.04), Color("#E04B3C"))
	# 작업대 (앞) + 바이스 + 공구함 + 선반 위 통.
	clay.box(Vector3(0.0, 0.85, -0.2), Vector3(2.6, 0.12, 1.0), wood)
	for x: float in [-1.2, 1.2]:
		for z: float in [-0.6, 0.2]:
			clay.box(Vector3(x, 0.42, z), Vector3(0.1, 0.84, 0.1), wood_dark)
	clay.box(Vector3(0.0, 0.3, -0.2), Vector3(2.4, 0.06, 0.9), wood_dark)
	clay.box(Vector3(0.9, 1.0, 0.2), Vector3(0.3, 0.2, 0.25), Color("#3B4046"))
	clay.box(Vector3(-0.7, 1.02, -0.3), Vector3(0.6, 0.22, 0.32), Color("#C0392B"))
	clay.box(Vector3(-1.9, 0.5, -2.2), Vector3(0.6, 1.0, 0.6), Color("#5E8F4E"))
	clay.box(Vector3(1.9, 0.4, -2.3), Vector3(0.7, 0.8, 0.5), Color("#8A7452"))
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = clay.commit()
	mesh.material_override = clay_material
	root.add_child(mesh)
	var body: StaticBody3D = StaticBody3D.new()
	for def: Array in [[Vector3(0.0, 1.5, -2.9), Vector3(5.0, 3.0, 0.3)], [Vector3(-2.5, 1.5, -1.9), Vector3(0.3, 3.0, 2.2)], [Vector3(2.5, 1.5, -1.9), Vector3(0.3, 3.0, 2.2)], [Vector3(0.0, 0.5, -0.2), Vector3(2.6, 1.0, 1.0)]]:
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = def[1]
		shape.shape = box
		shape.position = def[0]
		body.add_child(shape)
	root.add_child(body)
	var sign: Label3D = Label3D.new()
	sign.text = "%s · 공용 작업대" % b.name
	sign.font_size = 56
	sign.pixel_size = 0.008
	sign.outline_size = 12
	sign.modulate = Color("#FFF4DC")
	sign.outline_modulate = Color("#4A3020")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0.0, 3.8, 0.0)
	sign.visibility_range_end = 70.0
	root.add_child(sign)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
