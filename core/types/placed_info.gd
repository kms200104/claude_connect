class_name PlacedInfo
extends RefCounted
## 마을에 설치된 가구 하나 (서버가 정한 위치·방향).

var id: String = ""
var item: String = ""
var position: Vector3 = Vector3.ZERO
## 90° 단위 회전 (0~3).
var rot: int = 0
## 놓은 사람의 자리 번호 (그 사람만 주울 수 있다).
var owner: int = 0


static func from_dict(data: Dictionary) -> PlacedInfo:
	var p: PlacedInfo = PlacedInfo.new()
	p.id = str(data.get("id", ""))
	p.item = str(data.get("item", ""))
	p.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	p.rot = int(data.get("rot", 0))
	p.owner = int(data.get("owner", 0))
	return p
