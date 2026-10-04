class_name InteractionController
extends Node
## 상황 버튼으로 하는 일: 주민에게 말 걸기, 도끼로 나무 베기. (낚시는 FishingController 가 맡는다.)
## 우선순위: 주민 > 나무 > (물가면 낚시). 판정은 서버가 하고 여기서는 가까운 대상을 고르고 연출만 한다.

@export_group("References")
@export var player: Player
@export var trees: TreeField
@export var npcs: NpcCrowd
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

enum Target { NONE, TALK, CHOP }

var target: Target = Target.NONE
var target_id: String = ""


func _ready() -> void:
	action_hud.action_pressed.connect(_on_action_pressed)
	Net.chop_succeeded.connect(_on_chop_succeeded)
	Net.request_failed.connect(_on_request_failed)


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
	if player.held_item == "axe":
		var tree_id: String = trees.nearest_grown(pos, GameData.chop_range - safety_margin)
		if not tree_id.is_empty():
			target = Target.CHOP
			target_id = tree_id


func _on_action_pressed() -> void:
	match target:
		Target.TALK:
			dialogue.start(target_id)
		Target.CHOP:
			_chop(target_id)


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
	var text: String = "+1 %s" % GameData.item_name(item_id)
	toast_hud.show_toast("쿵! %s" % text if felled else text, true)


func _on_request_failed(kind: String, code: String) -> void:
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
