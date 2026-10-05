class_name LocalTestServer
extends Node
## 앱 안 테스트 서버 (v0.10): 진짜 서버(Node.js)에 연결할 수 없을 때 — 안드로이드 기기 하나만으로 — 게임을 돌려 볼 수 있게
## 같은 프로세스 안에서 WebSocket 서버(127.0.0.1)를 연다. 클라이언트(Net)는 진짜 서버와 똑같이 접속·요청한다.
## 입장 정보는 진짜 서버에서 찍어 둔 것(data/testserver/welcome.json, server/tools/make_test_snapshot.js)을 쓰고,
## 걷기 · 가방(옮기기·버리기·손에 들기) · 상점(드나들기·사고팔기) · 마을 가구 · 아파트 집 구경·꾸미기를 직접 처리한다.
## 그 밖의 요청(낚시·대화·식당 …)은 "test_server" 오류로 거절한다 — 혼자 테스트용이라 판정이 너그럽고 다른 사람이 없다.
## 상태는 user://test_server.json 에 저장된다.

const SNAPSHOT_PATH: String = "res://data/testserver/welcome.json"
const SAVE_PATH: String = "user://test_server.json"
const FIRST_PORT: int = 18680
const ROOM_CODE: String = "TEST01"
const ERR_TEST_ONLY: String = "test_server"
## 마을 시간대 (서버 기본 UTC+9).
const UTC_OFFSET_MS: float = 9.0 * 3600.0 * 1000.0

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


## 127.0.0.1 의 빈 포트에서 듣기 시작. 실패하면 false.
func start() -> bool:
	if _tcp != null and _tcp.is_listening():
		return true
	_snapshot = _read_json(SNAPSHOT_PATH)
	_shop_data = _read_json("res://data/shop/shop.json")
	if _snapshot.is_empty():
		push_error("LocalTestServer: %s 가 없음 (server/tools/make_test_snapshot.js)" % SNAPSHOT_PATH)
		return false
	_load()
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
	while _tcp.is_connection_available():
		var peer: WebSocketPeer = WebSocketPeer.new()
		if peer.accept_stream(_tcp.take_connection()) == OK:
			_peers.append(peer)
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
			var slot: int = int(msg.get("slot", -1))
			if slot >= 0 and slot < _slots.size() and _slots[slot] != null and not _is_tool(str(_slots[slot]["id"])):
				_remove(slot, maxi(1, int(msg.get("n", 1))))
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
		"bank_quote", "civic_info", "emote", "emote_quick", "talk_end", "fish_cancel":
			pass
		_:
			if rid != null:
				fail.call(ERR_TEST_ONLY)


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
	if saved.get("slots") is Array and (saved["slots"] as Array).size() == _slots.size():
		_slots = saved["slots"]
	_held = int(saved.get("held", _held))
	_sol = int(saved.get("sol", _sol))
	var p: Array = saved.get("pos", [0, 0])
	_pos = Vector3(float(p[0]), 0.1, float(p[1]))
	_home = str(saved.get("home", ""))
	_home_items = saved.get("home_items", {}) if saved.get("home_items") is Dictionary else {}
	_home_seq = int(saved.get("home_seq", 0))
	_placed = saved.get("placed", {}) if saved.get("placed") is Dictionary else {}
	_placed_seq = int(saved.get("placed_seq", 0))
	if not _home.is_empty() and GameData.econ.plan_of(_home) == null:
		_home = ""


func _save() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"slots": _slots, "held": _held, "sol": _sol, "pos": [_pos.x, _pos.z], "home": _home,
		"home_items": _home_items, "home_seq": _home_seq, "placed": _placed, "placed_seq": _placed_seq}))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
