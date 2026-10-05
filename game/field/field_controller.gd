class_name FieldController
extends Node3D
## 들판·물가 일 (v9): 여울(얕은 물) 물고기 떼를 그리고 뜰채로 몰아 뜨기, 삽으로 조개 숨구멍 파기 · 구덩이 파기·메우기 · 흙길 깔기.
## 상황 버튼은 InteractionController 가 pick_target / target_label / activate 로 묻는다. 판정은 서버(Field)가 한다.
## 같이 하면: 여울에 둘이 들어가면 물고기가 우왕좌왕해 느려지고 뜰채가 넓게 뜨며, 숨구멍을 같이 파면 한 번에 두 칸씩 줄고 둘 다 조개를 받는다.

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var clay_material: Material
@export var interaction: InteractionController

const TARGET_NET: String = "net"
const TARGET_CLAM: String = "clam:"
const TARGET_DIG: String = "dig"
const TARGET_FILL: String = "fill"
const TARGET_PATH: String = "path"
const TARGET_UNPATH: String = "unpath"
## 삽 쓰는 법: 구덩이(파기·메우기) / 흙길(깔기·걷기).
enum ShovelMode { HOLE, PATH }

var shovel_mode: ShovelMode = ShovelMode.HOLE
var _mode_button: Button = null
var _marker: MeshInstance3D = null
var _fish_nodes: Dictionary[String, Dictionary] = {}
var _spot_nodes: Dictionary[String, Node3D] = {}
var _hole_mm: MultiMeshInstance3D = null
var _path_mm: MultiMeshInstance3D = null
var _time: float = 0.0
var _busy_until: float = 0.0


func _ready() -> void:
	_hole_mm = _multimesh(_hole_mesh())
	_path_mm = _multimesh(_path_mesh())
	_build_marker()
	_mode_button = Button.new()
	_mode_button.name = "ShovelMode"
	_mode_button.focus_mode = Control.FOCUS_NONE
	_mode_button.add_theme_font_size_override("font_size", 28)
	_mode_button.add_theme_stylebox_override("normal", EventHud._box(Color(0.98, 0.95, 0.88, 0.96), Color(0.5, 0.38, 0.26), 30, 4, 12))
	_mode_button.add_to_group(&"blocks_joystick")
	_mode_button.pressed.connect(func() -> void:
		shovel_mode = ShovelMode.PATH if shovel_mode == ShovelMode.HOLE else ShovelMode.HOLE
		_refresh_mode_button())
	HudLayout.right_top(_mode_button, Vector2(250, 84), 24.0, 1290.0)
	_mode_button.visible = false
	if hud != null:
		hud.add_child.call_deferred(_mode_button)
	_refresh_mode_button()
	Field.shoal_changed.connect(_sync_shoal)
	Field.digspot_added.connect(_add_spot)
	Field.digspot_changed.connect(_update_spot)
	Field.digspot_removed.connect(_remove_spot)
	Field.tile_changed.connect(func(_x: int, _z: int, _s: String) -> void: _rebuild_tiles())
	Field.net_done.connect(_on_net)
	Field.dig_done.connect(_on_dig)
	Field.failed.connect(_on_failed)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync_all())
	_sync_all()


# ---- 상황 버튼 ----

func pick_target(position: Vector3) -> String:
	if player == null or Time.get_ticks_msec() < _busy_until:
		return ""
	var held: String = player.held_item
	if held == "fishing_net" and not Field.zone_at(position, 0.3).is_empty():
		return TARGET_NET
	if held != "shovel":
		return ""
	var spot_range: float = float(GameData.econ.dig.get("spot_range", 1.4))
	var spot: String = Field.nearest_digspot(_ahead(1.0), spot_range)
	if spot.is_empty():
		spot = Field.nearest_digspot(position, spot_range)
	if not spot.is_empty():
		return TARGET_CLAM + spot
	var at: Vector3 = _tile_ahead()
	if not _diggable(at):
		return ""
	var tile: String = Field.tile_at(int(at.x), int(at.z))
	if shovel_mode == ShovelMode.HOLE:
		return TARGET_FILL if tile == Field.TILE_HOLE else (TARGET_DIG if tile.is_empty() else "")
	return TARGET_UNPATH if tile == Field.TILE_PATH else (TARGET_PATH if tile.is_empty() else "")


func target_label(target: String) -> String:
	if target.begins_with(TARGET_CLAM):
		return "조개 캐기"
	return {TARGET_NET: "그물질", TARGET_DIG: "구덩이 파기", TARGET_FILL: "구덩이 메우기", TARGET_PATH: "흙길 깔기", TARGET_UNPATH: "흙길 걷기"}.get(target, "")


