class_name DialogueController
extends Node
## 주민과의 대화 한 번. 서버에 말을 걸고(talk), 서버가 알려 준 상황(진행 중인 부탁 / 새 부탁 제안 / 그냥 수다)에 맞춰
## data/npcs/dialogue.json 에서 성격별 대사를 골라 보여 준다. 부탁 수락·완료는 서버에 요청하고 결과를 기다린다.
## 주민의 지금 기분(서버가 정한다)에 따라 말투가 바뀌고(MoodSpeech), 친해지면 감정표현을 가르쳐 주거나 선물을 준다.
## 그냥 수다일 때는 대화 주제(요즘 어때? · 취미 · 소문 · 물고기 · 옛날 이야기 · 꿈 · 음식 · 나 어때?)를 골라 이야기한다.
## 박물관 관장·공항 조종사는 상점 주인처럼 서버에 말을 걸지 않고 기증·기념품 창을 연다.

signal finished

@export_group("References")
@export var player: Player
@export var npcs: NpcCrowd
@export var box: DialogueBox
@export var toast_hud: FishingHud
## 상점 주인과 이야기하면 여는 창.
@export var shop_window: ShopWindow
@export var shop: ShopController
## 떠돌이 상인 (이벤트 날에만 광장에 선다).
@export var merchant: MerchantStall
@export var museum: MuseumSite
@export var airport: AirportSite
@export var museum_window: MuseumWindow

@export_group("Feel")
## 서버가 답하지 않으면 이 시간 뒤 대화를 접는다.
@export_range(1.0, 15.0, 0.5, "suffix:s") var reply_timeout: float = 5.0
## 날씨 이야기를 꺼낼 확률 (맑은 날 제외).
@export_range(0.0, 1.0, 0.05) var weather_talk_chance: float = 0.6
## 이벤트가 열린 날 주민이 이벤트 이야기를 꺼낼 확률.
@export_range(0.0, 1.0, 0.05) var event_talk_chance: float = 0.7
## 인사 뒤에 오늘 기분을 털어놓을 확률.
@export_range(0.0, 1.0, 0.05) var mood_talk_chance: float = 0.55
## 한 번 대화에서 고를 수 있는 주제 수 (그 뒤엔 작별 인사).
@export_range(1, 6) var max_topics: int = 3

var npc_id: String = ""
## 지금 대화하는 주민의 기분 (말투가 바뀐다). 상점 주인·상인·관장·조종사는 "".
var mood: String = ""
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
	if GameData.shop.keeper != null and id == GameData.shop.keeper.id:
		await _shopkeeper_flow()
		return
	if merchant != null and merchant.npc_id() == id:
		await _merchant_flow()
		return
	if museum != null and museum.npc_id() == id:
		await _curator_flow()
		return
	if airport != null and airport.npc_id() == id:
		await _pilot_flow()
		return
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
	mood = ""
	# 서버에 말을 건 건 마을 주민뿐이다.
	if GameData.npcs.has(npc_id):
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
		"reward": Money.digits(quest.reward if quest != null else 0),
	}
	var p: String = info.personality
	mood = reply.mood
	values["friend"] = reply.friendship

	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	if not reply.teach.is_empty():
		values["emote"] = GameData.emote_name(reply.teach)
		var actor: NpcActor = npcs.actor(info.id) if npcs != null else null
		if actor != null:
			actor.play_emote(reply.teach)
		if not await _say(token, info, GameData.dialogue_line(p, "teach", values)):
			return
		toast_hud.show_toast("'%s' 감정표현을 배웠어요!" % values["emote"], true)
		Audio.play_sfx("quest_done", -4.0, 1.1, 0.0)
	if not reply.gift.is_empty():
		values["item"] = GameData.item_name(reply.gift)
		if not await _say(token, info, GameData.dialogue_line(p, "gift", values)):
			return
		toast_hud.show_toast("%s을(를) 선물 받았어요!" % values["item"], true)
		Audio.play_sfx("quest_done", -3.0, 1.0, 0.0)
		values["item"] = _quest_item_name(quest)
	if randf() < mood_talk_chance:
		if not await _say(token, info, GameData.dialogue_line(p, "mood_" + mood, values)):
			return
	if Net.weather != NetProtocol.WEATHER_CLEAR and randf() < weather_talk_chance:
		if not await _say(token, info, GameData.dialogue_line(p, "weather_" + Net.weather, values)):
			return
	if not Net.events.is_empty() and randf() < event_talk_chance:
		var ev: ActiveEvent = Net.events[randi() % Net.events.size()]
		values["wanted"] = wanted_names(ev)
		if not await _say(token, info, GameData.dialogue_line(p, "event_" + ev.id, values)):
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
		await _topics_flow(token, info, values)
	if token == _session:
		stop()


