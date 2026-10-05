class_name InteractionController
extends Node
## 상황 버튼으로 하는 일: 주민·상점 주인·떠돌이 상인·박물관 관장·공항 조종사에게 말 걸기, 상점 드나들기, 선물·별 조각 줍기,
## 핀 꽃 따기, 거울 보기(얼굴 꾸미기), 도끼로 나무 베기, 손에 든 씨앗 심기, 내 가구 줍기. (낚시는 FishingController 가 맡는다.)
## 우선순위: 주민 > 떠돌이 상인 > 관장·조종사 > 상점 주인 > 상점 문 > 선물·별 조각 > 꽃 > 거울 > 나무 > 씨앗 심기 > 가구 > (물가면 낚시).
## 판정은 서버가 하고 여기서는 가까운 대상을 고르고 연출만 한다.

@export_group("References")
@export var player: Player
@export var trees: TreeField
@export var npcs: NpcCrowd
@export var shop: ShopController
@export var furniture: FurnitureField
@export var drops: DropField
@export var merchant: MerchantStall
@export var museum: MuseumSite
@export var airport: AirportSite
@export var flowers: FlowerField
@export var mirrors: MirrorSite
@export var mirror_window: MirrorWindow
@export var dialogue: DialogueController
@export var fishing: FishingController
@export var action_hud: ActionHud
## 식당 열기 · 주방 · 부동산 · 동사무소 (v0.8~0.9, 없어도 된다).
@export var economy: EconomyController
## 뜰채질 · 조개 캐기 · 구덩이·흙길 (v0.9, 없어도 된다).
@export var field: FieldController
## 아파트 집 구경 · 집 안 나가기 (v0.10, 없어도 된다).
@export var home: HomeController
## 결과 문구를 띄울 곳 (낚시 HUD의 토스트를 같이 쓴다).
@export var toast_hud: FishingHud

@export_group("Feel")
## 서버 판정 거리보다 이만큼 안쪽에서만 버튼을 보여 줘서 경계에서 거절당하지 않게 한다.
@export_range(0.0, 1.0, 0.05, "suffix:m") var safety_margin: float = 0.3
## 도끼를 휘두르는 동안 멈춰 있는 시간.
@export_range(0.1, 1.5, 0.05, "suffix:s") var chop_lock_time: float = 0.45

## 씨앗을 심는 동안 멈춰 있는 시간 (쪼그려 앉아 토닥토닥).
@export_range(0.1, 2.0, 0.05, "suffix:s") var plant_lock_time: float = 0.8
## 씨앗을 심는 자리: 캐릭터 앞 이만큼.
@export_range(0.5, 2.0, 0.05, "suffix:m") var plant_ahead: float = 1.1

enum Target { NONE, TALK, CHOP, ENTER_SHOP, EXIT_SHOP, PICKUP, COLLECT, PICK, PLANT, MIRROR, ECONOMY, FIELD, HOME }

## 가구 줍기 거리 (서버 판정 2.5m 보다 안쪽).
const PICKUP_RANGE: float = 2.0

var target: Target = Target.NONE
var target_id: String = ""
## 씨앗을 심을 자리 (Target.PLANT 일 때).
var plant_spot: Vector3 = Vector3.ZERO
## 씨앗을 들고 있을 때 심을 자리를 보여 주는 고리 (초록 = 심을 수 있음, 빨강 = 안 됨).
var _plant_marker: MeshInstance3D = null
var _marker_ok: ArrayMesh = null
var _marker_bad: ArrayMesh = null


func _ready() -> void:
	action_hud.action_pressed.connect(_on_action_pressed)
	Net.chop_succeeded.connect(_on_chop_succeeded)
	Net.request_failed.connect(_on_request_failed)
	Net.furniture_placed.connect(_on_furniture_placed)
	Net.collected.connect(_on_collected)
	Net.fish_bonus.connect(func(amount: int) -> void: toast_hud.show_toast("낚시 대회 상금 %s!" % Money.delta(amount), true))
	Net.planted.connect(_on_planted)
	Net.flower_picked.connect(func(item_id: String) -> void: toast_hud.show_toast("%s을(를) 땄어요" % GameData.item_name(item_id), true))
	_build_plant_marker()


## 지금 말 걸기·베기 대상이 있는지 (있으면 낚시 버튼을 숨긴다).
func has_target() -> bool:
	return target != Target.NONE