func activate(target: String) -> void:
	_busy_until = Time.get_ticks_msec() + 450
	if target == TARGET_NET:
		player.play_chop()
		Audio.play_sfx("fish_plop", -2.0, 1.1)
		Puff.burst(get_parent(), _ahead(0.9) + Vector3(0.0, 0.25, 0.0), Color(0.85, 0.95, 1.0, 0.85), 8, 0.5, 0.5, 0.08, 0.5)
		Field.swing_net()
		return
	player.play_dig()
	Audio.play_sfx("dig", -2.0)
	if target.begins_with(TARGET_CLAM):
		var d: Dictionary = Field.digspots.get(target.trim_prefix(TARGET_CLAM), {})
		var at: Vector3 = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
		player.look_toward(at - player.global_position)
		Puff.burst(get_parent(), at + Vector3(0.0, 0.1, 0.0), Puff.dust_color(at), 6, 0.4, 0.4, 0.07, 0.45)
		Field.dig(at, "dig")
		return
	var tile: Vector3 = _tile_ahead()
	Puff.burst(get_parent(), tile + Vector3(0.0, 0.1, 0.0), Puff.dust_color(tile), 6, 0.45, 0.35, 0.07, 0.45)
	Field.dig(tile, {TARGET_DIG: "dig", TARGET_FILL: "fill", TARGET_PATH: "path", TARGET_UNPATH: "path"}.get(target, "dig"))


func _process(delta: float) -> void:
	_time += delta
	var shovel: bool = player != null and player.held_item == "shovel" and Net.state == Net.State.ONLINE
	if _mode_button != null:
		_mode_button.visible = shovel
	# 땅 고치기 자리 표시.
	var show_marker: bool = false
	if shovel and interaction != null and interaction.target == InteractionController.Target.FIELD and not interaction.target_id.begins_with(TARGET_CLAM):
		_marker.global_position = _tile_ahead() + Vector3(0.0, 0.04, 0.0)
		show_marker = true
	_marker.visible = show_marker
	_animate_fish(delta)
	for id: String in _spot_nodes:
		var n: Node3D = _spot_nodes[id]
		var bubble: Node3D = n.get_child(1)
		bubble.position.y = 0.06 + fmod(_time * 0.6 + float(absi(id.hash()) % 10) * 0.1, 0.25)
		bubble.scale = Vector3.ONE * (1.0 - bubble.position.y * 2.0)


# ---- 여울 물고기 ----

func _sync_all() -> void:
	for id: String in Field.shoals:
		_sync_shoal(id)
	for id: String in _spot_nodes.keys():
		if not Field.digspots.has(id):
			_remove_spot(id, 0)
	for d: Dictionary in Field.digspots.values():
		_add_spot(d)
	_rebuild_tiles()


func _sync_shoal(zone_id: String) -> void:
	var shoal: Dictionary = Field.shoals.get(zone_id, {})
	var fish: Dictionary = shoal.get("fish", {})
	for key: String in _fish_nodes.keys():
		var parts: PackedStringArray = key.split(":")
		if parts[0] == zone_id and not fish.has(int(parts[1])):
			(_fish_nodes[key]["node"] as Node3D).queue_free()
			_fish_nodes.erase(key)
	for fid: Variant in fish:
		var key: String = "%s:%d" % [zone_id, int(fid)]
		var f: Dictionary = fish[fid]
		if not _fish_nodes.has(key):
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = _fish_mesh(str(f.get("size", "S")))
			mi.material_override = clay_material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			mi.global_position = Vector3(float(f["x"]), 0.12, float(f["z"]))
			_fish_nodes[key] = {"node": mi, "zone": zone_id, "fid": int(fid)}


func _animate_fish(delta: float) -> void:
	var now: float = float(Time.get_ticks_msec())
	for key: String in _fish_nodes:
		var e: Dictionary = _fish_nodes[key]
		var shoal: Dictionary = Field.shoals.get(str(e["zone"]), {})
		var f: Dictionary = (shoal.get("fish", {}) as Dictionary).get(int(e["fid"]), {})
		if f.is_empty():
			continue
		var node: Node3D = e["node"]
		# 서버 값(10Hz)을 0.1초에 걸쳐 따라간다.
		var k: float = clampf((now - float(f.get("t", now))) / 100.0, 0.0, 1.0)
		var target: Vector3 = Vector3(lerpf(float(f["px"]), float(f["x"]), k), 0.12, lerpf(float(f["pz"]), float(f["z"]), k))
		var move: Vector3 = target - node.global_position
		node.global_position = node.global_position.lerp(target, 1.0 - exp(-14.0 * delta))
		if Vector2(move.x, move.z).length() > 0.002:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(move.z, -move.x), 1.0 - exp(-10.0 * delta))
		var panic: bool = bool(shoal.get("panic", false))
		node.rotation.z = sin(_time * (22.0 if panic else 9.0) + float(e["fid"])) * 0.18