## 대화 주제 고르기: 주제 몇 개를 보여 주고 고른 주제로 이야기한다 (서버에 알려 친밀도가 오른다). 작별을 고르면 끝.
func _topics_flow(token: int, info: NpcInfo, values: Dictionary) -> void:
	var talked: int = 0
	while token == _session and talked < max_topics:
		var topics: PackedStringArray = pick_topics(3, info)
		var labels: PackedStringArray = []
		for t: String in topics:
			labels.append(GameData.choice_text("topic_" + t))
		labels.append(GameData.choice_text("talk_bye"))
		if not await _say(token, info, GameData.dialogue_line(info.personality, "topic_ask" if talked == 0 else "topic_more", values)):
			return
		var pick: int = await _choose(token, labels)
		if pick < 0:
			return
		if pick >= topics.size():
			break
		var topic: String = topics[pick]
		Net.talk_topic(topic)
		for line: String in topic_lines(info, topic, values):
			if not await _say(token, info, line):
				return
		# 수다를 떨고 나면 기분이 바뀌었을 수도 있다 (서버가 알려 준다).
		mood = Net.npc_moods.get(info.id, mood)
		talked += 1
	if token == _session:
		await _say(token, info, GameData.dialogue_line(info.personality, "bye", values))


## 이번에 보여 줄 대화 주제 (무작위로 count 개). MBTI 의 S 는 음식·취미·물고기, N 은 꿈·옛날·MBTI 이야기를 더 자주 꺼낸다.
## "고민 상담" 은 늘 한 칸 (T/F 차이가 가장 잘 드러난다).
func pick_topics(count: int, info: NpcInfo = null) -> PackedStringArray:
	var pool: Array = Array(NetProtocol.TOPICS).filter(func(t: String) -> bool: return t != "worry")
	pool.shuffle()
	if info != null and randf() < 0.7:
		var liked: Array = (GameData.mbti.get("topic_bias", {}) as Dictionary).get(info.mbti_letter(1), [])
		var first: Array = pool.filter(func(t: String) -> bool: return t in liked)
		pool = first + pool.filter(func(t: String) -> bool: return not t in liked)
	var picked: Array = pool.slice(0, count - 1)
	picked.insert(randi() % count, "worry")
	return PackedStringArray(picked)


## 주제별 대사 (기분은 _say 에서 입힌다).
func topic_lines(info: NpcInfo, topic: String, values: Dictionary) -> PackedStringArray:
	var p: String = info.personality
	var lines: PackedStringArray = []
	match topic:
		"mood":
			lines.append(GameData.dialogue_line(p, "topic_mood_" + (mood if not mood.is_empty() else "calm"), values))
		"gossip":
			var others: Array = info.opinions.keys().filter(func(id: String) -> bool: return GameData.npcs.has(id))
			if others.is_empty():
				lines.append(GameData.dialogue_line(p, "chat", values))
			else:
				var other: String = others[randi() % others.size()]
				values["other"] = GameData.npc_name(other)
				lines.append(GameData.dialogue_line(p, "gossip_intro", values))
				lines.append(info.opinions[other])
		"fish":
			var fish: FishInfo = fish_tip()
			if fish == null:
				lines.append(GameData.dialogue_line(p, "chat", values))
			else:
				values["fish"] = fish.display_name
				values["when"] = fish_when(fish)
				lines.append(GameData.dialogue_line(p, "topic_fish", values))
				if Net.museum_fish.has(fish.id):
					lines.append(GameData.dialogue_line(p, "topic_fish_museum", values))
		"worry":
			# 고민 상담: F 는 같이 속상해하며 위로, T 는 원인·해결책부터 (그러다 어색하게 위로를 시도).
			var tf: String = "F" if info.is_feeler() else "T"
			lines.append(GameData.mbti_line("worry_open", values))
			lines.append(GameData.mbti_line("worry_" + tf, values))
			lines.append(GameData.mbti_line("worry_%s_after" % tf, values))
		"mbti":
			if info.mbti_self.is_empty():
				lines.append(GameData.dialogue_line(p, "chat", values))
			else:
				lines.append(info.mbti_self)
				var nick: String = GameData.mbti_nick(info.mbti)
				if not nick.is_empty():
					lines.append("(%s — %s. %s)" % [info.mbti, nick, "마음이 먼저 움직이는 F" if info.is_feeler() else "머리가 먼저 움직이는 T"])
		"you":
			var stage: int = mini(int(values.get("friend", 0)) / 20, 4)
			lines.append(GameData.dialogue_line(p, "topic_you_%d" % stage, values))
		_:
			var own: PackedStringArray = info.topics.get(topic, PackedStringArray())
			if own.is_empty():
				lines.append(GameData.dialogue_line(p, "topic_" + topic, values))
			else:
				lines.append(own[randi() % own.size()])
				var follow: String = GameData.dialogue_line(p, "topic_follow", values)
				if not follow.is_empty() and randf() < 0.5:
					lines.append(follow)
	return lines