func _process(_delta: float) -> void:
	_pick_target()
	match target:
		Target.TALK:
			action_hud.show_action("대화")
		Target.CHOP:
			action_hud.show_action("베기")
		Target.ENTER_SHOP:
			action_hud.show_action("들어가기")
		Target.EXIT_SHOP:
			action_hud.show_action("나가기")
		Target.PICKUP:
			action_hud.show_action("줍기")
		Target.COLLECT:
			action_hud.show_action(_collect_label(target_id))
		Target.PICK:
			action_hud.show_action("꽃 따기")
		Target.PLANT:
			action_hud.show_action("심기")
		Target.MIRROR:
			action_hud.show_action("거울 보기")
		Target.ECONOMY:
			action_hud.show_action(economy.target_label(target_id))
		Target.FIELD:
			action_hud.show_action(field.target_label(target_id))
		Target.HOME:
			action_hud.show_action(home.target_label(target_id))
		_:
			action_hud.hide_action()
	_update_plant_marker()


func _pick_target() -> void:
	target = Target.NONE
	target_id = ""
	if Net.state != Net.State.ONLINE or player.is_input_locked() or dialogue.is_active() or (mirror_window != null and mirror_window.is_open()):
		return
	if economy != null and economy.is_busy():
		return
	if home != null and home.is_busy():
		return
	if fishing != null and fishing.phase != FishingController.Phase.IDLE:
		return
	var pos: Vector3 = player.global_position
	var npc_id: String = npcs.nearest_talkable(pos, GameData.talk_range - safety_margin)
	if not npc_id.is_empty():
		target = Target.TALK
		target_id = npc_id
		return
	if merchant != null and merchant.near(pos, GameData.talk_range - safety_margin):
		target = Target.TALK
		target_id = merchant.npc_id()
		return
	for site: KeeperSite in [museum, airport]:
		if site != null and site.near(pos, GameData.talk_range - safety_margin):
			target = Target.TALK
			target_id = site.npc_id()
			return
	if home != null:
		var home_target: String = home.pick_target(pos)
		if not home_target.is_empty():
			target = Target.HOME
			target_id = home_target
			return
		# 집 안에서는 다른 상황 버튼(심기 · 줍기 …)을 띄우지 않는다.
		if Home.is_inside():
			return
	if economy != null:
		var econ_target: String = economy.pick_target(pos, GameData.talk_range - safety_margin)
		if not econ_target.is_empty():
			target = Target.ECONOMY
			target_id = econ_target
			return
	if shop != null:
		if shop.is_inside(pos):
			if shop.keeper != null and _flat(pos, shop.keeper.global_position) <= GameData.talk_range:
				target = Target.TALK
				target_id = GameData.shop.keeper.id
			elif shop.near_exit(pos):
				target = Target.EXIT_SHOP
			return
		if shop.near_entrance(pos):
			target = Target.ENTER_SHOP
			return
	if drops != null:
		var drop_id: String = drops.nearest(pos, GameData.collect_range - safety_margin)
		if not drop_id.is_empty():
			target = Target.COLLECT
			target_id = drop_id
			return
	if field != null:
		var field_target: String = field.pick_target(pos)
		if not field_target.is_empty():
			target = Target.FIELD
			target_id = field_target
			return
	if flowers != null:
		var flower_id: String = flowers.nearest_bloom(pos, GameData.plant_range - safety_margin)
		if not flower_id.is_empty():
			target = Target.PICK
			target_id = flower_id
			return
	var mirror_range: float = (GameData.face.mirror_range if GameData.face != null else 2.2) - safety_margin
	if mirrors != null and mirrors.nearest(pos, mirror_range) >= 0:
		target = Target.MIRROR
		return
	if furniture != null:
		var mirror_id: String = furniture.nearest_mirror(pos, mirror_range)
		if not mirror_id.is_empty():
			target = Target.MIRROR
			target_id = mirror_id
			return
	if player.held_item == "axe":
		var tree_id: String = trees.nearest_grown(pos, GameData.chop_range - safety_margin)
		if not tree_id.is_empty():
			target = Target.CHOP
			target_id = tree_id
			return
	var held: ItemInfo = GameData.item(player.held_item)
	if held != null and held.is_seed() and not (shop != null and shop.is_inside(pos)):
		plant_spot = _plant_spot()
		if can_plant_at(plant_spot, not held.plant_tree.is_empty()):
			target = Target.PLANT
			target_id = player.held_item
			return
	if furniture != null:
		var furniture_id: String = furniture.nearest_own(pos, PICKUP_RANGE)
		if not furniture_id.is_empty():
			target = Target.PICKUP
			target_id = furniture_id


