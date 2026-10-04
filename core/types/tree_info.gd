class_name TreeInfo
extends RefCounted
## data/world/trees.json 의 나무 한 그루 (서버가 거리 판정에 쓰는 위치와 같은 값).

var id: String = ""
## pine(뾰족한 소나무) / round(둥근 활엽수)
var kind: String = "round"
var position: Vector3 = Vector3.ZERO
## 씨앗을 심어 생긴 나무 (서버가 알려 준다).
var planted: bool = false


static func from_dict(data: Dictionary) -> TreeInfo:
	var info: TreeInfo = TreeInfo.new()
	info.id = str(data.get("id", ""))
	info.kind = str(data.get("kind", "round"))
	info.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	return info


## 서버의 tree 메시지에 실려 온 심은 나무 (k, x, z).
static func planted_from_dict(data: Dictionary) -> TreeInfo:
	var info: TreeInfo = TreeInfo.new()
	info.id = str(data.get("id", ""))
	info.kind = str(data.get("k", "round"))
	info.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	info.planted = true
	return info