## 물고기 이야기에 쓸 물고기: 지금 시각·날씨에 잡히는 것 중 귀한 걸 먼저 (없으면 아무거나).
static func fish_tip() -> FishInfo:
	var now: Array[FishInfo] = []
	for fish: FishInfo in GameData.fish.values():
		if fish.available(Net.game_hour(), Net.weather, Net.season()) and fish.rarity != "common":
			now.append(fish)
	if now.is_empty():
		for fish: FishInfo in GameData.fish.values():
			if fish.available(Net.game_hour(), Net.weather, Net.season()):
				now.append(fish)
	return now[randi() % now.size()] if not now.is_empty() else null


## "밤에", "비 오는 날에", "아무 때나" 처럼 짧게. 바다 물고기는 "바닷가에서 …" (v0.12).
static func fish_when(fish: FishInfo) -> String:
	var when: String = _fish_time(fish)
	if GameData.is_sea_fish(fish.id):
		return "바닷가에서 " + when
	return when


static func _fish_time(fish: FishInfo) -> String:
	if not fish.weathers.is_empty() and not "clear" in fish.weathers:
		return "비 오는 날에" if "rain" in fish.weathers else "흐린 날에"
	if fish.hours.size() == 2:
		var start: int = fish.hours[0]
		if start >= 17 or start < 4:
			return "해가 지고 나서"
		if start <= 6:
			return "아침 일찍"
		return "낮에"
	return "아무 때나"


## 상점 주인: 서버에 말을 걸지 않는다 (움직이지 않고, 여러 손님을 함께 받는다). 사고팔기는 상점 창에서 서버에 요청한다.
func _shopkeeper_flow() -> void:
	var token: int = _session
	var info: NpcInfo = GameData.shop.keeper
	var actor: NpcActor = shop.keeper if shop != null else null
	if actor != null:
		player.look_toward(actor.global_position - player.global_position)
	var values: Dictionary = {
		"player": GameData.player_name(Net.my_id),
		"shop": GameData.shop.level_info(Net.shop_level).display_name,
		"left": InventoryWindow._format_number(maxi(Net.shop_next - Net.shop_points, 0)),
	}
	var p: String = info.personality
	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	var bargain: ActiveEvent = Net.event_active(EventInfo.BARGAIN)
	if bargain != null:
		values["wanted"] = wanted_names(bargain)
		if not await _say(token, info, GameData.dialogue_line(p, "bargain", values)):
			return
	while token == _session:
		if not await _say(token, info, GameData.dialogue_line(p, "menu", values)):
			return
		var pick: int = await _choose(token, [GameData.choice_text("shop_buy"), GameData.choice_text("shop_sell"), GameData.choice_text("shop_talk"), GameData.choice_text("shop_leave")])
		if pick == 0 or pick == 1:
			box.close_quietly()
			shop_window.open(ShopWindow.MODE_BUY if pick == 0 else ShopWindow.MODE_SELL)
			await shop_window.closed
			if token != _session:
				return
			values["shop"] = GameData.shop.level_info(Net.shop_level).display_name
			values["left"] = InventoryWindow._format_number(maxi(Net.shop_next - Net.shop_points, 0))
		elif pick == 2:
			if not await _say(token, info, GameData.dialogue_line(p, "level_%d" % Net.shop_level, values)):
				return
			if not await _say(token, info, GameData.dialogue_line(p, "upgrade_hint" if Net.shop_next >= 0 else "max_level", values)):
				return
		else:
			break
	if token == _session:
		await _say(token, info, GameData.dialogue_line(p, "bye", values))
	if token == _session:
		stop()


