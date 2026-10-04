class_name QuestInfo
extends RefCounted
## 주민 부탁 하나 (서버가 만든다). `have`는 지금 인벤토리로 채운 개수.

var id: String = ""
var npc: String = ""
## NetProtocol.QUEST_*
var kind: String = ""
## 가져갈 아이템 id (아무 물고기면 빈 문자열).
var item: String = ""
var count: int = 1
var reward: int = 0
## 이 날짜(마을 날짜 번호)까지 유효.
var expires_day: int = 0
var have: int = 0


static func from_dict(data: Dictionary) -> QuestInfo:
	var q: QuestInfo = QuestInfo.new()
	q.id = str(data.get("id", ""))
	q.npc = str(data.get("npc", ""))
	q.kind = str(data.get("kind", ""))
	q.item = str(data.get("item", ""))
	q.count = int(data.get("n", 1))
	q.reward = int(data.get("reward", 0))
	q.expires_day = int(data.get("exp", 0))
	q.have = int(data.get("have", 0))
	return q


func is_ready() -> bool:
	return have >= count
