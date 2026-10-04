class_name FaceCatalog
extends RefCounted
## 얼굴 꾸미기 목록 (data/looks/face_parts.json): 눈·코·입 도형, 눈동자·피부·머리 색, 머리 모양, 자리별 기본 얼굴.
## 얼굴 설정은 {"eyes", "eye_color", "nose", "mouth", "skin", "hair", "hair_color"} 의 id 사전으로 주고받는다 (서버가 같은 파일로 검사).

const KEYS: PackedStringArray = ["eyes", "eye_color", "nose", "mouth", "skin", "hair", "hair_color"]

## 부품 하나: id, 이름, 도형 층(아래 → 위). 색 하나짜리 목록(피부·머리 색)은 layers 대신 colors 를 쓴다.
class Part:
	var id: String = ""
	var display_name: String = ""
	var layers: Array[Dictionary] = []
	## 피부: skin, cheeks / 색 목록: color
	var colors: Dictionary[String, Color] = {}


var anchors: Dictionary[String, Vector2] = {}
## 도형 색 이름 → 색 (ink, white, mouth, tongue …). 피부·눈동자처럼 사람마다 다른 색은 palette() 가 덧붙인다.
var colors: Dictionary[String, Color] = {}
var eyes: Array[Part] = []
var eye_colors: Array[Part] = []
var noses: Array[Part] = []
var mouths: Array[Part] = []
var skins: Array[Part] = []
var hair_styles: Array[Part] = []
var hair_colors: Array[Part] = []
var defaults: Array[Dictionary] = []
## 거울 앞 이 거리 안에서 얼굴을 바꿀 수 있다 (서버와 같은 값).
var mirror_range: float = 2.2


static func from_dict(data: Dictionary) -> FaceCatalog:
	var c: FaceCatalog = FaceCatalog.new()
	var raw_anchors: Dictionary = data.get("anchors", {})
	for key: String in raw_anchors:
		var a: Array = raw_anchors[key]
		c.anchors[key] = Vector2(float(a[0]), float(a[1]))
	var raw_colors: Dictionary = data.get("colors", {})
	for key: String in raw_colors:
		c.colors[key] = Color.html(str(raw_colors[key]))
	c.eyes = _parts(data.get("eyes", []))
	c.eye_colors = _parts(data.get("eye_colors", []))
	c.noses = _parts(data.get("noses", []))
	c.mouths = _parts(data.get("mouths", []))
	c.skins = _parts(data.get("skins", []))
	c.hair_styles = _parts(data.get("hair_styles", []))
	c.hair_colors = _parts(data.get("hair_colors", []))
	for d: Variant in data.get("defaults", []):
		if d is Dictionary:
			c.defaults.append(d)
	c.mirror_range = float((data.get("mirror", {}) as Dictionary).get("range", c.mirror_range))
	return c


static func _parts(list: Array) -> Array[Part]:
	var out: Array[Part] = []
	for raw: Variant in list:
		if not raw is Dictionary:
			continue
		var d: Dictionary = raw
		var p: Part = Part.new()
		p.id = str(d.get("id", ""))
		p.display_name = str(d.get("name", p.id))
		for layer: Variant in d.get("layers", []):
			if layer is Dictionary:
				p.layers.append(layer)
		for key: String in ["color", "skin", "cheeks"]:
			if d.has(key):
				p.colors[key] = Color.html(str(d[key]))
		out.append(p)
	return out


## 항목(eyes, nose …)의 목록.
func list(key: String) -> Array[Part]:
	match key:
		"eyes":
			return eyes
		"eye_color":
			return eye_colors
		"nose":
			return noses
		"mouth":
			return mouths
		"skin":
			return skins
		"hair":
			return hair_styles
		"hair_color":
			return hair_colors
	return []


func part(key: String, id: String) -> Part:
	for p: Part in list(key):
		if p.id == id:
			return p
	return null


## 자리(1, 2)의 기본 얼굴.
func default_face(slot: int) -> Dictionary:
	if defaults.is_empty():
		return {}
	return (defaults[clampi(slot - 1, 0, defaults.size() - 1)] as Dictionary).duplicate()


## 모르는 id·빠진 항목을 자리 기본값으로 채운 얼굴.
func sanitize(face: Variant, slot: int) -> Dictionary:
	var out: Dictionary = default_face(slot)
	if face is Dictionary:
		for key: String in KEYS:
			var id: String = str((face as Dictionary).get(key, ""))
			if part(key, id) != null:
				out[key] = id
	return out
