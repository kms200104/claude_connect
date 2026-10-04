class_name FlowerSpecies
extends RefCounted
## data/plants/plants.json 의 꽃 한 종류 (튤립·코스모스·해바라기·수국). 심을 때 서버가 색을 하나 고른다.

var id: String = ""
var display_name: String = ""
## 따면 얻는 아이템.
var item: String = ""
var colors: Array[Color] = []


static func from_dict(data: Dictionary) -> FlowerSpecies:
	var info: FlowerSpecies = FlowerSpecies.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.item = str(data.get("item", ""))
	for c: Variant in data.get("colors", []):
		info.colors.append(Color.html(str(c)))
	if info.colors.is_empty():
		info.colors.append(Color.WHITE)
	return info


func color(index: int) -> Color:
	return colors[clampi(index, 0, colors.size() - 1)]
