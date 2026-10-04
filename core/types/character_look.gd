class_name CharacterLook
extends RefCounted
## 캐릭터 겉모습: 피부·머리·옷 색, 머리 모양, 눈·코·입 모양. 플레이어 두 명은 자리 번호(옷 색)와 거울에서 고른 얼굴로,
## 주민은 data/npcs/npcs.json 의 look 으로 정한다.
## CharacterRig 가 이 값으로 몸 메시를 칠한다 (같은 겉모습은 메시를 공유한다).

const STYLE_BOB: String = "bob"
const STYLE_SHORT: String = "short"
const STYLE_BUN: String = "bun"

var skin: Color = Color("#F7D5BC")
var cheeks: Color = Color("#F4A6A0")
var hair: Color = Color("#8A5638")
## data/looks/face_parts.json 의 hair_styles id (bob 단발, short 짧은 머리, bun 올림머리, long, pigtails …)
var hair_style: String = STYLE_BOB
## 눈·코·입 모양 (face_parts.json 의 eyes / noses / mouths id) 과 눈동자 색.
var eyes: String = "round"
var eye_color: Color = Color("#4A2E22")
var nose: String = "button"
var mouth: String = "smile"
var top: Color = Color("#F1E8D6")
var bottom: Color = Color("#9A6436")
var shoes: Color = Color("#7A4A30")


## 플레이어 자리(1, 2)마다 정해진 겉모습. 두 사람 화면에서 같은 사람이 같은 모습으로 보인다.
static func for_player(slot: int) -> CharacterLook:
	var look: CharacterLook = CharacterLook.new()
	if slot == 2:
		look.hair = Color("#3B3445")
		look.hair_style = STYLE_SHORT
		look.top = Color("#9ED3C6")
		look.bottom = Color("#5B7DA8")
		look.shoes = Color("#6E4B3A")
	return look


## {"hair": "#RRGGBB", "style": "bob", "top": …, "bottom": …, "shoes": …, "skin": …, "cheeks": …,
##  "eyes": "round", "nose": "button", "mouth": "smile", "eye_color": "#RRGGBB"}. 빠진 값은 기본값, 윗옷은 fallback_top.
static func from_dict(data: Variant, fallback_top: Color) -> CharacterLook:
	var look: CharacterLook = CharacterLook.new()
	look.top = fallback_top
	if not data is Dictionary:
		return look
	var d: Dictionary = data
	look.skin = Color.html(str(d.get("skin", look.skin.to_html(false))))
	look.hair = Color.html(str(d.get("hair", look.hair.to_html(false))))
	look.hair_style = str(d.get("style", look.hair_style))
	look.top = Color.html(str(d.get("top", look.top.to_html(false))))
	look.bottom = Color.html(str(d.get("bottom", look.bottom.to_html(false))))
	look.shoes = Color.html(str(d.get("shoes", look.shoes.to_html(false))))
	look.cheeks = Color.html(str(d.get("cheeks", look.cheeks.to_html(false))))
	look.eyes = str(d.get("eyes", look.eyes))
	look.nose = str(d.get("nose", look.nose))
	look.mouth = str(d.get("mouth", look.mouth))
	look.eye_color = Color.html(str(d.get("eye_color", look.eye_color.to_html(false))))
	return look


## 거울에서 고른 얼굴(FaceCatalog id 사전)을 입힌다. 모르는 id 는 그대로 둔다.
func apply_face(face: Dictionary, catalog: FaceCatalog) -> void:
	if catalog == null:
		return
	var skin_part: FaceCatalog.Part = catalog.part("skin", str(face.get("skin", "")))
	if skin_part != null:
		skin = skin_part.colors.get("skin", skin)
		cheeks = skin_part.colors.get("cheeks", cheeks)
	var hair_part: FaceCatalog.Part = catalog.part("hair_color", str(face.get("hair_color", "")))
	if hair_part != null:
		hair = hair_part.colors.get("color", hair)
	var eye_part: FaceCatalog.Part = catalog.part("eye_color", str(face.get("eye_color", "")))
	if eye_part != null:
		eye_color = eye_part.colors.get("color", eye_color)
	if catalog.part("hair", str(face.get("hair", ""))) != null:
		hair_style = str(face["hair"])
	if catalog.part("eyes", str(face.get("eyes", ""))) != null:
		eyes = str(face["eyes"])
	if catalog.part("nose", str(face.get("nose", ""))) != null:
		nose = str(face["nose"])
	if catalog.part("mouth", str(face.get("mouth", ""))) != null:
		mouth = str(face["mouth"])


func duplicate_look() -> CharacterLook:
	var copy: CharacterLook = CharacterLook.new()
	copy.skin = skin
	copy.cheeks = cheeks
	copy.hair = hair
	copy.hair_style = hair_style
	copy.top = top
	copy.bottom = bottom
	copy.shoes = shoes
	copy.eyes = eyes
	copy.eye_color = eye_color
	copy.nose = nose
	copy.mouth = mouth
	return copy


## 메시 캐시 키 (색과 모양이 같으면 같은 키).
func key() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [skin.to_html(false), hair.to_html(false), hair_style, top.to_html(false), bottom.to_html(false), shoes.to_html(false), cheeks.to_html(false), face_key()]


## 눈 메시 캐시 키 (눈 모양과 눈동자 색).
func eye_key() -> String:
	return "%s|%s" % [eyes, eye_color.to_html(false)]


func face_key() -> String:
	return "%s|%s|%s" % [eye_key(), nose, mouth]
