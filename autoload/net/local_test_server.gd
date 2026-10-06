class_name LocalTestServer
extends Node
## 앱 안 테스트 서버 (v0.10): 진짜 서버(Node.js)에 연결할 수 없을 때 — 안드로이드 기기 하나만으로 — 게임을 돌려 볼 수 있게
## 같은 프로세스 안에서 WebSocket 서버(127.0.0.1)를 연다. 클라이언트(Net)는 진짜 서버와 똑같이 접속·요청한다.
## 입장 정보는 진짜 서버에서 찍어 둔 것(data/testserver/welcome.json, server/tools/make_test_snapshot.js)을 쓰고,
## 혼자 노는 데 필요한 것을 직접 처리한다: 걷기 · 가방(옮기기·버리기·손에 들기) · 상점(드나들기·사고팔기) · 마을 가구 ·
## 주민 대화(친밀도·수다) · 나무 베기(그루터기 → 다시 자람) · 낚시(입질·챔질) · 옷 입기 · 거울 얼굴 · 닉네임 · 씨앗 심기·꽃 따기 ·
## 들판 채집 · 아파트 집 구경·꾸미기. 나무·꽃은 진짜 서버보다 10배 빨리 자란다.
## 여럿이 하는 일·경제(식당·증권·은행·동사무소·혼인신고·여울 그물·삽)는 "test_server" 오류로 알려 준다 — 판정이 너그럽고 다른 사람이 없다.
## 상태는 user://test_server.json 에 저장된다.

const SNAPSHOT_PATH: String = "res://data/testserver/welcome.json"
const SAVE_PATH: String = "user://test_server.json"
const FIRST_PORT: int = 18680
const ROOM_CODE: String = "TEST01"
const ERR_TEST_ONLY: String = "test_server"
## 마을 시간대 (서버 기본 UTC+9).
const UTC_OFFSET_MS: float = 9.0 * 3600.0 * 1000.0
## 나무·꽃이 자라는 빠르기 (진짜 서버의 게임 분 → 실제 초: 1분 = 6초).
const GROW_MS_PER_MINUTE: float = 6000.0
const CHOPS_TO_FELL: int = 3
const FORAGE_MAX: int = 8
const FORAGE_EVERY_MS: float = 40000.0

var port: int = 0
var _tcp: TCPServer = null
var _peers: Array[WebSocketPeer] = []
var _snapshot: Dictionary = {}
var _shop_data: Dictionary = {}
# 저장되는 상태.
var _slots: Array = []
var _held: int = 0
var _sol: int = 0
var _pos: Vector3 = Vector3.ZERO
var _home: String = ""
var _home_items: Dictionary = {}
var _home_seq: int = 0
var _placed: Dictionary = {}
var _placed_seq: int = 0
var _outfit: Dictionary = {"hat": "", "top": ""}
## 닉네임 (v14).
var _name: String = ""
var _face: Dictionary = {}
var _friends: Dictionary = {}
## 친한 주민이 먼저 말 걸기 (테스트 서버의 주민은 걷지 않으니, 가까이 서 있을 때만): 주민 id → 마지막으로 건 시각.
var _greeted_at: Dictionary = {}
## 마을톡: 대화방 id → { m: [...], read }. 오늘 먼저 연락한 주민.
var _chats: Dictionary = {}
var _msg_day: Dictionary = {"day": "", "from": []}
var _next_msg_check_ms: float = 30000.0
var _next_greet_check_ms: float = 0.0
var _talk_days: Dictionary = {}
var _chat_today: Dictionary = {}
## 지금 이야기하는 주민.
var _talking: String = ""
var _planted: Dictionary = {}
var _plant_seq: int = 0
var _flowers: Dictionary = {}
var _flower_seq: int = 0
# 저장하지 않는 상태.
## 접속해 있는 사람 (혼자 쓰는 서버라 하나).
var _peer: WebSocketPeer = null
## 나무 id → { s, c } (데이터 나무 + 심은 나무)
var _trees: Dictionary = {}
## 바닥의 채집물 id → { id, kind, item, x, z }
var _drops: Dictionary = {}
var _drop_seq: int = 0
var _next_forage_ms: float = 0.0
## 낚시 중이면 { rid, fish, bite_at, window }
var _fishing: Dictionary = {}
## [시각(ms), Callable] — 입질 · 자라기
var _timers: Array = []
var _fish_weights: Dictionary = {}
var _spot_fish: Dictionary = {}
var _chop_drops: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## 127.0.0.1 의 빈 포트에서 듣기 시작. 실패하면 false.
func start() -> bool:
	if _tcp != null and _tcp.is_listening():
		return true
	_snapshot = _read_json(SNAPSHOT_PATH)
	_shop_data = _read_json("res://data/shop/shop.json")
	if _snapshot.is_empty():
		push_error("LocalTestServer: %s 가 없음 (server/tools/make_test_snapshot.js)" % SNAPSHOT_PATH)
		return false
	_rng.randomize()
	for f: Variant in _read_json("res://data/fish/fish.json").get("fish", []):
		_fish_weights[str(f["id"])] = float(f.get("weight", 10))
	for sp: Variant in _read_json("res://data/fish/spots.json").get("spots", []):
		_spot_fish[str(sp["id"])] = sp.get("fish", [])
	_chop_drops = _read_json("res://data/items/items.json").get("chop_drops", {})
	_load()
	for t: Variant in _snapshot.get("trees", []):
		_trees[str(t["id"])] = {"s": "grown", "c": 0}
	for id: String in _planted:
		_trees[id] = {"s": str(_planted[id].get("s", "grown")), "c": 0}
	_tcp = TCPServer.new()
	for p: int in range(FIRST_PORT, FIRST_PORT + 20):
		if _tcp.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	_tcp = null
	return false


func url() -> String:
	return "ws://127.0.0.1:%d" % port


func is_running() -> bool:
	return _tcp != null and _tcp.is_listening()


