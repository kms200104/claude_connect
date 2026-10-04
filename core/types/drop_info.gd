class_name DropInfo
extends RefCounted
## 바닥에 떨어진 것 하나 (선물 풍선 gift / 별 조각 star / 들판의 먹거리 forage). 선물 속 아이템은 주울 때까지 모른다.

const KIND_GIFT: String = "gift"
const KIND_STAR: String = "star"
## 나물·버섯·산딸기 (v8): 이벤트와 상관없이 들판에 늘 돋아난다. 식당 재료.
const KIND_FORAGE: String = "forage"

var id: String = ""
var kind: String = KIND_GIFT
var item: String = ""
var position: Vector3 = Vector3.ZERO


static func from_dict(data: Dictionary) -> DropInfo:
	var d: DropInfo = DropInfo.new()
	d.id = str(data.get("id", ""))
	d.kind = str(data.get("kind", KIND_GIFT))
	d.item = str(data.get("item", ""))
	d.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	return d
