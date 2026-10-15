class_name DropField
extends Node3D
## 바닥의 협회 보급품 꾸러미(낙하산 단 군용 상자, v0.28)와 마나 결정 조각(밤에 푸르게 빛남), 들판의 먹거리(나물·버섯·산딸기 덤불). 위치는 서버가 정하고,
## 가까이 가서 "줍기"·"채집"으로 줍는다. 보급품은 낙하산에 매달려 살랑살랑, 마나 조각은 빙글빙글 돌며 반짝이고,
## 먹거리는 풀숲 위로 아이템 모형이 살짝 흔들린다. 생길 때와 없어질 때 톡 튀는 연출.
## 사람이 내려놓은 물건(v13)은 그 아이템 모형을 손바닥만 하게 줄여 바닥에 둔다 (여러 개면 작게 쌓인다).
## v0.28.1: 가까이(GLOW_RANGE) 가면 주울 수 있는 것의 테두리가 노랗게 빛나며 숨쉰다 (material_overlay — 뒤집은 껍질 한 겹).

@export var clay_material: Material
## 밤에 빛나는 조각 머티리얼 (마나 조각은 이것을 푸르게 바꿔 쓴다).
@export var glow_material: Material

## 보급품 상자 색 (국방 · 모래 · 회청 · 올리브) · 낙하산 색.
const GIFT_COLORS: Array[Color] = [Color("#5E6B3A"), Color("#B8A070"), Color("#5A6A78"), Color("#7A7A48")]
const CHUTE_COLORS: Array[Color] = [Color("#F08A2C"), Color("#F4F0E8"), Color("#E8483A"), Color("#F0C040")]

static var _gift_meshes: Dictionary[int, ArrayMesh] = {}
static var _star: ArrayMesh = null
static var _mana_glow: Material = null
static var _forage: Dictionary[String, ArrayMesh] = {}
static var _sack: ArrayMesh = null
static var _shadow_material: StandardMaterial3D = null

## 내려놓은 물건 모형의 가장 긴 변 (m).
const ITEM_SIZE: float = 0.42
## 테두리가 빛나는 거리 (m) · 빛 색.
const GLOW_RANGE: float = 3.5
const GLOW_COLOR: Color = Color("#FFE45A")
static var _outline: StandardMaterial3D = null
## 지금 테두리가 켜진 것.
var _lit: Dictionary[String, bool] = {}

var _nodes: Dictionary[String, Node3D] = {}
var _time: float = 0.0


func _ready() -> void:
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync_all())
	Net.drop_added.connect(func(d: DropInfo) -> void: _add(d, true))
	Net.drop_removed.connect(_remove)
	Net.drop_changed.connect(_on_drop_changed)
	_sync_all()


## 주울 수 있는 것의 이름 (머리 위 이름표에 쓴다). 내려놓은 묶음은 "목재 ×3".
static func label_of(d: DropInfo) -> String:
	if d == null:
		return ""
	match d.kind:
		DropInfo.KIND_GIFT:
			return "협회 보급품"
		DropInfo.KIND_STAR:
			return GameData.item_name(d.item) if not d.item.is_empty() else "마나 결정 조각"
	var name: String = GameData.item_name(d.item) if GameData.item(d.item) != null else GameData.fish_name(d.item)
	return "%s ×%d" % [name, d.count] if d.count > 1 else name


## 이름표를 띄울 높이 (모형 꼭대기 조금 위).
func label_height(id: String) -> float:
	var n: Node3D = _nodes.get(id)
	if n == null:
		return 0.8
	match str(n.get_meta("kind", "")):
		DropInfo.KIND_GIFT:
			return 2.15
		DropInfo.KIND_ITEM:
			return 0.75
	return 0.85