## 떠돌이 상인: 상점 주인처럼 서버에 말을 걸지 않고, 사고팔기만 서버에 요청한다 (상인 곁에서만 된다).
func _merchant_flow() -> void:
	var token: int = _session
	var info: NpcInfo = merchant.info()
	var actor: NpcActor = merchant.actor
	if actor != null:
		player.look_toward(actor.global_position - player.global_position)
		actor.face_toward(player.global_position)
	var ev: ActiveEvent = Net.event_active(EventInfo.MERCHANT)
	var values: Dictionary = {"player": GameData.player_name(Net.my_id), "wanted": wanted_names(ev) if ev != null else ""}
	var p: String = info.personality
	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	if not await _say(token, info, GameData.dialogue_line(p, "wanted", values)):
		return
	while token == _session:
		if not await _say(token, info, GameData.dialogue_line(p, "menu", values)):
			return
		var pick: int = await _choose(token, [GameData.choice_text("merchant_buy"), GameData.choice_text("merchant_sell"), GameData.choice_text("merchant_talk"), GameData.choice_text("merchant_leave")])
		if pick == 0 or pick == 1:
			box.close_quietly()
			shop_window.open(ShopWindow.MODE_BUY if pick == 0 else ShopWindow.MODE_SELL, ShopWindow.AT_MERCHANT)
			await shop_window.closed
			if token != _session:
				return
		elif pick == 2:
			if not await _say(token, info, GameData.dialogue_line(p, "talk", values)):
				return
		else:
			break
	if token == _session:
		await _say(token, info, GameData.dialogue_line(p, "bye", values))
	if token == _session:
		stop()


## 박물관 관장 부엉: 물고기 기증 · 물고기 도감 · 물고기 이야기.
func _curator_flow() -> void:
	var token: int = _session
	var info: NpcInfo = museum.info()
	_face(museum.actor)
	var values: Dictionary = {"player": GameData.player_name(Net.my_id), "count": Net.museum_fish.size(), "total": GameData.fish.size()}
	var p: String = info.personality
	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	while token == _session:
		values["count"] = Net.museum_fish.size()
		if not await _say(token, info, GameData.dialogue_line(p, "menu", values)):
			return
		var pick: int = await _choose(token, [GameData.choice_text("museum_donate"), GameData.choice_text("museum_book"), GameData.choice_text("museum_talk"), GameData.choice_text("museum_leave")])
		if pick == 0:
			var thanks: Array = []
			var on_donated: Callable = func(fish_id: String, reward: int, count: int, gifts: PackedStringArray) -> void:
				thanks.append([fish_id, reward, count, gifts])
			Net.donated.connect(on_donated)
			var request: Callable = func(slot: int) -> void: Net.donate(slot)
			museum_window.donate_requested.connect(request)
			box.close_quietly()
			museum_window.open(MuseumWindow.MODE_DONATE)
			await museum_window.closed
			museum_window.donate_requested.disconnect(request)
			Net.donated.disconnect(on_donated)
			if token != _session:
				return
			for entry: Array in thanks.slice(0, 3):
				var fish: FishInfo = GameData.fish.get(str(entry[0]))
				values["fish"] = fish.display_name if fish != null else str(entry[0])
				values["desc"] = fish.description if fish != null else ""
				values["reward"] = Money.digits(int(entry[1]))
				values["count"] = int(entry[2])
				if not await _say(token, info, GameData.dialogue_line(p, "donate_thanks", values)):
					return
				for gift: String in entry[3]:
					values["item"] = GameData.item_name(gift)
					if not await _say(token, info, GameData.dialogue_line(p, "milestone", values)):
						return
					toast_hud.show_toast("%s을(를) 받았어요!" % values["item"], true)
			if thanks.is_empty():
				if not await _say(token, info, GameData.dialogue_line(p, "donate_none", values)):
					return
		elif pick == 1:
			box.close_quietly()
			museum_window.open(MuseumWindow.MODE_BOOK)
			await museum_window.closed
			if token != _session:
				return
		elif pick == 2:
			var fish2: FishInfo = GameData.fish.values()[randi() % GameData.fish.size()]
			values["fish"] = fish2.display_name
			values["desc"] = fish2.description
			if not await _say(token, info, GameData.dialogue_line(p, "talk", values)):
				return
		else:
			break
	if token == _session:
		await _say(token, info, GameData.dialogue_line(p, "bye", values))
	if token == _session:
		stop()


