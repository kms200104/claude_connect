class_name SoundDirector
extends Node
## 마을의 사건 소리: 도끼질·아이템 얻기·선물·별 조각 줍기·상점 문 종·사고팔기·상점 성장·부탁 완료·천둥,
## 그리고 날씨와 시각에 맞춘 환경음(비·새·풀벌레)과 마을 배경음악. 발소리·낚시·대사 소리는 각자 낸다.
## 배경음악은 1초마다 고른다 — 이벤트가 열려 있으면 이벤트 곡 > 비·뇌우면 비 곡 > 밤이면 밤 곡 > 낮 곡.
## 낮·밤이 바뀔 때는 천천히(time_fade), 비·이벤트는 조금 빠르게(weather_fade) 엇갈린다.

@export var sky: SkyController
@export var trees: TreeField
@export var shop: ShopController
@export var player: Player

## 밤 곡이 흐르는 시각 (마을 시각, 시). night_start 부터 다음 날 night_end 전까지.
@export_range(0.0, 24.0, 0.25) var night_start: float = 19.0
@export_range(0.0, 24.0, 0.25) var night_end: float = 5.5
## 엇갈리는 시간 (초).
@export_range(0.5, 10.0, 0.1) var time_fade: float = 4.0
@export_range(0.5, 10.0, 0.1) var weather_fade: float = 2.2

var _thunder_index: int = 0
var _music_timer: float = 0.0


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
			_update_music(true))
	Net.weather_changed.connect(func(_w: String) -> void: _update_music(false))
	Net.events_changed.connect(func(_started: PackedStringArray) -> void: _update_music(false))
	Prefs.events.changed.connect(func(key: String) -> void:
		if key == Prefs.MUSIC:
			_update_music(false))


## 지금 흘러야 할 마을 음악: 이벤트 > 비 > 밤 > 낮.
static func pick_music(hour: float, weather: String, event_active: bool, night_from: float = 19.0, night_to: float = 5.5) -> String:
	if event_active:
		return Audio.MUSIC_EVENT
	if weather == NetProtocol.WEATHER_RAIN or weather == NetProtocol.WEATHER_THUNDER:
		return Audio.MUSIC_RAIN
	var night: bool = hour >= night_from or hour < night_to if night_from > night_to else (hour >= night_from and hour < night_to)
	return Audio.MUSIC_NIGHT if night else Audio.MUSIC_VILLAGE


func _update_music(entering: bool) -> void:
	if Net.state != Net.State.ONLINE:
		return
	var track: String = pick_music(Net.game_hour(), Net.weather, not Net.events.is_empty(), night_start, night_end)
	# v16 음악 앱에서 곡을 골랐으면 그 곡 (끄기 = 조용히).
	var chosen: String = Prefs.music()
	if not chosen.is_empty():
		track = "" if chosen == Prefs.MUSIC_OFF else chosen
	var current: String = Audio.current_music()
	if track == current:
		return
	# 낮 ↔ 밤은 천천히, 비·이벤트로 바뀔 때는 조금 빠르게. 처음 들어올 때는 기본 빠르기.
	var day_night: bool = (current == Audio.MUSIC_VILLAGE and track == Audio.MUSIC_NIGHT) or (current == Audio.MUSIC_NIGHT and track == Audio.MUSIC_VILLAGE)
	Audio.play_music(track, -1.0 if entering else (time_fade if day_night else weather_fade))


func _process(delta: float) -> void:
	_music_timer -= delta
	if _music_timer <= 0.0:
		_music_timer = 1.0
		_update_music(false)
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
