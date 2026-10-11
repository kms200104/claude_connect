class_name GuestReaction
extends PanelContainer
## 요리 결과 화면의 손님 반응 (v20): 그 손님이 별점만큼 기뻐하거나 시무룩해하고(작은 3D 무대에서 감정표현),
## 말풍선으로 한마디 + 까닭(단골 · 좋아하는/싫어하는 맛 · 솜씨 · 기다림)을 말한다. 아래 칩은 별점에 들어간 세 가지.
## 별점 · 돈은 서버가 매긴다. 여기 글은 그 결과(별점 · 솜씨 · 입맛)와 손님 취향 · MBTI 로 고른 화면용 반응이다.

const RIG_SCENE: PackedScene = preload("res://game/player/character_rig.tscn")
const INK: Color = Color(0.32, 0.2, 0.12)
const SOFT: Color = Color(0.52, 0.42, 0.32)
const GOOD: Color = Color("#5AAE5A")
const WARN: Color = Color("#E8604A")
const PORTRAIT: float = 280.0

var _rig: CharacterRig = null
var _speech: Label = null
var _lines: PackedStringArray = []
var _view: SubViewport = null


## 트리에 넣은 뒤 부른다. info: { stars, quality, time_left(남은 기다림 비율 0~1), regular, recipe(RecipeInfo), order }
func setup(customer: EconData.Customer, info: Dictionary) -> void:
	add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 1.0, 1.0, 0.8), Color(0.8, 0.7, 0.58), 28, 3, 16))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(_portrait(customer))
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	row.add_child(col)
	var who: String = customer.display_name if customer != null else "손님"
	var tail: String = ""
	if customer != null and customer.mbti.length() == 4:
		tail = " · %s" % customer.mbti
	if bool(info.get("regular", false)):
		tail += "  ♥단골"
	col.add_child(_label(who + tail, 28, SOFT))
	var bubble: PanelContainer = PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.98, 0.9), Color(0.85, 0.72, 0.5), 22, 3, 14))
	col.add_child(bubble)
	var stars: int = int(info.get("stars", 3))
	var recipe: RecipeInfo = info.get("recipe")
	_lines = lines(customer, recipe, stars, float(info.get("quality", 0.0)), float(info.get("time_left", 0.5)), bool(info.get("regular", false)), str(info.get("order", "")).hash())
	_speech = _label("\n".join(_lines), 30, INK)
	bubble.add_child(_speech)
	col.add_child(_chips(customer, recipe, float(info.get("quality", 0.0)), float(info.get("time_left", 0.5))))
	if _rig != null:
		var emote: String = emote_for(stars, false)
		get_tree().create_timer(0.35).timeout.connect(func() -> void:
			if is_instance_valid(_rig):
				_rig.play_emote(emote))


## 서버가 단골이 되었다 / 풀렸다고 알려 왔다 (rest_served): 한마디를 더하고 하트 · 한숨.
func regular_changed(became: bool, lost: bool) -> void:
	if not became and not lost:
		return
	var r: Dictionary = _reactions()
	_lines.append(str(r.get("regular_new" if became else "regular_lost", "")))
	if _speech != null:
		_speech.text = "\n".join(_lines)
	if _rig != null:
		_rig.play_emote("love" if became else "sad")


## 별점 → 감정표현.
static func emote_for(stars: int, became: bool) -> String:
	if became:
		return "love"
	match stars:
		5:
			return "clap"
		4:
			return "happy"
		3:
			return "think"
		2:
			return "sad"
	return "angry"


