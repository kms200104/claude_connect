class_name InteractionController
extends Node
## 상황 버튼으로 하는 일: 주민·상점 주인·떠돌이 상인에게 말 걸기, 상점 드나들기, 선물·별 조각 줍기, 도끼로 나무 베기, 내 가구 줍기.
## (낚시는 FishingController 가 맡는다.) 우선순위: 주민 > 떠돌이 상인 > 상점 주인 > 상점 문 > 선물·별 조각 > 나무 > 가구 > (물가면 낚시).
## 판정은 서버가 하고 여기서는 가까운 대상을 고르고 연출만 한다.

@export_group("References")
@export var player: Player
@export var trees: TreeField
@export var npcs: NpcCrowd
@export var shop: ShopController
@export var furniture: FurnitureField
@export var drops: DropField
@export var merchant: MerchantStall
@export var dialogue: DialogueController
@export var fishing: FishingController
@export var action_hud: ActionHud
## 결과 문구를 띄울 곳 (낚시 HUD의 토스트를 같이 쓴다).
@export var toast_hud: FishingHud

@export_group("Feel")
## 서버 판정 거리보다 이만큼 안쪽에서만 버튼을 보여 줘서 경계에서 거절당하지 않게 한다.
@export_range(0.0, 1.0, 0.05, "suffix:m") var safety_margin: float = 0.3
## 도끼를 휘두르는 동안 멈춰 있는 시간.
@export_range(0.1, 1.5, 0.05, "suffix:s") var chop_lock_time: float = 0.45

enum Target { NONE, TALK, CHOP, ENTER_SHOP, EXIT_SHOP, PICKUP, COLLECT }

## 가구 줍기 거리 (서버 판정 2.5m 보다 안쪽).
const PICKUP_RANGE: float = 2.0

var target: Target = Target.NONE
var target_id: String = ""


func _ready() -> void:
	action_hud.action_pressed.connect(_on_action_pressed)
	Net.chop_succeeded.connect(_on_chop_succeeded)
	Net.request_failed.connect(_on_request_failed)
	Net.furniture_placed.connect(_on_furniture_placed)
	Net.collected.connect(_on_collected)
	Net.fish_bonus.connect(func(amount: int) -> void: toast_hud.show_toast("낚시 대회 상금 +%d솔!" % amount, true))


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
			action_hud.show_action("선물 줍기" if Net.drops.has(target_id) and Net.drops[target_id].kind == DropInfo.KIND_GIFT else "별 줍기")
		_:
			action_hud.hide_action()


func _pick_target() -> void:
	target = Target.NONE
	target_id = ""
	if Net.state != Net.State.ONLINE or player.is_input_locked() or dialogue.is_active():
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
	if player.held_item == "axe":
		var tree_id: String = trees.nearest_grown(pos, GameData.chop_range - safety_margin)
		if not tree_id.is_empty():
			target = Target.CHOP
			target_id = tree_id
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
	else:
		toast_hud.show_toast("반짝! %s을(를) 주웠어요" % GameData.item_name(item_id), true)


func _on_furniture_placed(info: PlacedInfo, by_player: int) -> void:
	if by_player == Net.my_id:
		toast_hud.show_toast("%s을(를) 놓았어요" % GameData.item_name(info.item), true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_request_failed(kind: String, code: String) -> void:
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