## 주울 수 있는 가장 가까운 것 (max_distance 안). 없으면 빈 문자열.
func nearest(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		var d: float = Vector2(position.x - n.global_position.x, position.z - n.global_position.z).length()
		if d <= best_d:
			best_d = d
			best = id
	return best


func has_drop(id: String) -> bool:
	return _nodes.has(id)


func drop_position(id: String) -> Vector3:
	var n: Node3D = _nodes.get(id)
	return n.global_position if n != null else Vector3.ZERO


func _process(delta: float) -> void:
	_time += delta
	_update_glow()
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		var phase: float = float(id.hash() % 100) * 0.1
		var visual: Node3D = n.get_child(0)
		var kind: String = n.get_meta("kind", "")
		if kind == DropInfo.KIND_STAR:
			visual.rotation.y = _time * 1.6 + phase
			visual.position.y = 0.15 + sin(_time * 2.4 + phase) * 0.06
		elif kind == DropInfo.KIND_FORAGE:
			visual.rotation.z = sin(_time * 1.1 + phase) * 0.05
		elif kind == DropInfo.KIND_ITEM:
			pass
		else:
			visual.rotation.z = sin(_time * 1.3 + phase) * 0.08
			visual.position.y = sin(_time * 1.7 + phase) * 0.05


func _sync_all() -> void:
	for id: String in _nodes.keys():
		if not Net.drops.has(id):
			_remove(id, 0)
	for d: DropInfo in Net.drops.values():
		if not _nodes.has(d.id):
			_add(d, false)


func _add(d: DropInfo, animate: bool) -> void:
	if _nodes.has(d.id):
		return
	var root: Node3D = Node3D.new()
	root.name = "Drop_%s" % d.id
	root.set_meta("kind", d.kind)
	add_child(root)
	root.global_position = d.position
	var mi: MeshInstance3D = MeshInstance3D.new()
	if d.kind == DropInfo.KIND_STAR:
		mi.mesh = star_mesh(d.item)
		mi.material_override = _mana_material(glow_material) if d.item.begins_with("mana") else glow_material
	elif d.kind == DropInfo.KIND_ITEM:
		_build_item(mi, d)
	elif d.kind == DropInfo.KIND_FORAGE:
		mi.mesh = forage_mesh()
		mi.material_override = clay_material
		var info: ItemInfo = GameData.item(d.item)
		if info != null and not info.model.is_empty():
			var crop: MeshInstance3D = MeshInstance3D.new()
			crop.mesh = PartMesh.get_mesh(info.id, info.model)
			crop.material_override = clay_material
			crop.scale = Vector3(1.8, 1.8, 1.8)
			crop.position = Vector3(0.0, 0.14, 0.0)
			mi.add_child(crop)
	else:
		mi.mesh = gift_mesh(absi(d.id.hash()) % GIFT_COLORS.size())
		mi.material_override = clay_material
	root.add_child(mi)
	_nodes[d.id] = root
	if animate:
		root.scale = Vector3(0.2, 0.2, 0.2)
		var tween: Tween = create_tween()
		if d.kind == DropInfo.KIND_ITEM:
			# 손에서 툭 떨어져 한 번 통 튄다.
			mi.position.y = 0.9
			tween.set_parallel(true)
			tween.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(mi, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			Audio.play_at("emote_pop", d.position, -6.0)
		elif d.kind == DropInfo.KIND_GIFT:
			# 낙하산이 하늘에서 내려앉는다.
			mi.position.y = 6.0
			tween.set_parallel(true)
			tween.tween_property(root, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(mi, "position:y", 0.0, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(root, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Audio.play_at("twinkle", d.position, -4.0)


## 일부만 주워 개수가 줄었다: 쌓인 모양을 다시 만든다.
func _on_drop_changed(d: DropInfo) -> void:
	var n: Node3D = _nodes.get(d.id)
	if n == null:
		_add(d, false)
		return
	_build_item(n.get_child(0) as MeshInstance3D, d)
	# 새로 만든 모형에도 테두리를 다시 입힌다.
	_lit.erase(d.id)


## 내려놓은 물건: 아이템 모형(물고기는 물고기 모형)을 ITEM_SIZE 에 맞춰 줄이고, 여러 개면 2~3개를 겹쳐 쌓는다.
## 바닥에 옅은 그림자 원을 깐다.
func _build_item(mi: MeshInstance3D, d: DropInfo) -> void:
	for c: Node in mi.get_children():
		c.queue_free()
	mi.mesh = null
	var mesh: Mesh = null
	var material: Material = clay_material
	var info: ItemInfo = GameData.item(d.item)
	var fish: FishInfo = GameData.fish.get(d.item)
	if fish != null:
		mesh = FishModel.mesh(fish)
		material = FishModel.material(fish, clay_material)
	elif info != null and not info.model.is_empty():
		mesh = PartMesh.get_mesh(info.id, info.model)
		material = PartMesh.material_for(info.id, clay_material)
	if mesh == null:
		mesh = sack_mesh()
	var aabb: AABB = mesh.get_aabb()
	var longest: float = maxf(aabb.size[aabb.get_longest_axis_index()], 0.01)
	var fit: float = clampf(ITEM_SIZE / longest, 0.15, 2.5)
	var copies: int = clampi(d.count, 1, 3)
	for i: int in copies:
		var part: MeshInstance3D = MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = material
		part.scale = Vector3.ONE * fit * (1.0 if i == 0 else 0.9)
		# 모형 바닥을 땅에 붙이고, 겹친 것은 살짝 비켜 얹는다.
		var lift: float = -aabb.position.y * part.scale.y
		part.position = Vector3(0.09 * i * (1.0 if i % 2 == 1 else -1.0), lift + aabb.size.y * part.scale.y * 0.45 * i, 0.05 * i)
		part.rotation.y = float(absi(d.id.hash()) % 628) * 0.01 + i * 0.9
		if fish != null:
			# 물고기 모형은 옆모습이 XY 평면이다 → 옆으로 눕혀 바닥에 둔다.
			part.rotation.x = -PI * 0.5
			part.position.y = aabb.size.z * part.scale.z * 0.5 + 0.01 + 0.07 * i
		mi.add_child(part)
	var shadow: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = ITEM_SIZE * 0.62
	disc.bottom_radius = ITEM_SIZE * 0.62
	disc.height = 0.005
	disc.radial_segments = 20
	disc.rings = 1
	shadow.mesh = disc
	shadow.material_override = _shadow()
	shadow.position.y = 0.012
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(shadow)


static func _shadow() -> StandardMaterial3D:
	if _shadow_material == null:
		_shadow_material = StandardMaterial3D.new()
		_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_material.albedo_color = Color(0.1, 0.08, 0.04, 0.22)
	return _shadow_material


## 모형이 없는 물건: 작은 보따리.
static func sack_mesh() -> ArrayMesh:
	if _sack != null:
		return _sack
	var st: SurfaceTool = ClayMesh.begin()
	var cloth: Color = Color("#E9C98F")
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.16, 0.0), Vector3(0.2, 0.16, 0.2), ClayMesh.vertical_gradient(cloth.darkened(0.15), cloth.lightened(0.1), 1.0), 12, 8)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.33, 0.0), Vector3(0.07, 0.05, 0.07), Color("#C9A26A"), 8, 4)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.29, 0.0), Vector3(0.09, 0.025, 0.09), Color("#B5523B"), 10, 3)
	_sack = ClayMesh.commit(st)
	return _sack