## 공항 조종사 제비: 여행 기념품 · 친구 초대 코드 · 하늘 이야기 (다음 비행기 시각).
func _pilot_flow() -> void:
	var token: int = _session
	var info: NpcInfo = airport.info()
	_face(airport.actor)
	var values: Dictionary = {"player": GameData.player_name(Net.my_id), "code": Net.room_code}
	var p: String = info.personality
	if not await _say(token, info, GameData.dialogue_line(p, "greet_" + VillageClock.time_band(Net.game_hour()), values)):
		return
	while token == _session:
		if not await _say(token, info, GameData.dialogue_line(p, "menu", values)):
			return
		var pick: int = await _choose(token, [GameData.choice_text("airport_shop"), GameData.choice_text("airport_invite"), GameData.choice_text("airport_talk"), GameData.choice_text("airport_leave")])
		if pick == 0:
			box.close_quietly()
			shop_window.open(ShopWindow.MODE_BUY, ShopWindow.AT_AIRPORT)
			await shop_window.closed
			if token != _session:
				return
		elif pick == 1:
			if not await _say(token, info, GameData.dialogue_line(p, "invite" if not Net.partner_present else "invite_together", values)):
				return
		elif pick == 2:
			values["minutes"] = maxi(int(ceil(airport.seconds_until_takeoff(Net.game_ms() / 1000.0) / 60.0)), 1)
			if not await _say(token, info, GameData.dialogue_line(p, "talk", values)):
				return
		else:
			break
	if token == _session:
		await _say(token, info, GameData.dialogue_line(p, "bye", values))
	if token == _session:
		stop()


func _face(actor: NpcActor) -> void:
	if actor == null:
		return
	player.look_toward(actor.global_position - player.global_position)
	actor.face_toward(player.global_position)


## 이벤트가 오늘 고른 물건 이름들 ("붕어, 목재").
static func wanted_names(ev: ActiveEvent) -> String:
	var names: PackedStringArray = []
	for id: String in ev.wanted:
		names.append(GameData.item_name(id))
	return ", ".join(names)


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
	values["reward"] = Money.digits(int(done[2]))
	await _say(token, info, GameData.dialogue_line(info.personality, "done", values))
	toast_hud.show_toast(Money.delta(int(done[2])), true)


## 한 줄 보여 주고 넘길 때까지 기다린다. 그 사이 대화가 끝났으면 false.
## 마을 주민은 지금 기분에 맞춰 말투를 바꾸고, 이름 옆에 기분을 적는다.
func _say(token: int, info: NpcInfo, line: String) -> bool:
	if token != _session:
		return false
	if line.is_empty():
		return true
	var shown: String = line
	var title: String = info.display_name
	if not mood.is_empty() and GameData.npcs.has(info.id):
		shown = MoodSpeech.apply(line, mood, info)
		title = "%s · %s" % [info.display_name, MoodSpeech.label(mood)] if info.mbti.is_empty() else "%s (%s) · %s" % [info.display_name, info.mbti, MoodSpeech.label(mood)]
	box.voice = info.voice
	box.show_line(title, shown, info.color.lightened(0.2))
	# 둘레 사람에게는 이 주민 머리 위 말풍선으로 들린다.
	Net.send_say(info.id, shown)
	await box.advanced
	return token == _session


func _choose(token: int, options: PackedStringArray) -> int:
	if token != _session:
		return -1
	box.show_choices(options)
	var index: int = await box.chosen
	if token == _session and index >= 0 and index < options.size():
		# 내가 고른 말도 내 머리 위 말풍선으로 들린다.
		Net.send_say("", options[index])
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
