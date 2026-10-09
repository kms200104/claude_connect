class_name FoodArt
extends RefCounted
## 주방 장면의 재료 그림 (2D, 그때그때 도형으로 그린다). 재료마다 모양이 다르고 익힘(cook)에 따라 색 · 무늬가 바뀐다.
##   cook: 0 = 날것, 1 = 딱 알맞게 익음, 1 넘으면 지나쳐 타 간다 (2 = 새까맣게).
##   생선은 그 물고기의 몸 색 · 무늬(FishInfo)로 옆으로 누운 모습, 소고기는 마블링 · 지방 띠, 삼겹살은 비계 · 살 층,
##   닭은 오돌토돌한 껍질, 표고는 별 모양 칼집, 조개는 익으면 입을 벌린다. 다 익으면 석쇠 자국 · 칼집이 짙어진다.
## draw_food 는 팬 · 도마 위의 통째 모습, draw_piece 는 그릇 · 냄비 · 웍 속 작은 조각, bar 는 썰기용 길쭉한 모습.

const GOLDEN: Color = Color(0.88, 0.6, 0.28)
const BURNT: Color = Color(0.2, 0.13, 0.09)
const MARK: Color = Color(0.32, 0.17, 0.08)

const VEG: PackedStringArray = ["radish", "scallion", "chili", "garlic", "onion", "potato", "shiitake", "wild_greens", "mugwort", "wild_chive", "lemon", "tofu"]
const SEASONING: PackedStringArray = ["soy_sauce", "doenjang", "sesame_oil", "sugar", "butter", "flour", "rice", "laver", "egg"]

## 생선 몸 높이 (몸길이 2 기준) — 모양별.
const FISH_HEIGHT: Dictionary[String, float] = {"eel": 0.13, "loach": 0.14, "lamprey": 0.12, "ribbon": 0.11, "halfbeak": 0.12, "bream": 0.46,
	"carp": 0.38, "goldfish": 0.44, "puffer": 0.48, "tuna": 0.34, "sturgeon": 0.22, "shark": 0.24, "hammerhead": 0.24, "catfish": 0.26, "snakehead": 0.22, "goby": 0.24}


## 재료 id → 그림 종류.
static func kind_of(id: String) -> String:
	if GameData.fish.has(id):
		match GameData.fish[id].shape:
			"crayfish":
				return "crab"
			"turtle":
				return "turtle"
		return "fish"
	match id:
		"pork_belly":
			return "belly"
		"beef":
			return "steak"
		"chicken":
			return "chicken"
		"shiitake":
			return "mushroom"
		"clam_manila", "surf_clam", "corbicula":
			return "clam"
		"razor_clam":
			return "razor"
		"pen_shell":
			return "scallop"
		"egg":
			return "egg"
		"potato":
			return "potato"
		"tofu":
			return "tofu"
		"jeon":
			return "jeon"
	return id


## 재료 기본 색 (아이템 색, 물고기는 살빛).
static func base_color(id: String) -> Color:
	if GameData.fish.has(id):
		return flesh_color(id)
	match kind_of(id):
		"belly":
			return Color(0.93, 0.6, 0.6)
		"steak":
			return Color(0.72, 0.16, 0.2)
		"chicken":
			return Color(0.96, 0.8, 0.72)
	var info: ItemInfo = GameData.item(id)
	return info.color if info != null else Color(0.95, 0.85, 0.5)


## 생선 살빛 (회 · 토막): 참치 · 방어는 붉게, 송어류는 주황, 나머지는 흰 살.
static func flesh_color(id: String) -> Color:
	match id:
		"bluefin_tuna":
			return Color(0.78, 0.18, 0.22)
		"yellowtail", "mackerel":
			return Color(0.9, 0.62, 0.58)
		"rainbow_trout", "cherry_salmon":
			return Color(0.96, 0.56, 0.38)
		"eel", "conger":
			return Color(0.96, 0.92, 0.84)
	return Color(0.97, 0.9, 0.86)


## 익힘에 따라 바뀐 색. tint = 익었을 때 쪽으로 얼마나 (생선 0.55 · 고기 1).
static func cooked(raw: Color, done: Color, cook: float, tint: float = 1.0) -> Color:
	var c: Color = raw.lerp(done, clampf(cook, 0.0, 1.0) * tint)
	if cook > 1.0:
		c = c.lerp(BURNT, clampf((cook - 1.0) * 1.1, 0.0, 1.0))
	return c


# ---- 통째 모습 (팬 · 석쇠 · 도마) ----