func _remove(id: String, _by: int) -> void:
	var n: Node3D = _nodes.get(id)
	if n == null:
		return
	_nodes.erase(id)
	var tween: Tween = create_tween()
	tween.tween_property(n, "scale", Vector3(1.3, 1.3, 1.3), 0.08)
	tween.tween_property(n, "scale", Vector3(0.01, 0.01, 0.01), 0.18)
	tween.tween_callback(n.queue_free)


## 협회 보급품 꾸러미 (v0.28): 끈으로 묶은 군용 상자 + 줄에 매단 작은 낙하산 (색 4가지).
static func gift_mesh(color_index: int) -> ArrayMesh:
	if _gift_meshes.has(color_index):
		return _gift_meshes[color_index]
	var st: SurfaceTool = ClayMesh.begin()
	var box: Color = GIFT_COLORS[color_index]
	var strap: Color = Color("#2C2F26")
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.2, 0.0), Vector3(0.48, 0.36, 0.38), 0.2, ClayMesh.vertical_gradient(box.darkened(0.15), box.lightened(0.08), 1.0), Basis(), 10, 6)
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.39, 0.0), Vector3(0.52, 0.06, 0.42), 0.3, box.darkened(0.2), Basis(), 10, 4)
	for x: float in [-0.14, 0.14]:
		ClayMesh.add_box(st, Vector3(x, 0.21, 0.0), Vector3(0.06, 0.4, 0.4), strap)
	ClayMesh.add_box(st, Vector3(0.0, 0.26, 0.0), Vector3(0.5, 0.05, 0.4), Color("#E8C23A"))
	ClayMesh.add_box(st, Vector3(0.0, 0.2, 0.191), Vector3(0.12, 0.12, 0.01), Color("#F4F0E8"))
	var chute: Color = CHUTE_COLORS[color_index]
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		ClayMesh.add_capsule(st, Vector3(corner.x * 0.2, 0.42, corner.z * 0.15), Vector3(corner.x * 0.4, 1.42, corner.z * 0.4), 0.007, Color("#E8E4DA"), 4, 1)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 1.5, 0.0), Vector3(0.56, 0.2, 0.56), ClayMesh.vertical_gradient(chute.darkened(0.15), chute.lightened(0.15), 1.0), 12, 6)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 1.56, 0.0), Vector3(0.26, 0.12, 0.26), Color("#F4F0E8") if color_index != 1 else Color("#F08A2C"), 10, 4)
	_gift_meshes[color_index] = ClayMesh.commit(st)
	return _gift_meshes[color_index]