func _on_action_pressed() -> void:
	match target:
		Target.TALK:
			dialogue.start(target_id)
		Target.CHOP:
			_chop(target_id)
		Target.ENTER_SHOP:
			Net.enter_shop()
		Target.EXIT_SHOP:
			Net.exit_shop()
		Target.PICKUP:
			Net.pickup_furniture(target_id)
		Target.COLLECT:
			player.look_toward(drops.drop_position(target_id) - player.global_position)
			Net.collect(target_id)
		Target.PICK:
			player.look_toward(flowers.flower_position(target_id) - player.global_position)
			player.play_plant()
			Net.pick_flower(target_id)
		Target.PLANT:
			_plant(plant_spot)
		Target.ECONOMY:
			economy.activate(target_id)
		Target.FIELD:
			field.activate(target_id)
		Target.HOME:
			home.activate(target_id)
		Target.MIRROR:
			if mirror_window != null:
				var at: Vector3 = Net.placed[target_id].position if Net.placed.has(target_id) else mirrors.spot_position(mirrors.nearest(player.global_position, 4.0))
				mirror_window.open(target_id, at)


func _collect_label(drop_id: String) -> String:
	var d: DropInfo = Net.drops.get(drop_id)
	if d == null:
		return "줍기"
	match d.kind:
		DropInfo.KIND_GIFT:
			return "선물 줍기"
		DropInfo.KIND_FORAGE:
			return "채집"
	return "별 줍기"


## 캐릭터 앞 땅, 0.5m 격자 (서버가 맞추는 자리와 같다).
func _plant_spot() -> Vector3:
	var forward: Vector3 = -player.body.global_basis.z if player.body != null else Vector3.FORWARD
	forward.y = 0.0
	var at: Vector3 = player.global_position + forward.normalized() * plant_ahead
	return Vector3(snappedf(at.x, 0.5), 0.0, snappedf(at.z, 0.5))


## 이 자리에 심을 수 있는지 (서버 plantProblem 과 같은 규칙: 섬 풀밭, 물·길·건물·집 아님, 나무·꽃과 떨어짐).
func can_plant_at(at: Vector3, is_tree: bool) -> bool:
	var layout: VillageLayout = GameData.layout
	var p: Vector2 = Vector2(at.x, at.z)
	if layout != null and (not layout.on_grass_land(p) or layout.on_path(p, 0.2)):
		return false
	for spot: SpotInfo in GameData.spots.values():
		if spot.distance_to(at) < 0.6:
			return false
	for place: KeeperPlace in [GameData.museum, GameData.airport]:
		if place != null and (VillageDecor._in_building(place, p, 1.5) or place.keeper_position.distance_to(at) < 1.6):
			return false
	var door: Vector3 = GameData.shop.door
	if at.x > door.x - 5.2 and at.x < door.x + 5.2 and at.z > door.z - 7.5 and at.z < door.z + 2.5:
		return false
	for npc: NpcInfo in GameData.npcs.values():
		if Vector2(npc.house_position.x, npc.house_position.z).distance_to(p) < 4.2:
			return false
	if layout != null:
		for mirror: Vector3 in layout.mirrors:
			if Vector2(mirror.x, mirror.y).distance_to(p) < 1.3:
				return false
	if trees != null and not trees.clear_for_tree(at, GameData.tree_clearance if is_tree else 1.0):
		return false
	if flowers != null and not flowers.clear_for(at, 1.0 if is_tree else GameData.flower_clearance):
		return false
	if furniture != null and not furniture.nearest_any(at, 0.9).is_empty():
		return false
	return true


func _plant(at: Vector3) -> void:
	player.look_toward(at - player.global_position)
	player.play_plant()
	player.set_input_lock(&"plant", true)
	Audio.play_sfx("dig", -2.0)
	Net.plant(at)
	await get_tree().create_timer(plant_lock_time).timeout
	player.set_input_lock(&"plant", false)
	player.clear_look_direction()


func _on_planted(kind: String, _id: String) -> void:
	toast_hud.show_toast("나무를 심었어요! 무럭무럭 자라라" if kind == "tree" else "꽃씨를 심었어요!", true)


func _build_plant_marker() -> void:
	var ok: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(ok, Vector3(0.0, 0.04, 0.0), 0.32, 0.035, Color("#7FE07A"), 16, 4)
	_marker_ok = ClayMesh.commit(ok)
	var bad: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_torus(bad, Vector3(0.0, 0.04, 0.0), 0.32, 0.035, Color("#F27A6A"), 16, 4)
	_marker_bad = ClayMesh.commit(bad)
	_plant_marker = MeshInstance3D.new()
	_plant_marker.name = "PlantMarker"
	_plant_marker.material_override = Puff.MATERIAL
	_plant_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plant_marker.visible = false
	add_child.call_deferred(_plant_marker)