## pos 에 size(px, 몸길이) 크기로. under >= 0 이면 아랫면(그 익힘 색)이 테두리로 살짝 비친다.
static func draw_food(ci: CanvasItem, id: String, pos: Vector2, size: float, cook: float, under: float = -1.0, rot: float = 0.0, squash: float = 1.0) -> void:
	var s: float = size * 0.5
	if under >= 0.0:
		ci.draw_set_transform(pos + Vector2(0.0, size * 0.045), rot, Vector2(s * 1.02, s * squash * 1.04))
		_draw_kind(ci, id, under, true)
	ci.draw_set_transform(pos, rot, Vector2(s, s * squash))
	_draw_kind(ci, id, cook, false)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _draw_kind(ci: CanvasItem, id: String, cook: float, silhouette: bool) -> void:
	match kind_of(id):
		"fish":
			_fish(ci, id, cook, silhouette)
		"crab":
			_crab(ci, id, cook, silhouette)
		"turtle":
			_turtle(ci, id, cook, silhouette)
		"steak":
			_steak(ci, cook, silhouette)
		"belly":
			_belly(ci, cook, silhouette)
		"chicken":
			_chicken(ci, cook, silhouette)
		"mushroom":
			_mushroom(ci, cook, silhouette)
		"clam":
			_clam(ci, id, cook, silhouette)
		"razor":
			_razor(ci, cook, silhouette)
		"scallop":
			_scallop(ci, cook, silhouette)
		"egg":
			_egg(ci, cook, silhouette)
		"jeon":
			_jeon(ci, cook, silhouette)
		"potato":
			_round_food(ci, Vector2(0.95, 0.7), Color(0.86, 0.72, 0.44), cook, silhouette, Color(0.6, 0.45, 0.25))
		"tofu":
			_tofu(ci, cook, silhouette)
		_:
			_round_food(ci, Vector2(0.9, 0.7), base_color(id), cook, silhouette, Color(0, 0, 0, 0))


static func _fish(ci: CanvasItem, id: String, cook: float, silhouette: bool) -> void:
	var f: FishInfo = GameData.fish.get(id)
	var shape: String = f.shape if f != null else "slim"
	var h: float = FISH_HEIGHT.get(shape, 0.3)
	var body_c: Color = f.body_color if f != null else Color(0.6, 0.62, 0.58)
	var belly_c: Color = f.belly_color if f != null else Color(0.92, 0.9, 0.82)
	var fin_c: Color = f.fin_color if f != null else body_c.darkened(0.2)
	var tint: float = 0.6
	var top: PackedVector2Array = []
	var bottom: PackedVector2Array = []
	for i: int in 19:
		var u: float = float(i) / 18.0
		var x: float = -1.0 + 1.7 * u
		var half: float = h * (sin(PI * pow(u, 0.72)) * 0.9 + 0.1)
		top.append(Vector2(x, -half))
		bottom.append(Vector2(x, half * 0.95))
	var body: PackedVector2Array = top.duplicate()
	for i: int in range(bottom.size() - 1, -1, -1):
		body.append(bottom[i])
	var tail: PackedVector2Array = [Vector2(0.62, -h * 0.18), Vector2(1.0, -h * 0.85 - 0.06), Vector2(0.86, 0.0), Vector2(1.0, h * 0.85 + 0.06), Vector2(0.62, h * 0.18)]
	if silhouette:
		var c: Color = cooked(belly_c, GOLDEN, cook, 1.0)
		ci.draw_colored_polygon(body, c)
		ci.draw_colored_polygon(tail, c)
		return
	var fin: PackedVector2Array = [Vector2(-0.3, -h * 0.85), Vector2(0.0, -h * 1.0 - 0.14), Vector2(0.3, -h * 0.7)]
	ci.draw_colored_polygon(fin, cooked(fin_c, GOLDEN.darkened(0.2), cook, tint))
	ci.draw_colored_polygon(tail, cooked(fin_c, GOLDEN.darkened(0.15), cook, tint))
	ci.draw_colored_polygon(body, cooked(body_c, GOLDEN, cook, tint))
	var belly: PackedVector2Array = []
	for i: int in bottom.size():
		belly.append(Vector2(bottom[i].x, bottom[i].y * 0.12))
	for i: int in range(bottom.size() - 1, -1, -1):
		belly.append(bottom[i] * Vector2(1.0, 0.98))
	ci.draw_colored_polygon(belly, cooked(belly_c, GOLDEN.lightened(0.15), cook, tint))
	var pattern: String = f.pattern if f != null else "none"
	var accent: Color = cooked(f.accent_color if f != null else body_c.darkened(0.3), MARK, cook, 0.5)
	match pattern:
		"stripe":
			ci.draw_line(Vector2(-0.6, -h * 0.05), Vector2(0.6, -h * 0.02), Color(accent, 0.7), 0.035)
		"band":
			for x: float in [-0.35, 0.0, 0.32]:
				ci.draw_line(Vector2(x, -h * 0.75), Vector2(x + 0.04, h * 0.6), Color(accent, 0.6), 0.07)
		"spots":
			for p: Vector2 in [Vector2(-0.3, -0.4), Vector2(-0.05, -0.5), Vector2(0.2, -0.35), Vector2(0.4, -0.45), Vector2(0.05, -0.15)]:
				ci.draw_circle(Vector2(p.x, p.y * h), h * 0.09 + 0.01, Color(accent, 0.75))
	# 칼집 (익을수록 짙게) · 석쇠 자국
	var slash: Color = Color(MARK, 0.25 + 0.5 * clampf(cook, 0.0, 1.0))
	for x: float in [-0.32, 0.0, 0.3]:
		ci.draw_line(Vector2(x - 0.04, -h * 0.62), Vector2(x + 0.06, h * 0.45), slash, 0.03)
	if cook > 0.45:
		var a: float = clampf((cook - 0.45) * 1.4, 0.0, 0.75)
		for x: float in [-0.48, -0.16, 0.16, 0.44]:
			ci.draw_line(Vector2(x + 0.12, -h * 0.7), Vector2(x - 0.12, h * 0.7), Color(MARK, a), 0.05)
	ci.draw_arc(Vector2(-0.64, 0.0), h * 0.6, -1.1, 1.1, 10, Color(cooked(body_c, MARK, cook, 0.5).darkened(0.25), 0.7), 0.025)
	var eye: Vector2 = Vector2(-0.8 if h < 0.2 else -0.76, -h * 0.28)
	var er: float = clampf(h * 0.24, 0.035, 0.085)
	if cook >= 0.7:
		ci.draw_circle(eye, er, Color(0.97, 0.96, 0.92))
		ci.draw_circle(eye, er * 0.35, Color(0.7, 0.68, 0.64))
	else:
		ci.draw_circle(eye, er, Color(0.98, 0.98, 0.96))
		ci.draw_circle(eye, er * 0.75, f.iris_color if f != null else Color(0.8, 0.6, 0.2))
		ci.draw_circle(eye, er * 0.45, Color(0.06, 0.05, 0.05))
		ci.draw_circle(eye + Vector2(-er * 0.3, -er * 0.3), er * 0.2, Color.WHITE)
	if f != null and f.barbels:
		ci.draw_line(Vector2(-0.95, h * 0.05), Vector2(-1.15, h * 0.4), Color(fin_c, 0.9), 0.02)
		ci.draw_line(Vector2(-0.95, h * 0.05), Vector2(-1.12, -h * 0.25), Color(fin_c, 0.9), 0.02)
	_gloss(ci, Vector2(-0.2, -h * 0.55), Vector2(0.3, h * 0.12 + 0.02), cook)


