extends Node
## 마을톡 (v0.11) — 휴대폰 메신저의 상태. 서버가 보낸 대화방만 들고 있고, 보내기·읽음 요청을 보낸다.
## 대화방: npc:<주민> · sys:bank(은행·동사무소 알림) · sys:town(마을 공지) · sys:shop(상점 배달, v13) · pl:<자리>(같은 마을 친구).
## 메시지 = { f: 보낸 쪽('me' | 주민 id | 'bank' | 'town' | 'p<자리>'), tx: 글, at: 유닉스 ms }.

## 새 메시지 (내가 보낸 것 포함).
signal received(thread: String, message: Dictionary)
## 대화방 목록·읽음이 바뀌었다.
signal changed
signal failed(kind: String, code: String)

const KINDS: PackedStringArray = ["msg_send"]

## 대화방 id → { "m": Array[Dictionary], "read": int }
var threads: Dictionary = {}


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind in KINDS:
			failed.emit(kind, code))


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			threads.clear()
			var raw: Variant = msg.get("chats", {})
			if raw is Dictionary:
				for th: Variant in raw:
					var t: Dictionary = raw[th] if raw[th] is Dictionary else {}
					threads[str(th)] = {"m": (t.get("m", []) as Array).duplicate(), "read": int(t.get("read", 0))}
			changed.emit()
		"msg":
			var th: String = str(msg.get("th", ""))
			var m: Dictionary = msg.get("m", {}) if msg.get("m") is Dictionary else {}
			if th.is_empty() or m.is_empty():
				return
			if not threads.has(th):
				threads[th] = {"m": [], "read": 0}
			var list: Array = threads[th]["m"]
			list.append(m)
			if str(m.get("f", "")) == "me":
				threads[th]["read"] = list.size()
			received.emit(th, m)
			changed.emit()


## 보내기 (주민 · 친구 대화방만).
func send(thread: String, text: String) -> void:
	var tx: String = text.strip_edges()
	if tx.is_empty() or thread.begins_with("sys:"):
		return
	Net.request("msg_send", {"th": thread, "tx": tx.left(200)})


## 대화방을 열어 봤다 (안 읽은 표시를 지운다).
func mark_read(thread: String) -> void:
	if not threads.has(thread):
		return
	var size: int = (threads[thread]["m"] as Array).size()
	if int(threads[thread]["read"]) == size:
		return
	threads[thread]["read"] = size
	Net.send_message({"t": "msg_read", "th": thread})
	changed.emit()


func unread(thread: String) -> int:
	if not threads.has(thread):
		return 0
	return maxi(0, (threads[thread]["m"] as Array).size() - int(threads[thread]["read"]))


func unread_total() -> int:
	var n: int = 0
	for th: String in threads:
		n += unread(th)
	return n


## 최근 메시지가 위로 오게 정렬한 대화방 id. 친구 대화방은 메시지가 없어도 같은 마을 친구가 있으면 보인다.
func sorted_threads() -> PackedStringArray:
	var ids: Array[String] = []
	for th: String in threads:
		ids.append(th)
	for slot: int in Net.faces:
		var th: String = "pl:%d" % slot
		if slot != Net.my_id and not th in ids:
			ids.append(th)
	ids.sort_custom(func(a: String, b: String) -> bool: return last_at(a) > last_at(b))
	return PackedStringArray(ids)


func last_at(thread: String) -> float:
	var list: Array = threads.get(thread, {}).get("m", [])
	return float((list.back() as Dictionary).get("at", 0.0)) if not list.is_empty() else 0.0


func last_text(thread: String) -> String:
	var list: Array = threads.get(thread, {}).get("m", [])
	return fill(str((list.back() as Dictionary).get("tx", ""))) if not list.is_empty() else ""


## 대화방 이름: 주민 이름 · "솔바람 은행" · "마을 소식" · 친구 이름.
func title(thread: String) -> String:
	if thread.begins_with("npc:"):
		return GameData.npc_name(thread.trim_prefix("npc:"))
	if thread == "sys:bank":
		return "솔바람 은행 · 동사무소"
	if thread == "sys:town":
		return "마을 소식"
	if thread == "sys:shop":
		return "솔바람 상점 배달"
	if thread.begins_with("pl:"):
		return "%s (친구)" % GameData.player_name(int(thread.trim_prefix("pl:")))
	return thread


## 보낸 쪽 이름 (말풍선 위).
func sender_name(from: String) -> String:
	if from == "me":
		return GameData.player_name(Net.my_id)
	if from == "bank":
		return "은행"
	if from == "town":
		return "마을"
	if from == "courier":
		var c: NpcInfo = GameData.shop.courier if GameData.shop != null else null
		return "%s (배달)" % c.display_name if c != null else "배달 알바"
	if from.begins_with("p"):
		return GameData.player_name(int(from.trim_prefix("p")))
	return GameData.npc_name(from)


## 프로필 동그라미 색: 주민 색 · 은행 초록 · 친구 하늘.
func color_of(thread: String) -> Color:
	if thread.begins_with("npc:"):
		var info: NpcInfo = GameData.npcs.get(thread.trim_prefix("npc:"))
		return info.color if info != null else Color("#C8B8A8")
	if thread == "sys:bank":
		return Color("#5AAE7A")
	if thread == "sys:town":
		return Color("#E8B84A")
	if thread == "sys:shop":
		return Color("#F2A65A")
	return Color("#6AAEE8")


## 받는 사람 이름 채우기 ({player} = 내 이름).
func fill(text: String) -> String:
	return text.replace("{player}", GameData.player_name(Net.my_id))


func can_reply(thread: String) -> bool:
	return thread.begins_with("npc:") or thread.begins_with("pl:")
