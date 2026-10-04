class_name FlowerState
extends RefCounted
## 마을에 심은 꽃 한 송이 (서버가 알려 준다): 종류·색·자리·자란 단계(sprout/bud/bloom).

var id: String = ""
var species: String = ""
var color_index: int = 0
var position: Vector3 = Vector3.ZERO
var stage: String = NetProtocol.FLOWER_SPROUT


static func from_dict(data: Dictionary) -> FlowerState:
	var f: FlowerState = FlowerState.new()
	f.id = str(data.get("id", ""))
	f.species = str(data.get("sp", ""))
	f.color_index = int(data.get("c", 0))
	f.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	f.stage = str(data.get("s", NetProtocol.FLOWER_SPROUT))
	return f