## 손님 한마디: 별점 첫마디 + 까닭 (단골 · 입맛 · 솜씨 · 기다림 가운데 두 가지까지).
static func lines(customer: EconData.Customer, recipe: RecipeInfo, stars: int, quality: float, time_left: float, regular: bool, seed_n: int) -> PackedStringArray:
	var r: Dictionary = _reactions()
	var dish: String = recipe.display_name if recipe != null else "요리"
	var out: PackedStringArray = []
	var firsts: Array = (r.get("stars", {}) as Dictionary).get(str(clampi(stars, 1, 5)), [])
	if not firsts.is_empty():
		out.append(str(firsts[absi(seed_n) % firsts.size()]).replace("{dish}", dish))
	var reasons: PackedStringArray = []
	if regular and stars >= 4:
		reasons.append(str(r.get("regular", "")).replace("{dish}", dish))
	var tags: Dictionary = r.get("tag", {})
	if customer != null and recipe != null:
		for t: String in recipe.tags:
			if t in customer.dislikes and stars <= 3:
				reasons.append(str(r.get("dislike", "")).replace("{tag}", str(tags.get(t, t))))
				break
		for t2: String in recipe.tags:
			if t2 in customer.likes and stars >= 3:
				reasons.append(str(r.get("like", "")).replace("{tag}", str(tags.get(t2, t2))))
				break
	var thinker: bool = customer != null and customer.mbti.length() == 4 and customer.mbti[2] == "T"
	if quality >= 0.9:
		reasons.append(str(r.get("skill_good_t" if thinker else "skill_good_f", "")))
	elif quality < 0.6:
		reasons.append(str(r.get("skill_bad_t" if thinker else "skill_bad_f", "")))
	if time_left < 0.25:
		reasons.append(str(r.get("late_t" if thinker else "late_f", "")))
	elif time_left > 0.7 and stars >= 3:
		reasons.append(str(r.get("fast", "")))
	for i: int in mini(2, reasons.size()):
		if not reasons[i].is_empty():
			out.append(reasons[i])
	return out


static func _reactions() -> Dictionary:
	return GameData.econ.restaurant.get("reactions", {}) if GameData.econ != null else {}


## 별점에 들어간 세 가지: 솜씨 · 입맛(좋아하는 ♥ / 싫어하는 ✕ 맛) · 기다림.
func _chips(customer: EconData.Customer, recipe: RecipeInfo, quality: float, time_left: float) -> Control:
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.add_child(_chip("솜씨 %d%%" % roundi(quality * 100.0), GOOD if quality >= 0.72 else (SOFT if quality >= 0.45 else WARN)))
	if customer != null and recipe != null:
		for t: String in recipe.tags:
			var name_t: String = str(EconData.TAG_NAMES.get(t, t))
			if t in customer.likes:
				flow.add_child(_chip("♥ %s" % name_t, GOOD))
			elif t in customer.dislikes:
				flow.add_child(_chip("✕ %s" % name_t, WARN))
	flow.add_child(_chip("빨리 나옴" if time_left > 0.7 else ("오래 기다림" if time_left < 0.25 else "기다림 보통"), GOOD if time_left > 0.7 else (WARN if time_left < 0.25 else SOFT)))
	return flow


func _chip(text: String, color: Color) -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", EventHud._box(Color(color, 0.14), Color(color, 0.7), 18, 2, 8))
	var l: Label = _label(text, 22, color.darkened(0.25))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	return p


## 손님 얼굴 무대: 그 손님의 겉모습 그대로 가슴 위까지, 별점만큼 감정표현.
func _portrait(customer: EconData.Customer) -> Control:
	var holder: SubViewportContainer = SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_2X
	holder.add_child(_view)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.98, 0.92, 0.84)
	env.ambient_light_energy = 0.6
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(150.0), 0.0)
	_view.add_child(sun)
	_rig = RIG_SCENE.instantiate()
	_view.add_child(_rig)
	if customer != null and customer.look != null:
		_rig.set_look(customer.look)
	_rig.set_held("")
	var cam: Camera3D = Camera3D.new()
	cam.fov = 26.0
	_view.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.48, -3.2), Vector3(0.0, 0.3, 0.0))
	cam.current = true
	return holder


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
