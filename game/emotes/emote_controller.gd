class_name EmoteController
extends Node
## 감정표현: 감정표현 칸(EmoteBar)에서 고르면 내 캐릭터가 몸짓을 하고 머리 위에 말풍선을 띄운 뒤 서버에 알린다.
## 서버는 상대에게 보여 주고, 근처 주민이 성격·기분대로 반응하게 한다 (npc_emote → 주민이 몸짓 + 짧은 대사).
## 달리다 브레이크를 잡으면 그 몸짓도 서버를 거쳐 상대 화면에 보인다.

@export var player: Player
@export var npcs: NpcCrowd
@export var dialogue: DialogueController
@export var fishing: FishingController
@export var emote_bar: EmoteBar
@export var emote_window: EmoteWindow
@export var toast_hud: FishingHud
## 감정표현을 하는 동안 멈춰 있는 시간.
@export_range(0.0, 2.0, 0.05, "suffix:s") var lock_time: float = 0.9

var _busy: bool = false


func _ready() -> void:
	if emote_bar != null:
		emote_bar.emote_chosen.connect(perform)
		if emote_window != null:
			emote_bar.edit_pressed.connect(emote_window.open)
	if player != null:
		player.braked.connect(func() -> void: Net.send_emote(NetProtocol.MOTION_BRAKE))
	Net.npc_emoted.connect(_on_npc_emoted)


## 지금 감정표현을 할 수 있는지 (대화·낚시·미끄러지는 중에는 안 된다).
func can_emote() -> bool:
	if Net.state != Net.State.ONLINE or player == null or _busy or player.braking:
		return false
	if dialogue != null and dialogue.is_active():
		return false
	if fishing != null and fishing.phase != FishingController.Phase.IDLE:
		return false
	return not player.is_input_locked()


func perform(emote_id: String) -> void:
	if not emote_id in Net.emotes_known:
		if toast_hud != null:
			toast_hud.show_toast("아직 배우지 않은 감정표현이에요", false)
		return
	if not can_emote():
		return
	_busy = true
	player.play_emote(emote_id)
	Net.send_emote(emote_id)
	player.set_input_lock(&"emote", true)
	await get_tree().create_timer(lock_time).timeout
	player.set_input_lock(&"emote", false)
	_busy = false


## 주민이 누군가의 감정표현에 반응했다: 그 사람을 돌아보고 몸짓 + 성격·기분에 맞는 한마디.
func _on_npc_emoted(npc_id: String, emote_id: String, to_player: int, mood: String, from: String = "") -> void:
	var actor: NpcActor = npcs.actor(npc_id) if npcs != null else null
	if actor == null:
		return
	actor.mood = mood
	if to_player == Net.my_id and player != null:
		actor.face_toward(player.global_position)
	var values: Dictionary = {"player": GameData.player_name(to_player)}
	# MBTI: 내 감정표현에 공감(F)하거나 덤덤하게(T) 반응한 거면 그 대사, 아니면 성격 대사.
	var line: String = ""
	var tf: String = actor.info.mbti_letter(2)
	var empathy: Array = ((GameData.mbti.get("empathy", {}) as Dictionary).get(tf, {}) as Dictionary).get("react", {}).get(from, [])
	if emote_id in empathy:
		line = GameData.mbti_line("react_%s_%s" % [tf, from], values)
	if line.is_empty():
		line = GameData.dialogue_line(actor.info.personality, "react_" + emote_id, values)
	line = MoodSpeech.apply(line, mood, actor.info)
	actor.play_emote(emote_id, line)
