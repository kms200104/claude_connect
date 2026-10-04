class_name DialogueController
extends Node
## 주민과의 대화 한 번. 서버에 말을 걸고(talk), 서버가 알려 준 상황(진행 중인 부탁 / 새 부탁 제안 / 그냥 수다)에 맞춰
## data/npcs/dialogue.json 에서 성격별 대사를 골라 보여 준다. 부탁 수락·완료는 서버에 요청하고 결과를 기다린다.

signal finished

@export_group("References")
@export var player: Player
@export var npcs: NpcCrowd
@export var box: DialogueBox
@export var toast_hud: FishingHud

@export_group("Feel")
## 서버가 답하지 않으면 이 시간 뒤 대화를 접는다.
@export_range(1.0, 15.0, 0.5, "suffix:s") var reply_timeout: float = 5.0
## 날씨 이야기를 꺼낼 확률 (맑은 날 제외).
@export_range(0.0, 1.0, 0.05) var weather_talk_chance: float = 0.6

var npc_id: String = ""
## 대화마다 하나씩 늘어난다. 기다리는 동안 대화가 끝나면 이전 흐름이 멈춘다.
var _session: int = 0
var _active: bool = false


func _ready() -> void:
	Net.talk_opened.connect(_on_talk_opened)
	Net.talk_closed.connect(_on_talk_closed)
	Net.request_failed.connect(_on_request_failed)
	Net.state_changed.connect(_on_net_state_changed)


func is_active() -> bool:
	return _active


func start(id: String) -> void:
	if _active:
		return
	_active = true
	_session += 1
	npc_id = id
	player.set_input_lock(&"dialogue", true)
	var actor: NpcActor = npcs.actor(id)
	if actor != null:
		player.look_toward(actor.global_position - player.global_position)
		actor.face_toward(player.global_position)
	Net.talk_to(id)
	var token: int = _session
	await get_tree().create_timer(reply_timeout).timeout
	if token == _session and _active and not box.is_open():
		stop()


## 대화를 끝낸다 (서버에도 알린다).
func stop() -> void:
	if not _active:
		return
	_active = false
	_session += 1
	Net.end_talk()
	box.close()
	player.set_input_lock(&"dialogue", false)
	player.clear_look_direction()
	finished.emit()


func _on_talk_closed(id: String) -> void:
	if id == npc_id:
		stop()


func _on_net_state_changed(new_state: int) -> void:
	if new_state != Net.State.ONLINE:
		stop()


func _on_request_failed(kind: String, code: String) -> void:
	if not _active:
		return
	match kind:
		"talk":
			var who: String = GameData.npc_name(npc_id)
			match code:
				NetProtocol.ERR_NPC_BUSY:
					toast_hud.show_toast("%s은(는) 다른 친구와 이야기 중이에요" % who, false)
				NetProtocol.ERR_ALREADY_FISHING:
					toast_hud.show_toast("낚시 중에는 말을 걸 수 없어요", false)
				_:
					toast_hud.show_toast("%s에게 더 가까이 가야 해요" % who, false)
			stop()
		"quest_turnin":
			toast_hud.show_toast("아직 부탁한 걸 다 모으지 못했어요", false)
			stop()


func _on_talk_opened(reply: TalkReply) -> void:
	if not _active or reply.npc != npc_id:
		return
	var token: int = _session
	var info: NpcInfo = GameData.npcs.get(reply.npc)
	if info == null:
		stop()
		return
	var quest: QuestInfo = reply.quest if reply.quest != null else reply.offer
	var values: Dictionary = {
		"player": GameData.player_name(Net.my_id),
		"npc": info.display_name,
		"item": _quest_item_name(quest),
		"n": quest.count if quest != null else 0,
		"reward": quest.reward if quest != null else 0,
	}
	var p: String = info.personality

	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	if Net.weather != NetProtocol.WEATHER_CLEAR and randf() < weather_talk_chance:
		if not await _say(token, info, GameData.dialogue_line(p, "weather_" + Net.weather, values)):
			return

	if reply.quest != null:
		if reply.ready:
			await _turn_in_flow(token, info, reply.quest, values)
		else:
			if not await _say(token, info, GameData.dialogue_line(p, "progress", values)):
				return
			await _say(token, info, GameData.dialogue_line(p, "bye", values))
	elif reply.offer != null:
		await _offer_flow(token, info, reply.offer, values)
	else:
		if not await _say(token, info, GameData.dialogue_line(p, "chat", values)):
			return
		await _say(token, info, GameData.dialogue_line(p, "bye", values))
	if token == _session:
		stop()


func _offer_flow(token: int, info: NpcInfo, offer: QuestInfo, values: Dictionary) -> void:
	var key: String = "offer_deliver"
	match offer.kind:
		NetProtocol.QUEST_DELIVER_FISH:
			key = "offer_fish"
		NetProtocol.QUEST_ANY_FISH:
			key = "offer_any_fish"
	if not await _say(token, info, GameData.dialogue_line(info.personality, key, values)):
		return
	var pick: int = await _choose(token, [GameData.choice_text("accept"), GameData.choice_text("decline")])
	if pick == 0:
		Net.accept_quest()
		if await _say(token, info, GameData.dialogue_line(info.personality, "accept", values)):
			toast_hud.show_toast("부탁을 받았어요: %s" % describe_quest(offer), true)
	elif pick == 1:
		Net.decline_quest()
		await _say(token, info, GameData.dialogue_line(info.personality, "decline", values))


func _turn_in_flow(token: int, info: NpcInfo, quest: QuestInfo, values: Dictionary) -> void:
	if not await _say(token, info, GameData.dialogue_line(info.personality, "ready", values)):
		return
	var pick: int = await _choose(token, [GameData.choice_text("turn_in"), GameData.choice_text("not_yet")])
	if pick != 0:
		if pick == 1:
			await _say(token, info, GameData.dialogue_line(info.personality, "bye", values))
		return
	Net.turn_in_quest(quest.id)
	var done: Array = await Net.quest_completed
	if token != _session:
		return
	values["reward"] = int(done[2])
	await _say(token, info, GameData.dialogue_line(info.personality, "done", values))
	toast_hud.show_toast("+%d솔" % int(done[2]), true)


## 한 줄 보여 주고 넘길 때까지 기다린다. 그 사이 대화가 끝났으면 false.
func _say(token: int, info: NpcInfo, line: String) -> bool:
	if token != _session:
		return false
	if line.is_empty():
		return true
	box.show_line(info.display_name, line, info.color.lightened(0.2))
	await box.advanced
	return token == _session


func _choose(token: int, options: PackedStringArray) -> int:
	if token != _session:
		return -1
	box.show_choices(options)
	var index: int = await box.chosen
	return index if token == _session else -1


func _quest_item_name(q: QuestInfo) -> String:
	if q == null:
		return ""
	return "물고기" if q.kind == NetProtocol.QUEST_ANY_FISH else GameData.item_name(q.item)


## "목재 3개", "붕어 1마리", "물고기 2마리" 처럼 짧게.
static func describe_quest(q: QuestInfo) -> String:
	if q.kind == NetProtocol.QUEST_ANY_FISH:
		return "물고기 %d마리" % q.count
	var info: ItemInfo = GameData.item(q.item)
	var unit: String = "마리" if info != null and info.is_fish() else "개"
	return "%s %d%s" % [GameData.item_name(q.item), q.count, unit]
