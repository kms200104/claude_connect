class_name SoundDirector
extends Node
## 마을의 사건 소리: 도끼질·아이템 얻기·선물·별 조각 줍기·상점 문 종·사고팔기·상점 성장·부탁 완료·천둥,
## 그리고 날씨와 시각에 맞춘 환경음(비·새·풀벌레)과 마을 배경음악. 발소리·낚시·대사 소리는 각자 낸다.

@export var sky: SkyController
@export var trees: TreeField
@export var shop: ShopController
@export var player: Player

var _thunder_index: int = 0


func _ready() -> void:
	Net.chop_succeeded.connect(_on_chop)
	Net.peer_action.connect(_on_peer_action)
	Net.quest_accepted.connect(func(_q: QuestInfo) -> void: Audio.play_ui(Audio.SFX_CONFIRM))
	Net.quest_completed.connect(func(_id: String, _npc: String, _reward: int) -> void: Audio.play_sfx("quest_done", -2.0, 1.0, 0.0))
	Net.shop_traded.connect(func(_kind: String, _item: String, _n: int, _amount: int) -> void: Audio.play_sfx("coin", -3.0))
	Net.shop_updated.connect(func(leveled_up: bool) -> void:
		if leveled_up:
			Audio.play_sfx("level_up", 0.0, 1.0, 0.0))
	Net.shop_door_passed.connect(func(_inside: bool, _p: Vector3) -> void: Audio.play_sfx("door_bell", -4.0, 1.0, 0.0))
	Net.furniture_placed.connect(func(info: PlacedInfo, _by: int) -> void: Audio.play_at("chop", info.position, -8.0, 0.8))
	Net.furniture_removed.connect(func(_id: String) -> void: Audio.play_sfx("pickup", -4.0))
	Net.lightning_struck.connect(_on_lightning)
	Net.collected.connect(func(kind: String, _item: String) -> void:
		Audio.play_sfx("twinkle" if kind == DropInfo.KIND_STAR else "pickup", -2.0)
		if kind == DropInfo.KIND_GIFT:
			Audio.play_sfx("quest_done", -6.0, 1.2, 0.0))
	Net.state_changed.connect(func(state: int) -> void:
		if state == Net.State.ONLINE:
			Audio.play_music(Audio.MUSIC_VILLAGE))


func _process(delta: float) -> void:
	if sky == null:
		return
	var indoor: float = 0.25 if sky.indoor else 1.0
	Audio.set_loop(Audio.LOOP_RAIN, sky.rain_amount * indoor, delta)
	var calm: float = clampf(1.0 - sky.clouds * 1.6, 0.0, 1.0) * (0.0 if sky.indoor else 1.0)
	Audio.set_loop(Audio.LOOP_BIRDS, smoothstep(0.5, 0.9, sky.daylight) * calm * 0.8, delta)
	Audio.set_loop(Audio.LOOP_CRICKETS, smoothstep(0.4, 0.05, sky.daylight) * (1.0 - sky.rain_amount) * (0.0 if sky.indoor else 0.7), delta)


## 도끼질 소리 (쓰러질 때의 우지끈·쿵은 TreeField 가 넘어지는 연출에 맞춰 낸다).
func _on_chop(_tree_id: String, item_id: String, _felled: bool) -> void:
	Audio.play_sfx("chop", -2.0)
	if not item_id.is_empty():
		await get_tree().create_timer(0.25).timeout
		Audio.play_sfx("pickup", -5.0)


func _on_peer_action(_id: int, kind: String, target: String) -> void:
	if kind == "chop" and trees != null:
		Audio.play_at("chop", trees.tree_position(target), -2.0)


## 번개: 번쩍인 뒤 조금 있다가 우르릉 (거리감). 실내에서는 작게.
func _on_lightning(power: float) -> void:
	await get_tree().create_timer(randf_range(0.4, 1.4)).timeout
	_thunder_index = (_thunder_index + 1) % 2
	var volume: float = linear_to_db(clampf(power, 0.2, 1.0)) + (-8.0 if sky != null and sky.indoor else 0.0)
	Audio.play_sfx("thunder_%d" % (_thunder_index + 1), volume, 1.0, 0.08)