# ---- 조개 숨구멍 · 땅 칸 ----

func _add_spot(d: Dictionary) -> void:
	var id: String = str(d.get("id", ""))
	if _spot_nodes.has(id):
		return
	var root: Node3D = Node3D.new()
	add_child(root)
	root.global_position = Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
	var hole: MeshInstance3D = MeshInstance3D.new()
	hole.mesh = _spot_mesh(str(d.get("kind", "beach")))
	hole.material_override = clay_material
	root.add_child(hole)
	var bubble: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	sm.radial_segments = 8
	sm.rings = 4
	bubble.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.97, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble.material_override = mat
	root.add_child(bubble)
	_spot_nodes[id] = root
	_update_spot(d)


func _update_spot(d: Dictionary) -> void:
	var n: Node3D = _spot_nodes.get(str(d.get("id", "")))
	if n == null:
		return
	# 파낼수록 구멍이 넓어진다.
	var hp: int = int(d.get("hp", 3))
	(n.get_child(0) as Node3D).scale = Vector3.ONE * (1.0 + 0.25 * maxf(0.0, 3.0 - float(hp)))


func _remove_spot(id: String, _by: int) -> void:
	var n: Node3D = _spot_nodes.get(id)
	if n == null:
		return
	_spot_nodes.erase(id)
	var tween: Tween = create_tween()
	tween.tween_property(n, "scale", Vector3(0.05, 0.05, 0.05), 0.25)
	tween.tween_callback(n.queue_free)


func _rebuild_tiles() -> void:
	var holes: Array[Vector3] = []
	var paths: Array[Vector3] = []
	for key: String in Field.tiles:
		var xz: PackedStringArray = key.split(",")
		var at: Vector3 = Vector3(float(xz[0]), 0.0, float(xz[1]))
		if Field.tiles[key] == Field.TILE_HOLE:
			holes.append(at)
		else:
			paths.append(at)
	_fill(_hole_mm, holes)
	_fill(_path_mm, paths)


func _fill(mmi: MultiMeshInstance3D, points: Array[Vector3]) -> void:
	var mm: MultiMesh = mmi.multimesh
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(absi(int(points[i].x * 31.0 + points[i].z * 17.0)) % 4) * PI * 0.5), points[i] + Vector3(0.0, 0.02, 0.0)))


# ---- 결과 ----

func _on_net(r: Dictionary) -> void:
	var fish: Array = r.get("fish", [])
	if fish.is_empty():
		toast_hud.show_toast("놓쳤어요! 구석으로 몰거나 친구와 양쪽에서 막아 보세요." if not bool(r.get("coop", false)) else "아깝다! 조금만 더 가까이.", false)
		return
	var names: PackedStringArray = []
	for id: Variant in fish:
		names.append(GameData.fish_name(str(id)))
	Audio.play_sfx("fish_catch", -4.0)
	toast_hud.show_toast("뜰채로 %s 을(를) 떴어요!%s" % [", ".join(names), " (둘이 몰아서 넓게!)" if bool(r.get("coop", false)) else ""], true)


func _on_dig(r: Dictionary) -> void:
	match str(r.get("kind", "")):
		"spot":
			toast_hud.show_toast("조금만 더! (남은 %d)%s" % [int(r.get("hp", 0)), " 같이 파서 두 칸!" if bool(r.get("coop", false)) else ""], true)
		"clam":
			var item: String = str(r.get("item", ""))
			if item.is_empty():
				toast_hud.show_toast("가방이 가득 차서 조개를 못 담았어요.", false)
			else:
				Audio.play_sfx("pickup", -4.0)
				toast_hud.show_toast("%s 을(를) 캤어요!%s" % [GameData.item_name(item), " (같이 캐서 둘 다 하나씩)" if bool(r.get("coop", false)) else ""], true)
		"dig":
			var found: String = str(r.get("item", ""))
			toast_hud.show_toast("구덩이를 팠어요." + (" 흙 속에서 %s!" % GameData.item_name(found) if not found.is_empty() else ""), true)
		"fill":
			toast_hud.show_toast("구덩이를 메웠어요.", true)
		"path":
			toast_hud.show_toast("흙길을 깔았어요." if str(r.get("s", "")) == Field.TILE_PATH else "흙길을 걷었어요.", true)