func _process(_delta: float) -> void:
	if _tcp == null:
		return
	var now: float = _now()
	var due: Array = []
	for t: Array in _timers:
		if now >= float(t[0]):
			due.append(t)
	for t: Array in due:
		_timers.erase(t)
		(t[1] as Callable).call()
	if _peer != null and now >= _next_forage_ms:
		_next_forage_ms = now + FORAGE_EVERY_MS
		_spawn_forage()
	if _peer != null and now >= _next_msg_check_ms:
		_next_msg_check_ms = now + 30000.0
		_maybe_text()
	if _peer != null and now >= _next_greet_check_ms:
		_next_greet_check_ms = now + 1000.0
		_maybe_greet()
	while _tcp.is_connection_available():
		var peer: WebSocketPeer = WebSocketPeer.new()
		if peer.accept_stream(_tcp.take_connection()) == OK:
			_peers.append(peer)
			_peer = peer
	for peer: WebSocketPeer in _peers.duplicate():
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var parsed: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
					if parsed is Dictionary:
						_handle(peer, parsed)
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(peer)


func _send(peer: WebSocketPeer, msg: Dictionary) -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(msg))


func _now() -> float:
	return float(Time.get_ticks_msec())


# ---- 요청 처리 ----

func _handle(peer: WebSocketPeer, msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	var rid: Variant = msg.get("rid")
	var fail: Callable = func(code: String) -> void: _send(peer, {"t": "error", "code": code, "rid": rid})
	match t:
		"ping":
			_send(peer, {"t": "pong", "c": msg.get("c", 0), "s": _now()})
		"create", "join", "resume":
			if int(msg.get("v", 0)) != NetProtocol.VERSION:
				fail.call(NetProtocol.ERR_BAD_VERSION)
				return
			var join_name: String = NetProtocol.clean_name(str(msg.get("name", "")))
			if not join_name.is_empty():
				_name = join_name
			_send(peer, _welcome(t == "resume"))
			if not _home.is_empty():
				_send(peer, _home_message(null))
		"move":
			_pos = Vector3(float(msg.get("x", _pos.x)), 0.1, float(msg.get("z", _pos.z)))
		"equip":
			var slot: int = int(msg.get("slot", -1))
			if slot >= -1 and slot < _quick():
				_held = slot
			_send_inventory(peer)
		"inv_move":
			_move_slot(int(msg.get("from", -1)), int(msg.get("to", -1)))
			_send_inventory(peer)
			_save()
		"inv_discard":
			# v13: 버린 물건은 발밑에 남는다 (다시 주울 수 있다).
			var slot: int = int(msg.get("slot", -1))
			if slot >= 0 and slot < _slots.size() and _slots[slot] != null and not _is_tool(str(_slots[slot]["id"])):
				var n: int = clampi(int(msg.get("n", 1)), 1, int(_slots[slot]["n"]))
				var item: String = str(_slots[slot]["id"])
				_remove(slot, n)
				_drop_seq += 1
				var k: float = float(_drop_seq % 12)
				var g: Dictionary = {"id": "g%d" % _drop_seq, "kind": "item", "item": item, "n": n,
					"x": _pos.x + cos(k * 2.4) * (0.25 + 0.2 * sqrt(k)), "z": _pos.z + sin(k * 2.4) * (0.25 + 0.2 * sqrt(k))}
				_drops[g["id"]] = g
				_send(peer, {"t": "drop", "d": g, "by": 1})
				_save()
			_send_inventory(peer)
		"shop_enter", "shop_exit":
			var inside: bool = t == "shop_enter"
			var spot: Dictionary = _shop_data.get("inside_spawn" if inside else "outside_spawn", {})
			_pos = Vector3(float(spot.get("x", 0.0)), 0.1, float(spot.get("z", 0.0)))
			_send(peer, {"t": "shop_door", "rid": rid, "inside": inside, "x": _pos.x, "y": _pos.y, "z": _pos.z, "shop": _snapshot.get("shop", {})})
		"shop_buy":
			if str(msg.get("at", "")) != "":
				fail.call(ERR_TEST_ONLY)
				return
			var item: String = str(msg.get("item", ""))
			var n: int = clampi(int(msg.get("n", 1)), 1, 99)
			var info: ItemInfo = GameData.item(item)
			if info == null or info.buy_price <= 0:
				fail.call(NetProtocol.ERR_NOT_FOR_SALE)
				return
			var cost: int = info.buy_price * n
			if _sol < cost:
				fail.call(NetProtocol.ERR_NOT_ENOUGH_SOL)
				return
			if not _add(item, n):
				fail.call(NetProtocol.ERR_INVENTORY_FULL)
				return
			_sol -= cost
			_send_inventory(peer)
			_send(peer, {"t": "shop_result", "rid": rid, "kind": "buy", "item": item, "n": n, "sol": _sol, "amount": cost, "back": 0})
			_save()
		"shop_sell":
			var slot: int = int(msg.get("slot", -1))
			if slot < 0 or slot >= _slots.size() or _slots[slot] == null:
				fail.call(NetProtocol.ERR_BAD_ITEM)
				return
			var item: String = str(_slots[slot]["id"])
			var info: ItemInfo = GameData.item(item)
			if info == null or info.price <= 0:
				fail.call(NetProtocol.ERR_CANT_SELL)
				return
			var n: int = mini(clampi(int(msg.get("n", 1)), 1, 99), int(_slots[slot]["n"]))
			_remove(slot, n)
			_sol += info.price * n
			_send_inventory(peer)
			_send(peer, {"t": "shop_result", "rid": rid, "kind": "sell", "item": item, "n": n, "sol": _sol, "amount": info.price * n, "back": 0})
			_save()
		"place":
			var slot: int = int(msg.get("slot", -1))
			if slot < 0 or slot >= _slots.size() or _slots[slot] == null or not _is_furniture(str(_slots[slot]["id"])):
				fail.call(NetProtocol.ERR_BAD_ITEM)
				return
			_placed_seq += 1
			var f: Dictionary = {"id": "f%d" % _placed_seq, "item": str(_slots[slot]["id"]), "x": snappedf(float(msg.get("x", 0.0)), 0.5), "z": snappedf(float(msg.get("z", 0.0)), 0.5), "rot": posmod(int(msg.get("rot", 0)), 4), "owner": 1}
			_remove(slot, 1)
			_placed[f["id"]] = f
			_send_inventory(peer)
			_send(peer, {"t": "placed", "rid": rid, "by": 1, "f": f})
			_save()
		"pickup":
			var f: Dictionary = _placed.get(str(msg.get("id", "")), {})
			if f.is_empty() or not _add(str(f["item"]), 1):
				fail.call(NetProtocol.ERR_BAD_PLACE)
				return
			_placed.erase(f["id"])
			_send_inventory(peer)
			_send(peer, {"t": "unplaced", "rid": rid, "id": f["id"]})
			_save()
		"home_enter", "home_exit", "home_place", "home_move", "home_pickup":
			_handle_home(peer, msg, fail)
		"talk":
			_talk(peer, msg, fail)
		"msg_send":
			_msg_send(msg, fail)
		"msg_read":
			var th: String = str(msg.get("th", ""))
			if _chats.has(th):
				_chats[th]["read"] = (_chats[th]["m"] as Array).size()
		"talk_topic":
			_talk_topic(peer, msg)
		"chop":
			_chop(peer, msg, fail)
		"fish_cast":
			_fish_cast(peer, msg, fail)
		"fish_hook":
			_fish_hook(peer, msg)
		"fish_reel":
			_fish_reel(peer, msg)
		"fish_cancel":
			if not _fishing.is_empty():
				_end_fishing(peer, {"ok": false, "reason": "cancelled"})
		"wear", "unwear":
			_wear(peer, msg, fail)
		"set_face":
			var face: Variant = msg.get("face", {})
			if not face is Dictionary:
				fail.call(NetProtocol.ERR_BAD_FACE)
				return
			if _face.is_empty():
				_face = ((_snapshot.get("players", [{}]) as Array)[0] as Dictionary).get("face", {}).duplicate()
			_face.merge(face, true)
			_send(peer, {"t": "face", "rid": rid, "id": 1, "face": _face})
			_save()
		"phone", "phone_tap":
			# 혼자 노는 테스트 서버: 다른 사람이 없으니 알릴 곳이 없다.
			pass
		"set_name":
			var raw: String = str(msg.get("name", ""))
			var clean: String = NetProtocol.clean_name(raw)
			if raw.strip_edges().length() > NetProtocol.NAME_MAX or (clean.is_empty() and not raw.strip_edges().is_empty()):
				fail.call(NetProtocol.ERR_BAD_NAME)
				return
			_name = clean
			_send(peer, {"t": "name", "rid": rid, "id": 1, "name": _name})
			_save()
		"plant":
			_plant(peer, msg, fail)
		"pick":
			_pick(peer, msg, fail)
		"collect":
			var d: Dictionary = _drops.get(str(msg.get("id", "")), {})
			if d.is_empty():
				fail.call(NetProtocol.ERR_NO_DROP)
				return
			var n: int = int(d.get("n", 1))
			if not _add(str(d["item"]), n):
				fail.call(NetProtocol.ERR_INVENTORY_FULL)
				return
			_drops.erase(d["id"])
			_send(peer, {"t": "collect_result", "rid": rid, "id": d["id"], "kind": d["kind"], "item": d["item"], "n": n, "left": 0})
			_send_inventory(peer)
			_send(peer, {"t": "drop_gone", "id": d["id"], "by": 1})
			_save()
		"talk_end":
			_talking = ""
		"bank_quote", "civic_info", "emote", "emote_quick", "say":
			pass
		"cal_info":
			_send(peer, _calendar())
		_:
			if rid != null:
				fail.call(ERR_TEST_ONLY)


# ---- 날씨 · 달력 (v16): 테스트 서버는 늘 맑고 이벤트가 없다. 주민 생일만 달력에 ----

func _calendar() -> Dictionary:
	var today: int = VillageClock.day_index(Time.get_unix_time_from_system() * 1000.0 + UTC_OFFSET_MS)
	var days: Array = []
	for i: int in 7:
		var date: Dictionary = VillageClock.date_of_day(today + i)
		var npcs: Array = []
		for npc: NpcInfo in GameData.npcs.values():
			if npc.birthday == Vector2i(int(date["month"]), int(date["day"])):
				npcs.append(npc.id)
		var noon: float = (float(today + i) * VillageClock.DAY_MS) + 12.0 * VillageClock.HOUR_MS
		days.append({"day": today + i, "y": int(date["year"]), "m": int(date["month"]), "d": int(date["day"]), "wd": int(date["weekday"]),
			"season": VillageClock.season_of(noon), "w": ["clear", "clear", "clear", "clear", "clear", "clear", "clear", "clear"], "ev": "", "meteor": false, "npc": npcs, "pl": []})
	return {"t": "cal", "today": today, "days": days, "econ": ""}


# ---- 마을톡 (주민과만: 친구는 테스트 서버에 없다) ----

func _chat_push(th: String, from: String, text: String) -> void:
	if not _chats.has(th):
		_chats[th] = {"m": [], "read": 0}
	var m: Dictionary = {"f": from, "tx": text, "at": Time.get_unix_time_from_system() * 1000.0}
	(_chats[th]["m"] as Array).append(m)
	if from == "me":
		_chats[th]["read"] = (_chats[th]["m"] as Array).size()
	if _peer != null:
		_send(_peer, {"t": "msg", "th": th, "m": m})
	_save()


func _msg_send(msg: Dictionary, fail: Callable) -> void:
	var th: String = str(msg.get("th", ""))
	var text: String = str(msg.get("tx", "")).strip_edges().left(200)
	if th.begins_with("pl:"):
		fail.call(ERR_TEST_ONLY)
		return
	var npc: String = th.trim_prefix("npc:")
	var lines: Dictionary = (GameData.messenger.get("lines", {}) as Dictionary).get(_personality_of(npc), {})
	if not th.begins_with("npc:") or text.is_empty() or lines.is_empty():
		fail.call(NetProtocol.ERR_BAD_MESSAGE)
		return
	_chat_push(th, "me", text)
	var replies: Array = lines.get("reply", [])
	_timers.append([_now() + _rng.randf_range(1500.0, 3500.0), func() -> void:
		if not replies.is_empty():
			_chat_push(th, npc, str(replies[_rng.randi() % replies.size()]))])


## 친한 주민이 하루 한 번씩 먼저 연락 (하루 3통까지).
func _maybe_text() -> void:
	var rules: Dictionary = GameData.messenger
	var today: String = Time.get_date_string_from_system()
	if _msg_day["day"] != today:
		_msg_day = {"day": today, "from": []}
	if (_msg_day["from"] as Array).size() >= int(rules.get("daily_max", 3)) or _rng.randf() > 0.5:
		return
	for n: Variant in _snapshot.get("npcs", []):
		var id: String = str(n["id"])
		var lines: Dictionary = (rules.get("lines", {}) as Dictionary).get(_personality_of(id), {})
		if lines.is_empty() or id in _msg_day["from"] or int(_friends.get(id, 0)) < int(rules.get("min_friendship", 4)):
			continue
		var pool: Array = lines.get("daily", []) + lines.get("shop", [])
		(_msg_day["from"] as Array).append(id)
		_chat_push("npc:" + id, id, str(pool[_rng.randi() % pool.size()]))
		return


func _personality_of(npc_id: String) -> String:
	var info: NpcInfo = GameData.npcs.get(npc_id)
	return info.personality if info != null else ""


# ---- 주민 대화 ----

func _maybe_greet() -> void:
	var rules: Dictionary = GameData.npc_approach
	if rules.is_empty() or not _talking.is_empty() or not _fishing.is_empty():
		return
	for n: Variant in _snapshot.get("npcs", []):
		var id: String = str(n["id"])
		if int(_friends.get(id, 0)) < int(rules.get("min_friendship", 6)) or _now() - float(_greeted_at.get(id, -INF)) < float(rules.get("cooldown_ms", 300000)):
			continue
		if Vector2(float(n["x"]) - _pos.x, float(n["z"]) - _pos.z).length() > 4.0 or _rng.randf() > float(rules.get("chance_per_s", 0.12)):
			continue
		_greeted_at[id] = _now()
		_send(_peer, {"t": "npc_greet", "npc": id})
		return


func _talk(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var npc: String = str(msg.get("npc", ""))
	if npc.is_empty():
		fail.call(NetProtocol.ERR_NOT_NEAR_NPC)
		return
	# 박물관 관장 · 조종사 같은 지기도 받아 준다 (기분은 보통).
	var mood: String = "calm"
	for n: Variant in _snapshot.get("npcs", []):
		if str(n["id"]) == npc:
			mood = str(n.get("m", "calm"))
	_talking = npc
	var today: String = Time.get_date_string_from_system()
	var first: bool = str(_talk_days.get(npc, "")) != today
	if first:
		_talk_days[npc] = today
		_friends[npc] = mini(100, int(_friends.get(npc, 0)) + 2)
		_send(peer, {"t": "profile", "sol": _sol, "friends": _friends})
	_send(peer, {"t": "talk_open", "rid": msg.get("rid"), "npc": npc, "f": int(_friends.get(npc, 0)), "first": first, "m": mood})
	_save()


func _talk_topic(peer: WebSocketPeer, msg: Dictionary) -> void:
	var npc: String = _talking
	if npc.is_empty():
		return
	var today: String = Time.get_date_string_from_system()
	var key: String = "%s/%s" % [npc, today]
	var gain: int = 1 if int(_chat_today.get(key, 0)) < 3 else 0
	_chat_today[key] = int(_chat_today.get(key, 0)) + 1
	_friends[npc] = mini(100, int(_friends.get(npc, 0)) + gain)
	_send(peer, {"t": "talk_topic", "npc": npc, "topic": msg.get("topic", ""), "f": int(_friends.get(npc, 0)), "gain": gain, "m": "happy"})
	if gain > 0:
		_send(peer, {"t": "profile", "sol": _sol, "friends": _friends})


# ---- 나무 베기 ----

func _chop(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var id: String = str(msg.get("tree", ""))
	if _held_id() != "axe":
		fail.call(NetProtocol.ERR_NO_TOOL)
		return
	if not _trees.has(id):
		fail.call(NetProtocol.ERR_NOT_NEAR_TREE)
		return
	var st: Dictionary = _trees[id]
	if str(st["s"]) != NetProtocol.TREE_GROWN:
		fail.call(NetProtocol.ERR_TREE_NOT_READY)
		return
	var kind: String = str(_planted[id]["k"]) if _planted.has(id) else _tree_kind(id)
	var item: String = _weighted(_chop_drops.get(kind, _chop_drops.get("round", [])))
	if not _add(item, 1):
		fail.call(NetProtocol.ERR_INVENTORY_FULL)
		return
	st["c"] = int(st["c"]) + 1
	var felled: bool = int(st["c"]) >= CHOPS_TO_FELL
	if felled:
		st["s"] = NetProtocol.TREE_STUMP
		st["c"] = 0
		_grow_tree(id, [NetProtocol.TREE_SAPLING, NetProtocol.TREE_YOUNG, NetProtocol.TREE_GROWN], [8, 10, 10])
	_send(peer, {"t": "chop_result", "rid": msg.get("rid"), "ok": true, "item": item, "n": 1, "tree": id, "felled": felled, "coop": false})
	_send_inventory(peer)
	_send_tree(id)
	_save()


func _tree_kind(id: String) -> String:
	var info: TreeInfo = GameData.trees.get(id)
	return info.kind if info != null else "round"


## 단계마다 minutes 게임 분(테스트 서버에서는 1분 = 6초) 뒤에 다음 단계로.
func _grow_tree(id: String, stages: Array, minutes: Array) -> void:
	var at: float = _now()
	for i: int in stages.size():
		at += float(minutes[i]) * GROW_MS_PER_MINUTE
		var stage: String = str(stages[i])
		_timers.append([at, func() -> void:
			if _trees.has(id):
				_trees[id]["s"] = stage
				if _planted.has(id):
					_planted[id]["s"] = stage
				_send_tree(id)])


func _send_tree(id: String) -> void:
	if _peer == null:
		return
	var wire: Dictionary = {"t": "tree", "id": id, "s": _trees[id]["s"], "c": _trees[id]["c"]}
	if _planted.has(id):
		wire.merge({"k": _planted[id]["k"], "x": _planted[id]["x"], "z": _planted[id]["z"]})
	_send(_peer, wire)


# ---- 낚시 ----

func _fish_cast(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var rid: Variant = msg.get("rid")
	if not _fishing.is_empty():
		fail.call(NetProtocol.ERR_ALREADY_FISHING)
		return
	if _held_id() != "rod":
		fail.call(NetProtocol.ERR_NO_TOOL)
		return
	var spot: String = str(msg.get("spot", ""))
	var pool: Array = _spot_fish.get(spot, [])
	if pool.is_empty():
		fail.call(NetProtocol.ERR_NOT_AT_SPOT)
		return
	# 제철 물고기만 (v0.12, 진짜 서버의 availableFish 처럼). 하나도 없으면 낚시터 전체에서.
	var season: String = VillageClock.season_of(Time.get_unix_time_from_system() * 1000.0 + UTC_OFFSET_MS)
	var in_season: Array = pool.filter(func(id: Variant) -> bool:
		var f: FishInfo = GameData.fish.get(str(id))
		return f == null or f.seasons.is_empty() or season in f.seasons)
	if not in_season.is_empty():
		pool = in_season
	var entries: Array = pool.map(func(id: Variant) -> Dictionary: return {"id": str(id), "weight": _fish_weights.get(str(id), 10.0)})
	var fish: String = _weighted(entries)
	var info: FishInfo = GameData.fish.get(fish)
	_fishing = {"rid": rid, "fish": fish, "bite_at": -1.0, "window": float(info.hook_window_ms if info != null else 700)}
	_send(peer, {"t": "fish_started", "rid": rid, "spot": spot, "zone": "deep", "coop": false, "shadow": _shadow_size(info)})
	var at: float = _now() + _rng.randf_range(2000.0, 4000.0)
	for i: int in _rng.randi_range(0, 2):
		_timers.append([at, func() -> void:
			if not _fishing.is_empty() and _fishing["rid"] == rid:
				_send(peer, {"t": "fish_nibble", "rid": rid})])
		at += _rng.randf_range(1500.0, 3000.0)
	_timers.append([at, func() -> void:
		if _fishing.is_empty() or _fishing["rid"] != rid:
			return
		_fishing["bite_at"] = _now()
		_send(peer, {"t": "fish_bite", "rid": rid, "windowMs": int(_fishing["window"])})
		_timers.append([_now() + float(_fishing["window"]) + 1500.0, func() -> void:
			if not _fishing.is_empty() and _fishing["rid"] == rid and not _fishing.has("reel"):
				_end_fishing(peer, {"ok": false, "reason": "escaped"})])])


func _fish_hook(peer: WebSocketPeer, msg: Dictionary) -> void:
	if _fishing.is_empty() or _fishing["rid"] != msg.get("rid"):
		return
	if float(_fishing["bite_at"]) < 0.0:
		_end_fishing(peer, {"ok": false, "reason": "early"})
		return
	var reaction: float = float(msg.get("reaction", 0.0))
	if reaction > float(_fishing["window"]):
		_end_fishing(peer, {"ok": false, "reason": "late"})
		return
	# 끌어올리기 연타 (진짜 서버의 reelNeed 와 같은 표).
	var info: FishInfo = GameData.fish.get(str(_fishing["fish"]))
	var rarity: String = info.rarity if info != null else "common"
	var size: String = info.size if info != null else "M"
	var base: Array = {"common": [6, 2600], "uncommon": [9, 3000], "rare": [13, 3400]}.get(rarity, [6, 2600])
	var taps: int = maxi(1, int(base[0]) + (2 if size == "L" else (-1 if size == "S" else 0)))
	var ms: int = int(base[1]) + (300 if size == "L" else 0)
	_fishing["reel"] = {"taps": taps, "ms": ms}
	_fishing["bite_at"] = -2.0
	var rid: Variant = _fishing["rid"]
	_send(peer, {"t": "fish_reel", "rid": rid, "taps": taps, "ms": ms})
	_timers.append([_now() + ms + 1500.0, func() -> void:
		if not _fishing.is_empty() and _fishing["rid"] == rid and _fishing.has("reel"):
			_end_fishing(peer, {"ok": false, "reason": "snapped"})])


func _fish_reel(peer: WebSocketPeer, msg: Dictionary) -> void:
	if _fishing.is_empty() or _fishing["rid"] != msg.get("rid") or not _fishing.has("reel"):
		return
	var need: Dictionary = _fishing["reel"]
	var counted: int = 0
	var prev: float = -INF
	for t: Variant in (msg.get("taps", []) as Array):
		var at: float = float(t)
		if at - prev >= 40.0 and at <= float(need["ms"]):
			counted += 1
		prev = maxf(prev, at)
	if counted < int(need["taps"]):
		_end_fishing(peer, {"ok": false, "reason": "snapped"})
		return
	var fish: String = str(_fishing["fish"])
	if not _add(fish, 1):
		_end_fishing(peer, {"ok": false, "reason": "inventory_full"})
		return
	_send_inventory(peer)
	_end_fishing(peer, {"ok": true, "fish": fish})
	_save()


## 물 밑 그림자 크기 (진짜 서버의 shadowSize 와 같은 표).
static func _shadow_size(info: FishInfo) -> float:
	if info == null:
		return 0.75
	var r: float = {"common": 0.75, "uncommon": 1.0, "rare": 1.35}.get(info.rarity, 0.75)
	var s: float = {"S": 0.85, "M": 1.0, "L": 1.2}.get(info.size, 1.0)
	return snappedf(r * s, 0.01)


func _end_fishing(peer: WebSocketPeer, result: Dictionary) -> void:
	var msg: Dictionary = {"t": "fish_result", "rid": _fishing.get("rid")}
	msg.merge(result)
	_fishing = {}
	_send(peer, msg)


# ---- 옷 ----

func _wear(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	if str(msg.get("t", "")) == "unwear":
		var part: String = str(msg.get("part", ""))
		if not _outfit.has(part) or str(_outfit[part]).is_empty():
			fail.call(NetProtocol.ERR_NOT_WEARABLE)
			return
		if not _add(str(_outfit[part]), 1):
			fail.call(NetProtocol.ERR_INVENTORY_FULL)
			return
		_outfit[part] = ""
	else:
		var slot: int = int(msg.get("slot", -1))
		var item: String = str(_slots[slot]["id"]) if slot >= 0 and slot < _slots.size() and _slots[slot] != null else ""
		var info: ItemInfo = GameData.item(item)
		if info == null or not info.is_clothing():
			fail.call(NetProtocol.ERR_NOT_WEARABLE)
			return
		var previous: String = str(_outfit.get(info.wear_slot, ""))
		_remove(slot, 1)
		if not previous.is_empty():
			_slots[slot] = {"id": previous, "n": 1}
		_outfit[info.wear_slot] = item
	_send_inventory(peer)
	_send(peer, {"t": "profile", "sol": _sol, "outfit": _outfit})
	_save()


# ---- 씨앗 심기 · 꽃 따기 ----

func _plant(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var seed: ItemInfo = GameData.item(_held_id())
	if seed == null or (seed.plant_tree.is_empty() and seed.plant_flower.is_empty()):
		fail.call(NetProtocol.ERR_NOT_SEED)
		return
	var x: float = snappedf(float(msg.get("x", 0.0)), 0.5)
	var z: float = snappedf(float(msg.get("z", 0.0)), 0.5)
	_remove(_held, 1)
	var kind: String = "tree" if not seed.plant_tree.is_empty() else "flower"
	var id: String = ""
	if kind == "tree":
		_plant_seq += 1
		id = "p%d" % _plant_seq
		_planted[id] = {"k": seed.plant_tree, "x": x, "z": z, "s": NetProtocol.TREE_SPROUT}
		_trees[id] = {"s": NetProtocol.TREE_SPROUT, "c": 0}
		_send_tree(id)
		_grow_tree(id, [NetProtocol.TREE_SAPLING, NetProtocol.TREE_YOUNG, NetProtocol.TREE_GROWN], [8, 10, 10])
	else:
		_flower_seq += 1
		id = "g%d" % _flower_seq
		var def: Dictionary = _flower_def(seed.plant_flower)
		var f: Dictionary = {"id": id, "sp": seed.plant_flower, "c": _rng.randi_range(0, maxi(0, (def.get("colors", [""]) as Array).size() - 1)), "x": x, "z": z, "s": "sprout"}
		_flowers[id] = f
		_send(peer, {"t": "flower", "f": _flower_wire(f), "by": 1})
		_grow_flower(id)
	_send(peer, {"t": "plant_result", "rid": msg.get("rid"), "id": id, "kind": kind, "x": x, "z": z})
	_send_inventory(peer)
	_save()


func _pick(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var f: Dictionary = _flowers.get(str(msg.get("id", "")), {})
	if f.is_empty() or str(f["s"]) != "bloom":
		fail.call(NetProtocol.ERR_NO_FLOWER)
		return
	var item: String = str(_flower_def(str(f["sp"])).get("item", f["sp"]))
	if not _add(item, 1):
		fail.call(NetProtocol.ERR_INVENTORY_FULL)
		return
	f["s"] = "bud"
	_send(peer, {"t": "pick_result", "rid": msg.get("rid"), "id": f["id"], "item": item})
	_send(peer, {"t": "flower", "f": _flower_wire(f), "by": 1})
	_send_inventory(peer)
	var def: Dictionary = _flower_def(str(f["sp"]))
	var id: String = str(f["id"])
	_timers.append([_now() + float(def.get("rebloom_minutes", 6)) * GROW_MS_PER_MINUTE, func() -> void: _set_flower(id, "bloom")])
	_save()


func _grow_flower(id: String) -> void:
	var def: Dictionary = _flower_def(str(_flowers[id]["sp"]))
	var minutes: Dictionary = def.get("minutes", {"sprout": 5, "bud": 5})
	var at: float = _now() + float(minutes.get("sprout", 5)) * GROW_MS_PER_MINUTE
	_timers.append([at, func() -> void: _set_flower(id, "bud")])
	at += float(minutes.get("bud", 5)) * GROW_MS_PER_MINUTE
	_timers.append([at, func() -> void: _set_flower(id, "bloom")])


func _set_flower(id: String, stage: String) -> void:
	if not _flowers.has(id):
		return
	_flowers[id]["s"] = stage
	if _peer != null:
		_send(_peer, {"t": "flower", "f": _flower_wire(_flowers[id])})
	_save()


func _flower_def(species: String) -> Dictionary:
	for f: Variant in _read_json("res://data/plants/plants.json").get("flowers", []):
		if str(f["id"]) == species:
			return f
	return {}


static func _flower_wire(f: Dictionary) -> Dictionary:
	return {"id": f["id"], "sp": f["sp"], "c": f["c"], "x": f["x"], "z": f["z"], "s": f["s"]}


# ---- 들판 채집 (나무 곁 풀숲에 돋는다 — 섬 안 땅이 틀림없는 자리) ----

func _spawn_forage() -> void:
	if _drops.values().filter(func(d: Dictionary) -> bool: return d.get("kind") == "forage").size() >= FORAGE_MAX or GameData.trees.is_empty():
		return
	var items: Array = (_read_json("res://data/restaurant/restaurant.json").get("forage", {}) as Dictionary).get("items", [])
	var trees: Array = GameData.trees.values()
	var tree: TreeInfo = trees[_rng.randi_range(0, trees.size() - 1)]
	var angle: float = _rng.randf() * TAU
	_drop_seq += 1
	var d: Dictionary = {"id": "t%d" % _drop_seq, "kind": "forage", "item": _weighted(items),
		"x": snappedf(tree.position.x + cos(angle) * 2.4, 0.1), "z": snappedf(tree.position.z + sin(angle) * 2.4, 0.1)}
	_drops[d["id"]] = d
	_send(_peer, {"t": "drop", "d": d})


func _held_id() -> String:
	return str(_slots[_held]["id"]) if _held >= 0 and _held < _slots.size() and _slots[_held] != null else ""


func _weighted(entries: Array) -> String:
	var total: float = 0.0
	for e: Dictionary in entries:
		total += float(e.get("weight", 1))
	var r: float = _rng.randf() * total
	for e: Dictionary in entries:
		r -= float(e.get("weight", 1))
		if r <= 0.0:
			return str(e["id"])
	return str(entries[-1]["id"]) if not entries.is_empty() else ""


# ---- 집 안 (서버 homes.js 와 같은 규칙, 테스트 서버에서는 어느 집이든 내 집처럼 꾸밀 수 있다) ----

func _handle_home(peer: WebSocketPeer, msg: Dictionary, fail: Callable) -> void:
	var econ: EconData = GameData.econ
	var t: String = str(msg.get("t", ""))
	if t == "home_enter":
		var unit: String = str(msg.get("unit", ""))
		var plan: FloorPlan = econ.plan_of(unit)
		if plan == null:
			fail.call(NetProtocol.ERR_BAD_UNIT)
			return
		_home = unit
		_pos = econ.home_origin(unit) + Vector3(plan.spawn.x, 0.1, plan.spawn.y)
		_send(peer, _home_message(msg.get("rid")))
		_save()
		return
	if _home.is_empty():
		fail.call(NetProtocol.ERR_NOT_HOME)
		return
	var plan: FloorPlan = econ.plan_of(_home)
	if t == "home_exit":
		var building: String = _home.split("-")[0]
		_home = ""
		_pos = econ.lobby_of(building) + Vector3(0.0, 0.1, 0.6)
		_send(peer, {"t": "home", "rid": msg.get("rid"), "unit": "", "x": _pos.x, "y": _pos.y, "z": _pos.z})
		_save()
		return
	var list: Array = _home_list(_home, true)
	var g: float = float(econ.home_rules.get("grid", 0.25))
	var at: Vector2 = Vector2(snappedf(float(msg.get("x", 0.0)), g), snappedf(float(msg.get("z", 0.0)), g))
	match t:
		"home_place":
			var slot: int = int(msg.get("slot", -1))
			if slot < 0 or slot >= _slots.size() or _slots[slot] == null or not _is_furniture(str(_slots[slot]["id"])):
				fail.call(NetProtocol.ERR_BAD_ITEM)
				return
			if not plan.on_floor(at, 0.05):
				fail.call(NetProtocol.ERR_BAD_PLACE)
				return
			_home_seq += 1
			list.append({"id": "h%d" % _home_seq, "item": str(_slots[slot]["id"]), "x": at.x, "z": at.y, "rot": posmod(int(msg.get("rot", 0)), 8)})
			_remove(slot, 1)
			_send_inventory(peer)
		"home_move":
			var f: Dictionary = _find(list, str(msg.get("id", "")))
			if f.is_empty() or not plan.on_floor(at, 0.05):
				fail.call(NetProtocol.ERR_BAD_PLACE)
				return
			f["x"] = at.x
			f["z"] = at.y
			f["rot"] = posmod(int(msg.get("rot", 0)), 8)
		"home_pickup":
			var f: Dictionary = _find(list, str(msg.get("id", "")))
			if f.is_empty():
				fail.call(NetProtocol.ERR_BAD_PLACE)
				return
			if not _add(str(f["item"]), 1):
				fail.call(NetProtocol.ERR_INVENTORY_FULL)
				return
			list.erase(f)
			_send_inventory(peer)
	_send(peer, {"t": "home_f", "rid": msg.get("rid"), "unit": _home, "f": _furniture_wire(list)})
	_save()


func _home_message(rid: Variant) -> Dictionary:
	var econ: EconData = GameData.econ
	var plan: FloorPlan = econ.plan_of(_home)
	var o: Vector3 = econ.home_origin(_home)
	return {"t": "home", "rid": rid, "unit": _home, "plan": plan.id if plan != null else "", "ox": o.x, "oz": o.z, "owner": 1, "edit": true,
		"x": _pos.x, "y": _pos.y, "z": _pos.z, "f": _furniture_wire(_home_list(_home, false))}


## 그 집 가구 목록 (아직 손대지 않은 집은 평면도의 기본 가구). make = 기본 가구를 그 집 것으로 만든다.
func _home_list(unit: String, make: bool) -> Array:
	if _home_items.has(unit):
		return _home_items[unit]
	var list: Array = []
	var plan: FloorPlan = GameData.econ.plan_of(unit)
	if plan != null:
		for i: int in plan.defaults.size():
			var d: FloorPlan.Default = plan.defaults[i]
			list.append({"id": "d%d" % (i + 1), "item": d.item, "x": d.position.x, "z": d.position.y, "rot": d.rot})
	if make:
		_home_items[unit] = list
	return list


static func _furniture_wire(list: Array) -> Array:
	var out: Array = []
	for f: Dictionary in list:
		out.append([f["id"], f["item"], snappedf(float(f["x"]), 0.001), snappedf(float(f["z"]), 0.001), int(f["rot"])])
	return out


static func _find(list: Array, id: String) -> Dictionary:
	for f: Dictionary in list:
		if str(f["id"]) == id:
			return f
	return {}


# ---- 입장 정보 · 가방 ----

func _welcome(resumed: bool) -> Dictionary:
	var w: Dictionary = _snapshot.duplicate(true)
	w["id"] = 1
	w["token"] = "local-test-token"
	w["code"] = ROOM_CODE
	w["resumed"] = resumed
	w["st"] = _now()
	w["clock"] = {"g": Time.get_unix_time_from_system() * 1000.0 + UTC_OFFSET_MS, "s": 1, "st": _now()}
	w["inv"] = _inventory_wire()
	var prof: Dictionary = w.get("prof", {})
	prof["sol"] = _sol
	w["prof"] = prof
	var players: Array = w.get("players", [])
	if not players.is_empty():
		players[0]["x"] = _pos.x
		players[0]["z"] = _pos.z
	w["placed"] = _placed.values()
	if not _face.is_empty() and not players.is_empty():
		players[0]["face"] = _face
		prof["face"] = _face
	prof["outfit"] = _outfit
	prof["name"] = _name
	if not players.is_empty():
		players[0]["name"] = _name
	if not players.is_empty():
		players[0]["hat"] = _outfit["hat"]
		players[0]["top"] = _outfit["top"]
	prof["friends"] = _friends
	var trees: Array = []
	for id: String in _trees:
		var wire: Dictionary = {"id": id, "s": _trees[id]["s"], "c": _trees[id]["c"]}
		if _planted.has(id):
			wire.merge({"k": _planted[id]["k"], "x": _planted[id]["x"], "z": _planted[id]["z"]})
		trees.append(wire)
	w["trees"] = trees
	w["flowers"] = _flowers.values().map(func(f: Dictionary) -> Dictionary: return _flower_wire(f))
	w["drops"] = _drops.values()
	if _chats.is_empty():
		_chats["sys:town"] = {"m": [{"f": "town", "tx": str(GameData.messenger.get("welcome", "")) + " (테스트 서버에서는 주민과만 이야기할 수 있어요.)", "at": Time.get_unix_time_from_system() * 1000.0}], "read": 0}
	w["chats"] = _chats
	return w


func _inventory_wire() -> Dictionary:
	var inv: Dictionary = (_snapshot.get("inv", {}) as Dictionary).duplicate(true)
	inv["slots"] = _slots
	inv["held"] = _held
	return inv


func _send_inventory(peer: WebSocketPeer) -> void:
	var msg: Dictionary = _inventory_wire()
	msg["t"] = "inventory"
	_send(peer, msg)
	_send(peer, {"t": "profile", "sol": _sol})


func _quick() -> int:
	return int((_snapshot.get("inv", {}) as Dictionary).get("quick", 5))


func _is_tool(id: String) -> bool:
	var info: ItemInfo = GameData.item(id)
	return info != null and info.kind == "tool"


func _is_furniture(id: String) -> bool:
	var info: ItemInfo = GameData.item(id)
	return info != null and info.is_furniture()


func _limit(id: String) -> int:
	var info: ItemInfo = GameData.item(id)
	return 1 if info == null or info.kind in ["tool", "furniture", "clothing"] else 30


func _add(id: String, n: int) -> bool:
	var left: int = n
	for s: Variant in _slots:
		if s != null and str(s["id"]) == id and int(s["n"]) < _limit(id):
			var put: int = mini(_limit(id) - int(s["n"]), left)
			s["n"] = int(s["n"]) + put
			left -= put
	for i: int in range(_quick(), _slots.size()):
		if left <= 0:
			break
		if _slots[i] == null:
			var put: int = mini(_limit(id), left)
			_slots[i] = {"id": id, "n": put}
			left -= put
	return left <= 0


func _remove(slot: int, n: int) -> void:
	var s: Dictionary = _slots[slot]
	s["n"] = int(s["n"]) - n
	if int(s["n"]) <= 0:
		_slots[slot] = null


func _move_slot(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= _slots.size() or to >= _slots.size() or from == to or _slots[from] == null:
		return
	var a: Dictionary = _slots[from]
	var b: Variant = _slots[to]
	if b != null and str(b["id"]) == str(a["id"]):
		var put: int = mini(_limit(str(a["id"])) - int(b["n"]), int(a["n"]))
		if put > 0:
			b["n"] = int(b["n"]) + put
			a["n"] = int(a["n"]) - put
			if int(a["n"]) <= 0:
				_slots[from] = null
			return
	_slots[from] = b
	_slots[to] = a


# ---- 저장 ----

func _load() -> void:
	var inv: Dictionary = _snapshot.get("inv", {})
	_slots = (inv.get("slots", []) as Array).duplicate(true)
	_held = int(inv.get("held", 0))
	_sol = int((_snapshot.get("prof", {}) as Dictionary).get("sol", 0))
	var saved: Dictionary = _read_json(SAVE_PATH)
	if saved.is_empty():
		return
	if saved.get("slots") is Array:
		# 가방 칸 수가 바뀌었어도(v13: 20 → 30) 있던 칸은 같은 자리에 둔다.
		var old_slots: Array = saved["slots"]
		for i: int in mini(old_slots.size(), _slots.size()):
			_slots[i] = old_slots[i]
	for g: Variant in saved.get("ground", []):
		if g is Dictionary and str(g.get("id", "")).begins_with("g") and GameData.item(str(g.get("item", ""))) != null:
			_drops[str(g["id"])] = g
	_drop_seq = int(saved.get("drop_seq", _drop_seq))
	_held = int(saved.get("held", _held))
	_sol = int(saved.get("sol", _sol))
	var p: Array = saved.get("pos", [0, 0])
	_pos = Vector3(float(p[0]), 0.1, float(p[1]))
	_home = str(saved.get("home", ""))
	_chats = saved.get("chats", {}) if saved.get("chats") is Dictionary else {}
	_home_items = saved.get("home_items", {}) if saved.get("home_items") is Dictionary else {}
	_home_seq = int(saved.get("home_seq", 0))
	_placed = saved.get("placed", {}) if saved.get("placed") is Dictionary else {}
	_placed_seq = int(saved.get("placed_seq", 0))
	if saved.get("outfit") is Dictionary:
		_outfit = saved["outfit"]
	if saved.get("face") is Dictionary:
		_face = saved["face"]
	_name = NetProtocol.clean_name(str(saved.get("name", "")))
	if saved.get("friends") is Dictionary:
		_friends = saved["friends"]
	if saved.get("talk_days") is Dictionary:
		_talk_days = saved["talk_days"]
	if saved.get("planted") is Dictionary:
		_planted = saved["planted"]
	_plant_seq = int(saved.get("plant_seq", 0))
	if saved.get("flowers") is Dictionary:
		_flowers = saved["flowers"]
		# 저장했다 다시 켜면 덜 자란 꽃은 활짝 핀 것으로 (테스트 서버는 자라는 타이머를 저장하지 않는다).
		for f: Dictionary in _flowers.values():
			f["s"] = "bloom"
	_flower_seq = int(saved.get("flower_seq", 0))
	for planted: Dictionary in _planted.values():
		planted["s"] = NetProtocol.TREE_GROWN
	if not _home.is_empty() and GameData.econ.plan_of(_home) == null:
		_home = ""


func _save() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"slots": _slots, "held": _held, "sol": _sol, "pos": [_pos.x, _pos.z], "home": _home,
		"home_items": _home_items, "home_seq": _home_seq, "placed": _placed, "placed_seq": _placed_seq,
		"outfit": _outfit, "face": _face, "name": _name, "friends": _friends, "talk_days": _talk_days,
		"planted": _planted, "plant_seq": _plant_seq, "flowers": _flowers, "flower_seq": _flower_seq, "chats": _chats,
		"ground": _drops.values().filter(func(d: Dictionary) -> bool: return d.get("kind") == "item"), "drop_seq": _drop_seq}))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