## 씨앗을 들고 있으면 심을 자리에 고리를 보여 준다.
func _update_plant_marker() -> void:
	if _plant_marker == null or not _plant_marker.is_inside_tree():
		return
	var held: ItemInfo = GameData.item(player.held_item)
	var show: bool = held != null and held.is_seed() and Net.state == Net.State.ONLINE and not player.is_input_locked() \
		and target in [Target.NONE, Target.PLANT] and not (shop != null and shop.is_inside(player.global_position))
	_plant_marker.visible = show
	if not show:
		return
	var at: Vector3 = plant_spot if target == Target.PLANT else _plant_spot()
	_plant_marker.global_position = at
	_plant_marker.mesh = _marker_ok if target == Target.PLANT else _marker_bad
	_plant_marker.scale = Vector3.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() / 160.0))


func _chop(tree_id: String) -> void:
	player.look_toward(trees.tree_position(tree_id) - player.global_position)
	player.play_chop()
	player.set_input_lock(&"chop", true)
	Net.chop_tree(tree_id)
	await get_tree().create_timer(chop_lock_time).timeout
	player.set_input_lock(&"chop", false)
	player.clear_look_direction()


func _on_chop_succeeded(_tree_id: String, item_id: String, felled: bool) -> void:
	# 세로 화면 한 줄에 들어가게 짧게.
	var text: String = "+%d %s" % [Net.last_chop_count, GameData.item_name(item_id)]
	toast_hud.show_toast("쿵! %s" % text if felled else text, true)


func _on_collected(kind: String, item_id: String) -> void:
	player.clear_look_direction()
	if kind == DropInfo.KIND_GIFT:
		toast_hud.show_toast("선물 상자 속에 %s!" % GameData.item_name(item_id), true)
	elif kind == DropInfo.KIND_FORAGE:
		toast_hud.show_toast("%s을(를) 채집했어요 (식당 재료)" % GameData.item_name(item_id), true)
	else:
		toast_hud.show_toast("반짝! %s을(를) 주웠어요" % GameData.item_name(item_id), true)


func _on_furniture_placed(info: PlacedInfo, by_player: int) -> void:
	if by_player == Net.my_id:
		toast_hud.show_toast("%s을(를) 놓았어요" % GameData.item_name(info.item), true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_request_failed(kind: String, code: String) -> void:
	if code == LocalTestServer.ERR_TEST_ONLY:
		toast_hud.show_toast("테스트 서버에서는 아직 안 되는 기능이에요 (진짜 서버에서 해 보세요)", false)
		return
	match kind:
		"place":
			match code:
				NetProtocol.ERR_PLACE_LIMIT:
					toast_hud.show_toast("가구를 더 놓을 수 없어요", false)
				_:
					toast_hud.show_toast("여기에는 놓을 수 없어요", false)
			return
		"pickup":
			toast_hud.show_toast("가방이 가득 찼어요" if code == NetProtocol.ERR_INVENTORY_FULL else "주울 수 없어요", false)
			return
		"wear", "unwear":
			toast_hud.show_toast("가방이 가득 차서 벗을 수 없어요" if code == NetProtocol.ERR_INVENTORY_FULL else "입을 수 없는 물건이에요", false)
			return
		"shop_enter", "shop_exit":
			toast_hud.show_toast("문에 더 가까이 가야 해요", false)
			return
		"collect":
			player.clear_look_direction()
			toast_hud.show_toast("가방이 가득 찼어요" if code == NetProtocol.ERR_INVENTORY_FULL else "조금 더 가까이 가야 해요", false)
			return
		"plant":
			match code:
				NetProtocol.ERR_PLANT_LIMIT:
					toast_hud.show_toast("마을에 더 심을 자리가 없어요", false)
				NetProtocol.ERR_NOT_SEED:
					toast_hud.show_toast("씨앗을 손에 들어야 해요", false)
				_:
					toast_hud.show_toast("여기에는 심을 수 없어요", false)
			return
		"pick":
			toast_hud.show_toast("가방이 가득 찼어요" if code == NetProtocol.ERR_INVENTORY_FULL else "아직 꽃이 안 피었어요", false)
			return
	if kind != "chop":
		return
	match code:
		NetProtocol.ERR_INVENTORY_FULL:
			toast_hud.show_toast("가방이 가득 찼어요", false)
		NetProtocol.ERR_TREE_NOT_READY:
			toast_hud.show_toast("아직 다 자라지 않았어요", false)
		NetProtocol.ERR_NO_TOOL:
			toast_hud.show_toast("도끼를 손에 들어야 해요", false)
		NetProtocol.ERR_TOO_FAST:
			pass
		_:
			toast_hud.show_toast("나무에 더 가까이 가야 해요", false)
