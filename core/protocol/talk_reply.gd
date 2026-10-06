class_name TalkReply
extends RefCounted
## 서버의 talk_open: 주민이 말을 받아 줬다. 진행 중인 부탁이나 새 부탁 제안이 실려 올 수 있다.

var npc: String = ""
## 친밀도 0~100.
var friendship: int = 0
## 오늘 처음 말을 걸었는지.
var first_today: bool = false
## 이 주민에게 받은 진행 중인 부탁 (없으면 null).
var quest: QuestInfo = null
## quest 를 지금 완료할 수 있는지.
var ready: bool = false
## 새 부탁 제안 (없으면 null). 수락하면 quest_accept 를 보낸다.
var offer: QuestInfo = null
## 지금 기분 (말투가 바뀐다).
var mood: String = "calm"
## 이번에 가르쳐 준 감정표현 (없으면 빈 문자열).
var teach: String = ""
## 친해져서 챙겨 준 선물 아이템 (없으면 빈 문자열). 이미 가방에 들어 있다.
var gift: String = ""
## 오늘이 이 주민 생일 (v16). 그날 처음 말을 걸면 친밀도가 더 오른다.
var birthday: bool = false


static func from_dict(data: Dictionary) -> TalkReply:
	var r: TalkReply = TalkReply.new()
	r.npc = str(data.get("npc", ""))
	r.friendship = int(data.get("f", 0))
	r.first_today = bool(data.get("first", false))
	r.ready = bool(data.get("ready", false))
	r.mood = str(data.get("m", "calm"))
	r.teach = str(data.get("teach", ""))
	r.gift = str(data.get("gift", ""))
	r.birthday = bool(data.get("bday", false))
	var q: Variant = data.get("quest")
	if q is Dictionary:
		r.quest = QuestInfo.from_dict(q)
	var o: Variant = data.get("offer")
	if o is Dictionary:
		r.offer = QuestInfo.from_dict(o)
	return r