static func _crab(ci: CanvasItem, id: String, cook: float, silhouette: bool) -> void:
	var f: FishInfo = GameData.fish.get(id)
	var raw: Color = f.body_color if f != null else Color(0.45, 0.4, 0.35)
	var c: Color = cooked(raw, Color(0.9, 0.32, 0.18), cook, 1.0)
	if silhouette:
		_ellipse(ci, Vector2.ZERO, Vector2(0.75, 0.46), c)
		return
	for side: float in [-1.0, 1.0]:
		for k: int in 4:
			var root: Vector2 = Vector2(side * 0.5, -0.1 + k * 0.12)
			var knee: Vector2 = root + Vector2(side * 0.32, -0.06 + k * 0.04)
			ci.draw_line(root, knee, c.darkened(0.15), 0.07)
			ci.draw_line(knee, knee + Vector2(side * 0.16, 0.2), c.darkened(0.2), 0.05)
		var arm: Vector2 = Vector2(side * 0.42, -0.42)
		ci.draw_line(Vector2(side * 0.3, -0.25), arm, c.darkened(0.1), 0.09)
		_ellipse(ci, arm + Vector2(side * 0.12, -0.12), Vector2(0.2, 0.13), c)
		ci.draw_line(arm + Vector2(side * 0.18, -0.2), arm + Vector2(side * 0.3, -0.12), c.darkened(0.3), 0.04)
	_ellipse(ci, Vector2.ZERO, Vector2(0.72, 0.44), c)
	_ellipse(ci, Vector2(0.0, 0.08), Vector2(0.5, 0.25), c.lightened(0.12))
	for side2: float in [-0.14, 0.14]:
		ci.draw_circle(Vector2(side2, -0.42), 0.05, Color(0.1, 0.08, 0.06))
	_gloss(ci, Vector2(-0.2, -0.18), Vector2(0.22, 0.07), cook)


static func _turtle(ci: CanvasItem, id: String, cook: float, silhouette: bool) -> void:
	var f: FishInfo = GameData.fish.get(id)
	var shell: Color = cooked(f.body_color if f != null else Color(0.4, 0.45, 0.3), GOLDEN.darkened(0.3), cook, 0.5)
	if silhouette:
		_ellipse(ci, Vector2.ZERO, Vector2(0.8, 0.55), shell)
		return
	var skin: Color = cooked(f.belly_color if f != null else Color(0.6, 0.6, 0.45), GOLDEN, cook, 0.5)
	for p: Vector2 in [Vector2(-0.55, -0.42), Vector2(0.55, -0.42), Vector2(-0.55, 0.42), Vector2(0.55, 0.42)]:
		_ellipse(ci, p, Vector2(0.18, 0.12), skin)
	_ellipse(ci, Vector2(-0.95, 0.0), Vector2(0.22, 0.16), skin)
	ci.draw_circle(Vector2(-1.05, -0.05), 0.03, Color(0.1, 0.1, 0.1))
	_ellipse(ci, Vector2.ZERO, Vector2(0.8, 0.55), shell)
	_ellipse(ci, Vector2.ZERO, Vector2(0.62, 0.4), shell.lightened(0.1))
	_gloss(ci, Vector2(-0.2, -0.25), Vector2(0.28, 0.08), cook)