func _on_failed(kind: String, code: String) -> void:
	var text: String = {
		NetProtocol.ERR_BAD_DIG: "여기는 팔 수 없어요 (물가 · 모래밭 · 길 · 나무 곁).",
		NetProtocol.ERR_NOT_IN_SHALLOW: "얕은 물(여울) 안에서 그물질해요.",
		NetProtocol.ERR_TOO_FAST: "",
		NetProtocol.ERR_PLANT_LIMIT: "땅을 너무 많이 고쳤어요.",
		NetProtocol.ERR_NO_TOOL: "손에 도구를 들어야 해요.",
	}.get(code, code)
	if not text.is_empty():
		toast_hud.show_toast(text, false)


# ---- 도우미 ----

func _ahead(distance: float) -> Vector3:
	var forward: Vector3 = -player.body.global_basis.z if player.body != null else Vector3.FORWARD
	forward.y = 0.0
	return player.global_position + forward.normalized() * distance


func _tile_ahead() -> Vector3:
	var at: Vector3 = _ahead(1.3)
	return Vector3(roundf(at.x), 0.0, roundf(at.z))


## 서버 판정(groundProblem · 모래밭 · 길)과 비슷하게 미리 거른다. 확정은 서버.
func _diggable(at: Vector3) -> bool:
	var layout: VillageLayout = GameData.layout
	var p: Vector2 = Vector2(at.x, at.z)
	var tile: String = Field.tile_at(int(at.x), int(at.z))
	if layout != null and not layout.on_grass_land(p):
		return false
	if layout != null and tile.is_empty() and layout.on_path(p, 0.2):
		return false
	for spot: SpotInfo in GameData.spots.values():
		if spot.distance_to(at) < 0.6:
			return false
	return true


func _refresh_mode_button() -> void:
	if _mode_button != null:
		_mode_button.text = "삽: 구덩이" if shovel_mode == ShovelMode.HOLE else "삽: 흙길"


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	for side: float in [-1.0, 1.0]:
		ClayMesh.add_box(st, Vector3(0.0, 0.0, 0.48 * side), Vector3(1.0, 0.03, 0.06), Color("#FFF4C8"))
		ClayMesh.add_box(st, Vector3(0.48 * side, 0.0, 0.0), Vector3(0.06, 0.03, 1.0), Color("#FFF4C8"))
	_marker.mesh = ClayMesh.commit(st)
	_marker.material_override = clay_material
	_marker.visible = false
	add_child(_marker)


func _multimesh(mesh: Mesh) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = clay_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## 구덩이: 어두운 흙 바닥 + 둘레에 쌓인 흙 무더기.
static func _hole_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.0, 0.0), Vector3(0.42, 0.02, 0.42), Color("#3E2A1C"), 12, 3)
	ClayMesh.add_torus(st, Vector3(0.0, 0.03, 0.0), 0.44, 0.07, ClayMesh.vertical_gradient(Color("#6A4A30"), Color("#8A6A48"), 1.0), 14, 4)
	ClayMesh.add_ellipsoid(st, Vector3(0.38, 0.06, 0.32), Vector3(0.16, 0.08, 0.14), Color("#7A5A3A"), 6, 4)
	return ClayMesh.commit(st)


## 흙길 한 칸: 살짝 볼록한 흙빛 판 (마을 길과 같은 색).
static func _path_mesh() -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rounded_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.04, 0.03, 1.04), 0.5, ClayMesh.vertical_gradient(Color("#C8AE7E"), Color("#E3CC98"), 1.0), Basis(), 6, 2)
	return ClayMesh.commit(st)


## 숨구멍: 모래(호숫가는 진흙빛) 위의 작은 구멍.
static func _spot_mesh(kind: String) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	var rim: Color = Color("#E8D4A8") if kind == "beach" else Color("#B89A6A")
	ClayMesh.add_torus(st, Vector3(0.0, 0.015, 0.0), 0.11, 0.035, rim, 10, 4)
	ClayMesh.add_ellipsoid(st, Vector3(0.0, 0.005, 0.0), Vector3(0.09, 0.01, 0.09), Color("#6A5A44"), 8, 2)
	return ClayMesh.commit(st)


## 여울 물고기: 물속에 비친 어두운 몸 + 꼬리 (머리 = −X).
static func _fish_mesh(size: String) -> ArrayMesh:
	var s: float = {"S": 0.7, "M": 1.0, "L": 1.3}.get(size, 0.8)
	var st: SurfaceTool = ClayMesh.begin()
	var body: Callable = ClayMesh.vertical_gradient(Color("#3E5A66"), Color("#6A8A94"), 1.0)
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.16, 0.045, 0.06) * s, body, 8, 4)
	ClayMesh.add_ellipsoid(st, Vector3(0.17, 0.0, 0.0) * s, Vector3(0.05, 0.04, 0.012) * s, Color("#4E6A76"), 6, 3)
	return ClayMesh.commit(st)