## 들판의 먹거리 덤불: 둥글게 펼친 잎 (위에 아이템 모형을 따로 얹는다).
static func forage_mesh() -> ArrayMesh:
	if _forage.has("bush"):
		return _forage["bush"]
	var st: SurfaceTool = ClayMesh.begin()
	var leaf: Callable = ClayMesh.vertical_gradient(Color("#4F8A3C"), Color("#8CC66A"), 1.0)
	for i: int in 7:
		var a: float = TAU * float(i) / 7.0
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		ClayMesh.add_ellipsoid(st, out * 0.16 + Vector3(0.0, 0.1 + 0.03 * float(i % 3), 0.0), Vector3(0.06, 0.13, 0.035), leaf, 6, 4, Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, 0.55))
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.04, 0.0), Vector3(0.2, 0.06, 0.2), Color("#5E8E44"), 10, 4)
	_forage["bush"] = ClayMesh.commit(st)
	return _forage["bush"]


## 하늘에서 떨어진 조각: 그 아이템 모형 (마나 결정 조각 · 옛 별 조각).
static func star_mesh(item_id: String = "mana_shard") -> ArrayMesh:
	if _star == null or str(_star.get_meta("item", "")) != item_id:
		var info: ItemInfo = GameData.item(item_id if GameData.item(item_id) != null else "mana_shard")
		_star = PartMesh.build(info.model if info != null else [])
		_star.set_meta("item", item_id)
	return _star


## 마나 조각: 별빛 머티리얼을 푸르게 (같은 셰이더).
static func _mana_material(base: Material) -> Material:
	if _mana_glow == null and base is ShaderMaterial:
		var m: ShaderMaterial = (base as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("albedo", Color(0.75, 0.95, 1.0))
		m.set_shader_parameter("emission", Color(0.25, 0.8, 1.0))
		m.set_shader_parameter("emission_energy", 2.2)
		_mana_glow = m
	return _mana_glow if _mana_glow != null else base


# ---- v0.28.1 가까이 가면 빛나는 테두리 ----

## 뒤집은 껍질 한 겹 (앞면을 버리고 조금 부풀려, 모형 둘레만 빛난다). 모두 같은 머티리얼이라 함께 숨쉰다.
static func outline_material() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.025
		_outline.albedo_color = GLOW_COLOR
	return _outline


## 이 물건의 테두리가 켜져 있는지 (테스트용).
func is_glowing(id: String) -> bool:
	return _lit.has(id)


func _update_glow() -> void:
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	var pos: Vector3 = player.global_position
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		var near: bool = Vector2(pos.x - n.global_position.x, pos.z - n.global_position.z).length() <= GLOW_RANGE
		if near != _lit.has(id):
			if near:
				_lit[id] = true
			else:
				_lit.erase(id)
			_set_overlay(n, outline_material() if near else null)
	for id: String in _lit.keys():
		if not _nodes.has(id):
			_lit.erase(id)
	if not _lit.is_empty():
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		var m: StandardMaterial3D = outline_material()
		m.grow_amount = 0.03 + pulse * 0.025
		m.albedo_color = GLOW_COLOR.lerp(Color.WHITE, pulse * 0.45)


func _set_overlay(n: Node, m: Material) -> void:
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		# 바닥 그림자 원은 빼고.
		if mi.mesh is CylinderMesh:
			continue
		mi.material_overlay = m