static func _steak(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var outline: PackedVector2Array = _blob(Vector2(0.95, 0.62), [0.0, 0.06, -0.04, 0.05, 0.02, -0.06, 0.04, 0.0, -0.03, 0.05, 0.03, -0.02])
	var meat: Color = cooked(Color(0.74, 0.16, 0.2), Color(0.52, 0.28, 0.15), cook)
	if silhouette:
		ci.draw_colored_polygon(outline, meat)
		return
	var fat: PackedVector2Array = []
	for p: Vector2 in outline:
		fat.append(p * 1.06 + Vector2(0.0, -0.04))
	ci.draw_colored_polygon(fat, cooked(Color(0.96, 0.9, 0.84), Color(0.92, 0.7, 0.42), cook))
	ci.draw_colored_polygon(outline, meat)
	var marble: Color = Color(1.0, 0.94, 0.9, 0.55 * (1.0 - clampf(cook, 0.0, 1.0) * 0.7))
	for line: Array in [[Vector2(-0.6, -0.2), Vector2(-0.3, -0.05), Vector2(-0.1, -0.2), Vector2(0.2, -0.05)], [Vector2(-0.3, 0.25), Vector2(0.0, 0.1), Vector2(0.3, 0.25), Vector2(0.55, 0.1)], [Vector2(0.3, -0.35), Vector2(0.5, -0.2), Vector2(0.65, -0.3)]]:
		ci.draw_polyline(PackedVector2Array(line), marble, 0.03)
	_grill_marks(ci, Vector2(0.78, 0.48), cook, true)
	_gloss(ci, Vector2(-0.3, -0.3), Vector2(0.3, 0.08), cook)


static func _belly(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var w: float = 1.0
	var hh: float = 0.36
	if silhouette:
		_round_rect(ci, Rect2(-w, -hh, w * 2.0, hh * 2.0), 0.12, cooked(Color(0.97, 0.92, 0.86), GOLDEN, cook))
		return
	var layers: Array = [[0.12, Color(0.94, 0.8, 0.7), Color(0.74, 0.44, 0.2)], [0.16, Color(0.98, 0.94, 0.9), Color(0.96, 0.78, 0.46)],
		[0.16, Color(0.92, 0.52, 0.54), Color(0.78, 0.48, 0.26)], [0.1, Color(0.98, 0.94, 0.9), Color(0.96, 0.78, 0.46)],
		[0.18, Color(0.9, 0.48, 0.5), Color(0.76, 0.46, 0.24)], [0.12, Color(0.98, 0.94, 0.9), Color(0.95, 0.76, 0.44)], [0.08, Color(0.92, 0.52, 0.54), Color(0.78, 0.48, 0.26)]]
	var y: float = -hh
	var total: float = 0.0
	for l: Array in layers:
		total += float(l[0])
	_round_rect(ci, Rect2(-w, -hh, w * 2.0, hh * 2.0), 0.12, cooked(layers[0][1], layers[0][2], cook))
	for i: int in layers.size():
		var l2: Array = layers[i]
		var th: float = float(l2[0]) / total * hh * 2.0
		var wave: float = 0.02 * sin(float(i) * 1.7)
		ci.draw_rect(Rect2(-w + 0.04, y + wave, w * 2.0 - 0.08, th), cooked(l2[1], l2[2], cook))
		y += th
	_grill_marks(ci, Vector2(0.9, hh * 0.95), cook, false)
	_gloss(ci, Vector2(-0.4, -hh * 0.6), Vector2(0.35, 0.05), cook)


static func _chicken(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var outline: PackedVector2Array = _blob(Vector2(0.9, 0.58), [0.04, -0.02, 0.06, 0.0, -0.05, 0.03, 0.06, -0.04, 0.02, 0.05, -0.03, 0.0])
	var skin: Color = cooked(Color(0.97, 0.82, 0.74), Color(0.86, 0.55, 0.22), cook)
	if silhouette:
		ci.draw_colored_polygon(outline, skin)
		return
	ci.draw_colored_polygon(outline, skin)
	var dot: Color = cooked(Color(0.92, 0.72, 0.64), Color(0.7, 0.4, 0.14), cook)
	for p: Vector2 in [Vector2(-0.5, -0.2), Vector2(-0.2, 0.15), Vector2(0.1, -0.25), Vector2(0.4, 0.1), Vector2(0.55, -0.15), Vector2(-0.35, 0.3), Vector2(0.2, 0.32), Vector2(-0.05, -0.02)]:
		ci.draw_circle(p, 0.05, dot)
	_grill_marks(ci, Vector2(0.72, 0.45), cook, false)
	_gloss(ci, Vector2(-0.25, -0.28), Vector2(0.3, 0.08), cook)


static func _mushroom(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var r: float = 0.82 - 0.08 * clampf(cook, 0.0, 1.0)
	var cap: Color = cooked(Color(0.5, 0.31, 0.2), Color(0.32, 0.18, 0.1), cook)
	if silhouette:
		ci.draw_circle(Vector2.ZERO, r, cap)
		return
	ci.draw_circle(Vector2.ZERO, r, cap.lightened(0.15))
	ci.draw_circle(Vector2.ZERO, r * 0.9, cap)
	var cut: Color = cooked(Color(0.95, 0.9, 0.8), Color(0.82, 0.62, 0.36), cook)
	for k: int in 3:
		var a: float = PI / 3.0 * k + 0.3
		ci.draw_line(Vector2.from_angle(a) * r * 0.7, -Vector2.from_angle(a) * r * 0.7, cut, 0.1)
	_gloss(ci, Vector2(-0.25, -0.35), Vector2(0.25, 0.1), cook + 0.3)


static func _clam(ci: CanvasItem, id: String, cook: float, silhouette: bool) -> void:
	var shell: Color = cooked(base_color(id), base_color(id).darkened(0.2), cook, 0.4)
	if silhouette:
		_ellipse(ci, Vector2.ZERO, Vector2(0.7, 0.55), shell)
		return
	var open: float = clampf((cook - 0.75) * 4.0, 0.0, 1.0)
	if open > 0.0:
		_fan(ci, Vector2(0.0, -0.05 - open * 0.25), Vector2(0.7, 0.55), shell.darkened(0.08), true)
		_ellipse(ci, Vector2(0.0, 0.05), Vector2(0.4, 0.26), cooked(Color(0.98, 0.88, 0.72), GOLDEN, cook, 0.4))
		_ellipse(ci, Vector2(0.08, 0.02), Vector2(0.16, 0.1), Color(0.96, 0.66, 0.4))
	_fan(ci, Vector2(0.0, 0.1 + open * 0.1), Vector2(0.7, 0.55 * (1.0 - open * 0.45)), shell, false)


static func _razor(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var shell: Color = cooked(Color(0.85, 0.75, 0.5), Color(0.7, 0.55, 0.3), cook, 0.5)
	if silhouette:
		_round_rect(ci, Rect2(-1.0, -0.22, 2.0, 0.44), 0.18, shell)
		return
	var open: float = clampf((cook - 0.75) * 4.0, 0.0, 1.0)
	_round_rect(ci, Rect2(-1.0, -0.22 - open * 0.1, 2.0, 0.44), 0.18, shell)
	if open > 0.0:
		_round_rect(ci, Rect2(-0.9, -0.1, 1.8, 0.24), 0.1, cooked(Color(0.98, 0.92, 0.8), GOLDEN, cook, 0.5))
	for k: int in 5:
		ci.draw_line(Vector2(-0.8 + k * 0.4, -0.2 - open * 0.1), Vector2(-0.7 + k * 0.4, 0.2 - open * 0.1), Color(shell.darkened(0.25), 0.5), 0.03)


static func _scallop(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var c: Color = cooked(Color(0.98, 0.95, 0.9), Color(0.9, 0.62, 0.3), cook)
	if silhouette:
		ci.draw_circle(Vector2.ZERO, 0.7, c)
		return
	ci.draw_circle(Vector2.ZERO, 0.7, c)
	ci.draw_circle(Vector2.ZERO, 0.52, cooked(Color(1.0, 0.97, 0.93), Color(0.94, 0.74, 0.42), cook))
	for k: int in 6:
		var a: float = TAU / 6.0 * k
		ci.draw_line(Vector2.from_angle(a) * 0.2, Vector2.from_angle(a) * 0.6, Color(1, 1, 1, 0.25), 0.02)
	_gloss(ci, Vector2(-0.2, -0.3), Vector2(0.2, 0.08), cook + 0.4)


static func _egg(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var outline: PackedVector2Array = _blob(Vector2(0.9, 0.7), [0.08, -0.05, 0.1, 0.02, -0.08, 0.06, 0.0, 0.09, -0.04, 0.05, 0.07, -0.06])
	var k: float = clampf(cook, 0.0, 1.0)
	if silhouette:
		ci.draw_colored_polygon(outline, cooked(Color(1, 1, 1, 0.3), GOLDEN, cook))
		return
	var white: Color = Color(1.0, 0.99, 0.95, 0.45 + 0.55 * k)
	if cook > 1.0:
		white = white.lerp(BURNT, clampf((cook - 1.0) * 0.6, 0.0, 1.0))
	ci.draw_colored_polygon(outline, white)
	if cook > 0.7:
		var lace: Color = Color(GOLDEN, clampf((cook - 0.7) * 2.0, 0.0, 0.8))
		var ring: PackedVector2Array = outline.duplicate()
		ring.append(outline[0])
		ci.draw_polyline(ring, lace, 0.07)
	ci.draw_circle(Vector2(0.08, -0.05), 0.3, cooked(Color(1.0, 0.72, 0.12), Color(1.0, 0.66, 0.2), cook, 0.3))
	ci.draw_circle(Vector2(0.0, -0.13), 0.08, Color(1, 1, 1, 0.5))


static func _jeon(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var outline: PackedVector2Array = _blob(Vector2(0.88, 0.8), [0.03, -0.02, 0.04, 0.0, -0.03, 0.02, 0.03, -0.02, 0.01, 0.03, -0.02, 0.0])
	var c: Color = cooked(Color(0.97, 0.88, 0.58), Color(0.9, 0.62, 0.26), cook)
	if silhouette:
		ci.draw_colored_polygon(outline, c)
		return
	ci.draw_colored_polygon(outline, c)
	for p: Vector2 in [Vector2(-0.4, -0.2), Vector2(0.3, 0.3), Vector2(0.1, -0.4), Vector2(-0.2, 0.35), Vector2(0.45, -0.1)]:
		ci.draw_line(p, p + Vector2(0.12, 0.05), Color(0.38, 0.62, 0.3), 0.06)
	if cook > 0.5:
		for p2: Vector2 in [Vector2(-0.2, 0.0), Vector2(0.25, -0.15), Vector2(0.0, 0.25), Vector2(-0.45, 0.25), Vector2(0.5, 0.2)]:
			ci.draw_circle(p2, 0.09, Color(0.66, 0.4, 0.16, clampf((cook - 0.5) * 1.2, 0.0, 0.6)))
	_gloss(ci, Vector2(-0.3, -0.35), Vector2(0.25, 0.08), cook)


static func _tofu(ci: CanvasItem, cook: float, silhouette: bool) -> void:
	var c: Color = cooked(Color(0.98, 0.96, 0.9), Color(0.92, 0.68, 0.32), cook)
	_round_rect(ci, Rect2(-0.7, -0.5, 1.4, 1.0), 0.1, c)
	if not silhouette:
		_grill_marks(ci, Vector2(0.6, 0.42), cook, false)


static func _round_food(ci: CanvasItem, radii: Vector2, raw: Color, cook: float, silhouette: bool, spots: Color) -> void:
	var c: Color = cooked(raw, GOLDEN, cook, 0.8)
	_ellipse(ci, Vector2.ZERO, radii, c)
	if silhouette:
		return
	if spots.a > 0.0:
		for p: Vector2 in [Vector2(-0.4, -0.1), Vector2(0.2, 0.25), Vector2(0.45, -0.2)]:
			ci.draw_circle(p, 0.04, spots)
	_gloss(ci, Vector2(-0.25, -radii.y * 0.5), Vector2(radii.x * 0.3, 0.07), cook)


## 석쇠 자국: 익힘 0.4 부터 짙어진다 (cross = 격자).
static func _grill_marks(ci: CanvasItem, radii: Vector2, cook: float, cross: bool) -> void:
	if cook < 0.4:
		return
	var col: Color = Color(MARK, clampf((cook - 0.4) * 1.3, 0.0, 0.7))
	for k: int in 4:
		var off: float = (float(k) - 1.5) * 0.36
		var seg: PackedVector2Array = _chord(radii, Vector2(1.0, -0.55).normalized(), off)
		if seg.size() == 2:
			ci.draw_line(seg[0], seg[1], col, 0.07)
		if cross:
			var seg2: PackedVector2Array = _chord(radii, Vector2(1.0, 0.55).normalized(), off)
			if seg2.size() == 2:
				ci.draw_line(seg2[0], seg2[1], Color(col, col.a * 0.7), 0.05)


## 기름기 반짝임 (익을수록 또렷하게, 타면 사라짐).
static func _gloss(ci: CanvasItem, at: Vector2, radii: Vector2, cook: float) -> void:
	var a: float = 0.18 + 0.2 * clampf(cook, 0.0, 1.0) - 0.4 * clampf(cook - 1.0, 0.0, 1.0)
	if a > 0.02:
		_ellipse(ci, at, radii, Color(1, 1, 1, a))


# ---- 작은 조각 (그릇 · 냄비 · 웍) ----

## 조각 하나: size(px) 크기. 생선 · 고기는 토막, 채소는 저마다 모양.
static func draw_piece(ci: CanvasItem, id: String, pos: Vector2, size: float, rot: float, cook: float = 0.0, seed_n: int = 0) -> void:
	ci.draw_set_transform(pos, rot, Vector2(size * 0.5, size * 0.5))
	var k: String = kind_of(id)
	match k:
		"fish", "turtle":
			_round_rect(ci, Rect2(-0.8, -0.55, 1.6, 1.1), 0.25, cooked(flesh_color(id), Color(0.92, 0.82, 0.68), cook, 0.7))
			var f: FishInfo = GameData.fish.get(id)
			ci.draw_rect(Rect2(-0.8, -0.55, 1.6, 0.25), cooked(f.body_color if f != null else Color(0.5, 0.5, 0.5), MARK, cook, 0.3))
		"crab":
			_ellipse(ci, Vector2.ZERO, Vector2(0.8, 0.6), cooked(base_color(id), Color(0.9, 0.32, 0.18), maxf(cook, 0.9)))
		"steak":
			_round_rect(ci, Rect2(-0.85, -0.45, 1.7, 0.9), 0.2, cooked(Color(0.72, 0.18, 0.22), Color(0.48, 0.27, 0.15), cook))
		"belly":
			_round_rect(ci, Rect2(-0.85, -0.45, 1.7, 0.9), 0.15, cooked(Color(0.92, 0.56, 0.56), Color(0.78, 0.5, 0.28), cook))
			ci.draw_rect(Rect2(-0.8, -0.12, 1.6, 0.22), cooked(Color(0.98, 0.94, 0.9), Color(0.95, 0.78, 0.46), cook))
		"chicken":
			_ellipse(ci, Vector2.ZERO, Vector2(0.8, 0.6), cooked(Color(0.97, 0.84, 0.76), Color(0.86, 0.56, 0.24), cook))
		"clam", "razor", "scallop":
			_fan(ci, Vector2.ZERO, Vector2(0.8, 0.65), cooked(base_color(id), base_color(id).darkened(0.2), cook, 0.4), false)
		"mushroom":
			_ellipse(ci, Vector2(0.0, -0.1), Vector2(0.8, 0.45), cooked(Color(0.5, 0.31, 0.2), Color(0.32, 0.18, 0.1), cook))
			ci.draw_rect(Rect2(-0.15, 0.0, 0.3, 0.55), Color(0.95, 0.9, 0.8))
		"scallion", "wild_chive":
			ci.draw_circle(Vector2.ZERO, 0.55, Color(0.45, 0.72, 0.32) if seed_n % 3 != 0 else Color(0.92, 0.95, 0.85))
			ci.draw_circle(Vector2.ZERO, 0.28, Color(0.75, 0.9, 0.6) if seed_n % 3 != 0 else Color(0.85, 0.92, 0.7))
		"chili":
			ci.draw_circle(Vector2.ZERO, 0.5, Color(0.85, 0.2, 0.15))
			ci.draw_circle(Vector2.ZERO, 0.28, Color(0.95, 0.75, 0.4))
		"garlic":
			_ellipse(ci, Vector2.ZERO, Vector2(0.45, 0.35), Color(0.98, 0.95, 0.86))
		"onion":
			ci.draw_arc(Vector2.ZERO, 0.6, 0.0, PI * 1.3, 12, cooked(Color(0.95, 0.92, 0.85), Color(0.82, 0.6, 0.3), cook, 0.8), 0.18)
		"radish":
			_round_rect(ci, Rect2(-0.6, -0.6, 1.2, 1.2), 0.12, cooked(Color(0.99, 0.98, 0.92), Color(0.86, 0.76, 0.52), cook, 0.6))
		"potato":
			_round_rect(ci, Rect2(-0.55, -0.55, 1.1, 1.1), 0.2, cooked(Color(0.96, 0.88, 0.6), GOLDEN, cook, 0.8))
		"tofu":
			_round_rect(ci, Rect2(-0.6, -0.6, 1.2, 1.2), 0.08, cooked(Color(0.98, 0.96, 0.9), GOLDEN, cook, 0.5))
		"egg":
			ci.draw_circle(Vector2.ZERO, 0.6, Color(0.99, 0.97, 0.92))
			ci.draw_circle(Vector2(0.1, 0.0), 0.3, Color(1.0, 0.75, 0.15))
		"wild_greens", "mugwort", "laver":
			var leaf: PackedVector2Array = [Vector2(-0.8, 0.0), Vector2(-0.2, -0.45), Vector2(0.8, 0.0), Vector2(-0.2, 0.45)]
			ci.draw_colored_polygon(leaf, base_color(id))
			ci.draw_line(Vector2(-0.8, 0.0), Vector2(0.7, 0.0), base_color(id).lightened(0.3), 0.06)
		"lemon":
			ci.draw_circle(Vector2.ZERO, 0.6, Color(0.96, 0.82, 0.2))
			ci.draw_circle(Vector2.ZERO, 0.5, Color(0.99, 0.94, 0.6))
			for s: int in 6:
				ci.draw_line(Vector2.ZERO, Vector2.from_angle(TAU / 6.0 * s) * 0.48, Color(0.96, 0.84, 0.3), 0.05)
		"rice":
			for g: int in 5:
				_ellipse(ci, Vector2(cos(g * 2.4) * 0.35, sin(g * 2.4) * 0.3), Vector2(0.2, 0.11), Color(0.99, 0.98, 0.95))
		_:
			ci.draw_circle(Vector2.ZERO, 0.5, base_color(id))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---- 썰기용 길쭉한 모습 ----

## 썰 재료의 겉 · 속 · 자른 면 색과 모양 (도마 위에 가로로 눕힌다).
static func bar_spec(id: String) -> Dictionary:
	if GameData.fish.has(id):
		var f: FishInfo = GameData.fish[id]
		return {"skin": f.body_color, "flesh": flesh_color(id), "cross": flesh_color(id), "thick": 0.5, "skin_band": 0.22}
	match id:
		"radish":
			return {"skin": Color(0.96, 0.95, 0.88), "flesh": Color(0.99, 0.99, 0.95), "cross": Color(0.99, 0.99, 0.96), "thick": 0.62, "tip": Color(0.6, 0.78, 0.38)}
		"scallion", "wild_chive":
			return {"skin": Color(0.46, 0.74, 0.34), "flesh": Color(0.6, 0.82, 0.45), "cross": Color(0.82, 0.94, 0.7), "ring": Color(0.4, 0.68, 0.3), "thick": 0.26, "root": Color(0.95, 0.96, 0.88)}
		"chili":
			return {"skin": Color(0.84, 0.18, 0.14), "flesh": Color(0.88, 0.24, 0.18), "cross": Color(0.95, 0.8, 0.45), "ring": Color(0.84, 0.18, 0.14), "thick": 0.3, "tip": Color(0.35, 0.6, 0.25)}
		"garlic":
			return {"skin": Color(0.97, 0.93, 0.84), "flesh": Color(0.99, 0.97, 0.9), "cross": Color(1.0, 0.98, 0.9), "thick": 0.36}
		"onion":
			return {"skin": Color(0.9, 0.78, 0.55), "flesh": Color(0.97, 0.94, 0.86), "cross": Color(0.98, 0.96, 0.9), "ring": Color(0.88, 0.84, 0.72), "thick": 0.7}
		"potato":
			return {"skin": Color(0.78, 0.62, 0.36), "flesh": Color(0.97, 0.9, 0.6), "cross": Color(0.98, 0.92, 0.64), "thick": 0.6}
		"shiitake":
			return {"skin": Color(0.5, 0.31, 0.2), "flesh": Color(0.95, 0.9, 0.8), "cross": Color(0.95, 0.9, 0.8), "thick": 0.5, "skin_band": 0.4}
		"lemon":
			return {"skin": Color(0.96, 0.82, 0.2), "flesh": Color(0.99, 0.94, 0.6), "cross": Color(0.99, 0.94, 0.6), "ring": Color(0.96, 0.82, 0.2), "thick": 0.6}
		"tofu":
			return {"skin": Color(0.98, 0.96, 0.9), "flesh": Color(0.98, 0.96, 0.9), "cross": Color(1.0, 0.99, 0.95), "thick": 0.6}
		"beef":
			return {"skin": Color(0.96, 0.9, 0.84), "flesh": Color(0.74, 0.16, 0.2), "cross": Color(0.78, 0.22, 0.26), "thick": 0.55, "skin_band": 0.16, "marble": true}
		"pork_belly":
			return {"skin": Color(0.94, 0.8, 0.7), "flesh": Color(0.92, 0.55, 0.56), "cross": Color(0.98, 0.94, 0.9), "thick": 0.5, "skin_band": 0.12, "layers": true}
		"chicken":
			return {"skin": Color(0.97, 0.84, 0.74), "flesh": Color(0.98, 0.8, 0.78), "cross": Color(0.98, 0.84, 0.8), "thick": 0.5, "skin_band": 0.2}
		"wild_greens", "mugwort":
			return {"skin": base_color(id), "flesh": base_color(id).lightened(0.15), "cross": base_color(id).lightened(0.3), "thick": 0.4}
	var c: Color = base_color(id)
	return {"skin": c.darkened(0.1), "flesh": c, "cross": c.lightened(0.2), "thick": 0.5}


# ---- 도형 도우미 ----

static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, color: Color, n: int = 28) -> void:
	var pts: PackedVector2Array = []
	for i: int in n:
		var a: float = TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(pts, color)


static func ellipse(ci: CanvasItem, c: Vector2, r: Vector2, color: Color) -> void:
	_ellipse(ci, c, r, color)


static func _blob(r: Vector2, bumps: Array) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var n: int = 36
	for i: int in n:
		var a: float = TAU * i / n
		var b: float = float(bumps[i * bumps.size() / n])
		pts.append(Vector2(cos(a) * r.x, sin(a) * r.y) * (1.0 + b))
	return pts


static func _round_rect(ci: CanvasItem, r: Rect2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = []
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners: Array[Vector2] = [r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad), r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad)]
	for k: int in 4:
		for j: int in 7:
			var a: float = PI * 0.5 * k + PI * 0.5 * j / 6.0
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, color)


static func round_rect(ci: CanvasItem, r: Rect2, radius: float, color: Color) -> void:
	_round_rect(ci, r, radius, color)


## 조개껍데기 (부채꼴 + 골). flip = 위로 열린 쪽.
static func _fan(ci: CanvasItem, c: Vector2, r: Vector2, color: Color, flip: bool) -> void:
	var pts: PackedVector2Array = [c + Vector2(0.0, r.y * (-0.7 if flip else 0.7))]
	for i: int in 13:
		var a: float = PI + PI * i / 12.0
		var y: float = sin(a) * r.y
		pts.append(c + Vector2(cos(a) * r.x, -y if flip else y) + Vector2(0.0, r.y * (0.3 if flip else -0.3)))
	ci.draw_colored_polygon(pts, color)
	for k: int in 5:
		var a2: float = PI + PI * (k + 1) / 6.0
		var tip: Vector2 = c + Vector2(cos(a2) * r.x, (-1.0 if flip else 1.0) * sin(a2) * r.y) + Vector2(0.0, r.y * (0.3 if flip else -0.3))
		ci.draw_line(pts[0], tip, Color(color.darkened(0.25), 0.6), 0.04)


## 타원 안을 지나는 선분 (방향 dir, 중심에서 수직으로 off 만큼 옮긴 선). 안 지나면 빈 배열.
static func _chord(r: Vector2, dir: Vector2, off: float) -> PackedVector2Array:
	var n: Vector2 = Vector2(-dir.y, dir.x)
	var o: Vector2 = n * off
	var a: float = (dir.x / r.x) ** 2 + (dir.y / r.y) ** 2
	var b: float = 2.0 * (o.x * dir.x / (r.x * r.x) + o.y * dir.y / (r.y * r.y))
	var c: float = (o.x / r.x) ** 2 + (o.y / r.y) ** 2 - 1.0
	var disc: float = b * b - 4.0 * a * c
	if disc <= 0.0:
		return PackedVector2Array()
	var sq: float = sqrt(disc)
	return PackedVector2Array([o + dir * ((-b - sq) / (2.0 * a)), o + dir * ((-b + sq) / (2.0 * a))])
