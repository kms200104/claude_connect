class_name KitchenCounter
extends Node3D
## 위에서 내려다보는 3D 주방 조리대 (v0.18 리듬 요리). CookStage 의 SubViewport 안에서 그린다.
## 나무 조리대 위에 도마 · 화구 · 튀김 냄비 자리가 있고, 동작(장면)마다 카메라가 그 자리로 미끄러져 간다.
## 누를 때마다(act) 그 동작이 한 번 일어난다 — 칼이 내려와 한 토막 · 팬 위 고기를 뒤집기 · 냄비에 풍덩 · 웍을 휙 …
## 시간이 흐르며 익는다 (팬 · 튀김 · 냄비). 재료 · 도구는 KitchenProps 가 실제 크기로 빚는다.
## 좌표: 조리대 윗면 y = 0, 보는 사람 쪽 = +Z.

const CLAY: Material = preload("res://assets/materials/foliage.tres")

## 장면 → 자리 (조리대 위).
const STATIONS: Dictionary[String, Vector3] = {
	"board": Vector3(-0.55, 0.0, 0.06), "stove": Vector3(0.15, 0.0, 0.02), "fryer": Vector3(0.74, 0.0, 0.04), "pass": Vector3(-0.1, 0.0, 0.2)}
const SCENE_STATION: Dictionary[String, String] = {
	"chop": "board", "season": "board", "skewer": "board", "knead": "board", "mix": "board",
	"grill": "stove", "flip": "stove", "wok": "stove", "boil": "stove", "simmer": "stove", "steam": "stove",
	"fry": "fryer", "plate": "pass"}

## 익힘 색 (머티리얼에 곱한다): 날것 → 노릇 → 탐.
const RAW_TINT: Color = Color(1.0, 1.0, 1.0)
const GOLD_TINT: Color = Color(0.93, 0.7, 0.42)
const BURNT_TINT: Color = Color(0.36, 0.25, 0.17)

var scene: String = ""
var step: Dictionary = {}
var recipe: RecipeInfo = null
var main_id: String = ""
var chop_id: String = ""
var pot_ids: Array[String] = []
## 지금까지 한 동작 수 · 해야 할 수.
var done: int = 0
var total: int = 0

var _camera: Camera3D = null
var _cam_from: Vector3 = Vector3.ZERO
var _cam_to: Vector3 = Vector3.ZERO
var _cam_t: float = 1.0
var _set: Node3D = null
var _time: float = 0.0
var _flame: Node3D = null
var _flame_on: float = 0.0
var _flame_want: float = 0.0
var _puff_texture: Texture2D = null
var _puffs: Array[Dictionary] = []
var _bubbles: Array[Dictionary] = []
var _flyers: Array[Dictionary] = []
## 장면마다 쓰는 것들 (이름 → 노드).
var _n: Dictionary[String, Node3D] = {}
## 익는 재료 (머티리얼 · 익힘 0~2 · 익는 빠르기).
var _cooking: Array[Dictionary] = []
var _liquid_y: float = 0.0
var _boil: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 지금 동작의 움직임들 — 다음 동작으로 장면을 새로 차릴 때 멈춘다 (지운 재료를 붙잡은 채 돌지 않게).
var _tweens: Array[Tween] = []


func _ready() -> void:
	_build_room()


# ---- 방 · 조리대 ----

func _build_room() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(28.0), 0.0)
	sun.light_energy = 0.8
	# 바로 위에서 보면 툰 반사광이 평평한 면 전체를 하얗게 덮는다 — 조리대에서는 끈다.
	sun.light_specular = 0.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 3.0
	add_child(sun)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(0.0, 0.9, 0.6)
	fill.omni_range = 3.0
	fill.light_energy = 0.2
	fill.light_specular = 0.2
	fill.light_color = Color(1.0, 0.93, 0.82)
	add_child(fill)
	_add(self, "Counter", KitchenProps.mesh("counter"), Vector3.ZERO)
	_add(self, "Board", KitchenProps.mesh("board"), STATIONS["board"])
	_add(self, "Burner", KitchenProps.mesh("burner"), STATIONS["stove"])
	_add(self, "FryerBurner", KitchenProps.mesh("burner"), STATIONS["fryer"])
	_add(self, "Fryer", KitchenProps.mesh("fryer"), STATIONS["fryer"] + Vector3(0.0, 0.018, 0.0))
	# 튀김 기름 (늘 데워져 있다).
	var oil: MeshInstance3D = _disc(0.116, Color("#E2A43A"), "Oil")
	oil.position = STATIONS["fryer"] + Vector3(0.0, 0.11, 0.0)
	add_child(oil)
	# 장식: 행주 · 양념 병 · 남은 채소.
	_add(self, "Towel", KitchenProps.mesh("towel"), Vector3(-0.2, 0.0, -0.28)).rotation.y = 0.15
	for k: int in 3:
		_add(self, "Jar%d" % k, KitchenProps.mesh("jar"), Vector3(0.3 + 0.075 * float(k), 0.0, -0.36))
	_add(self, "SpareOnion", KitchenProps.food("onion"), Vector3(-0.86, 0.0, -0.25))
	_add(self, "SpareGarlic", KitchenProps.food("garlic"), Vector3(-0.78, 0.0, -0.3))
	_flame = _make_flame()
	_flame.position = STATIONS["stove"] + Vector3(0.0, 0.018, 0.0)
	add_child(_flame)
	var fryer_flame: Node3D = _make_flame()
	fryer_flame.position = STATIONS["fryer"] + Vector3(0.0, 0.018, 0.0)
	fryer_flame.scale = Vector3.ONE * 0.7
	add_child(fryer_flame)
	_camera = Camera3D.new()
	# 세로로 긴 무대: 가로 폭(조리대 약 0.6 m)을 맞추고 위아래는 더 보인다.
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 52.0
	_camera.current = true
	add_child(_camera)
	_cam_to = _cam_spot(STATIONS["board"])
	_cam_from = _cam_to
	_place_camera(_cam_to)
	_set = Node3D.new()
	_set.name = "Set"
	add_child(_set)
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in 32:
		for x: int in 32:
			var d: float = Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2 * 0.8))
	_puff_texture = ImageTexture.create_from_image(img)


func camera() -> Camera3D:
	return _camera


## 자리 위 카메라: 거의 위에서 (앞으로 조금 기울여) 내려다본다.
func _cam_spot(at: Vector3) -> Vector3:
	return at + Vector3(0.0, 0.62, 0.24)


## 지역 좌표로 겨눈다 (이 조리대는 땅 휘기 기준점을 따라가는 CurveAnchor 아래에 있다). 화면 위쪽 = 조리대 안쪽(-Z).
func _place_camera(spot: Vector3) -> void:
	var target: Vector3 = spot - Vector3(0.0, 0.62, 0.17)
	_camera.transform = Transform3D(Basis.looking_at(target - spot, Vector3.FORWARD), spot)


# ---- 동작 시작 ----

func begin(step_def: Dictionary, recipe_info: RecipeInfo, subjects: Dictionary) -> void:
	step = step_def
	scene = CookStage.scene_of(step)
	recipe = recipe_info
	main_id = str(subjects.get("main", ""))
	chop_id = str(subjects.get("chop", main_id))
	pot_ids.clear()
	for id: Variant in subjects.get("pot", []):
		pot_ids.append(str(id))
	if pot_ids.is_empty():
		pot_ids.append(main_id)
	total = CookRules.hits(step).size()
	done = 0
	_rng.seed = hash(recipe.id if recipe != null else "") + total
	for tw: Tween in _tweens:
		if tw.is_valid():
			tw.kill()
	_tweens.clear()
	for c: Node in _set.get_children():
		c.queue_free()
	_n.clear()
	_cooking.clear()
	_flyers.clear()
	_boil = 0.0
	_flame_want = 0.0
	var station: Vector3 = STATIONS.get(SCENE_STATION.get(scene, "board"), STATIONS["board"])
	_set.position = station
	_cam_from = _camera.position
	_cam_to = _cam_spot(station)
	_cam_t = 0.0
	_build_scene()


## 지금 손이 닿는 곳 (월드) — 박자 고리를 이 자리에 띄운다.
func focus_point() -> Vector3:
	var p: Vector3 = _set.global_position
	match scene:
		"chop":
			return p + Vector3(_cut_x(), 0.03, 0.0)
		"season", "knead":
			return p + Vector3(0.0, 0.04, 0.0)
		"skewer":
			return p + Vector3(_slot_x(mini(done, total - 1)), 0.02, -0.03)
		"plate":
			return p + Vector3(0.0, 0.03, 0.0)
	return p + Vector3(0.0, 0.06, 0.0)


func _build_scene() -> void:
	match scene:
		"chop":
			_scene_chop()
		"season":
			_scene_season()
		"skewer":
			_scene_skewer()
		"knead":
			_scene_knead()
		"mix":
			_scene_mix()
		"grill", "flip":
			_scene_pan()
		"wok":
			_scene_wok()
		"boil", "simmer":
			_scene_pot()
		"steam":
			_scene_steam()
		"fry":
			_scene_fry()
		"plate":
			_scene_plate()


# ---- 장면 만들기 ----

## 썰기: 도마 위 재료 하나, 칼이 오른쪽 끝부터 박자마다 한 토막씩.
func _scene_chop() -> void:
	var body: Node3D = _food_node(chop_id, true)
	body.position = Vector3(-0.06, 0.024, 0.0)
	_n["body"] = body
	var knife: Node3D = Node3D.new()
	_set.add_child(knife)
	# 칼날이 재료를 가로질러 (칼끝은 화면 위쪽), 날 옆면이 위에서 보이게 비스듬히 쥔다.
	var blade: MeshInstance3D = _add(knife, "Mesh", KitchenProps.mesh("knife"), Vector3(0.0, 0.0, 0.07))
	blade.basis = Basis(Vector3.BACK, 0.85) * Basis(Vector3.UP, PI * 0.5)
	_n["knife"] = knife
	_place_knife(0.0)


## 남은 재료의 비율 (오른쪽부터 한 토막씩 잘려 나간다).
func _left(n: int) -> float:
	return clampf(1.0 - float(n) / float(total + 2), 0.2, 1.0)


## 다음에 자를 곳: 남은 재료의 오른쪽 끝 조금 안쪽.
func _cut_x() -> float:
	return -0.06 + 0.085 * _left(done) - 0.012


func _place_knife(lift: float) -> void:
	var knife: Node3D = _n.get("knife")
	if knife == null:
		return
	# 날이 도마에 수직으로 서서 위아래로 내려온다 (칼끝은 화면 위쪽).
	knife.position = Vector3(_cut_x(), 0.024 + 0.005 + lift * 0.07, 0.03)
	knife.rotation = Vector3(0.0, 0.0, 0.0)


## 간하기: 도마 위 고기 · 생선, 위에서 소금통을 흔든다.
func _scene_season() -> void:
	var body: Node3D = _food_node(main_id, false)
	body.position = Vector3(0.0, 0.024, 0.0)
	_n["body"] = body
	var shaker: Node3D = Node3D.new()
	_set.add_child(shaker)
	_add(shaker, "Mesh", KitchenProps.mesh("shaker"), Vector3(0.0, -0.09, 0.0))
	shaker.position = Vector3(0.05, 0.22, -0.02)
	shaker.rotation = Vector3(0.0, 0.0, deg_to_rad(150.0))
	_n["shaker"] = shaker


## 꼬치: 도마 위 꼬챙이 하나, 앞줄에 꿸 조각들 (주재료 · 파 번갈아).
func _scene_skewer() -> void:
	_add(_set, "Skewer", KitchenProps.mesh("skewer"), Vector3(0.0, 0.03, -0.03))
	for i: int in total:
		var id: String = main_id if i % 2 == 0 else ("scallion" if main_id != "scallion" else "shiitake")
		var p: Node3D = _piece_node(id)
		p.position = Vector3(-0.1 + 0.065 * float(i), 0.024, 0.07)
		p.rotation.y = _rng.randf_range(-0.4, 0.4)
		_n["piece%d" % i] = p


func _slot_x(i: int) -> float:
	return -0.09 + 0.06 * float(i)


## 반죽: 밀가루 뿌린 도마 위 반죽 덩이.
func _scene_knead() -> void:
	for k: int in 26:
		var dust: MeshInstance3D = _add(_set, "Flour%d" % k, KitchenProps.piece("garlic"), Vector3(_rng.randf_range(-0.14, 0.14), 0.024, _rng.randf_range(-0.09, 0.09)))
		dust.scale = Vector3(1.6, 0.25, 1.6) * _rng.randf_range(0.5, 1.2)
	var dough: Node3D = _food_node("flour", false)
	dough.position = Vector3(0.0, 0.024, 0.0)
	_n["body"] = dough


## 무치기: 도마 위 스테인리스 그릇, 썬 재료 · 깨.
func _scene_mix() -> void:
	_add(_set, "Bowl", KitchenProps.mesh("bowl"), Vector3(0.0, 0.024, 0.0))
	var holder: Node3D = Node3D.new()
	holder.position = Vector3(0.0, 0.03, 0.0)
	_set.add_child(holder)
	_n["holder"] = holder
	for i: int in 14:
		var id: String = pot_ids[i % pot_ids.size()]
		var p: Node3D = _piece_node(id, holder)
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, 0.065)
		p.position = Vector3(cos(a) * d, 0.006 * float(i % 3), sin(a) * d)
		p.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, 0.0)
	var spoon: Node3D = Node3D.new()
	spoon.position = Vector3(0.0, 0.08, 0.0)
	_set.add_child(spoon)
	_add(spoon, "Mesh", KitchenProps.mesh("turner"), Vector3(0.04, 0.0, 0.0)).rotation.z = -0.5
	_n["spoon"] = spoon


## 굽기 · 부치기: 화구 위 팬, 옆 쟁반에 재료 (부치기는 반죽 그릇).
func _scene_pan() -> void:
	var pan: Node3D = _add(_set, "Pan", KitchenProps.mesh("grill_pan" if scene == "grill" else "pan"), Vector3(0.0, 0.03, 0.0))
	pan.rotation.y = PI
	_flame_want = 1.0
	var tray: Vector3 = Vector3(0.24, 0.0, 0.08)
	_add(_set, "Tray", KitchenProps.mesh("plate"), tray)
	var body: Node3D = _food_node(main_id if scene == "grill" else ("egg" if main_id == "egg" else "jeon"), scene == "grill")
	body.position = tray + Vector3(0.0, 0.016, 0.0)
	if scene == "flip":
		body.scale = Vector3.ONE * 0.001
		body.position = Vector3(0.0, 0.04, 0.0)
		body.visible = false
	_n["body"] = body
	var turner: Node3D = Node3D.new()
	turner.position = Vector3(0.16, 0.12, -0.12)
	_set.add_child(turner)
	_add(turner, "Mesh", KitchenProps.mesh("turner"), Vector3.ZERO).rotation.y = PI * 0.75
	_n["turner"] = turner


## 볶기: 화구 위 웍, 안에 썬 재료.
func _scene_wok() -> void:
	var wok: Node3D = Node3D.new()
	wok.position = Vector3(0.0, 0.03, 0.0)
	_set.add_child(wok)
	_add(wok, "Mesh", KitchenProps.mesh("wok"), Vector3.ZERO).rotation.y = PI
	_n["wok"] = wok
	_flame_want = 1.3
	for i: int in 16:
		var p: Node3D = _piece_node(pot_ids[i % pot_ids.size()], wok)
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(0.0, 0.07)
		p.position = Vector3(cos(a) * d, 0.012 + d * d * 3.0, sin(a) * d)
		p.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
		_track_cook(p, 0.05)


## 끓이기 · 졸이기: 화구 위 냄비, 물(국물) · 옆에 넣을 재료.
func _scene_pot() -> void:
	_add(_set, "Pot", KitchenProps.mesh("pot"), Vector3(0.0, 0.03, 0.0))
	_flame_want = 1.0
	var broth: Color = Color("#BFD6DC") if scene == "boil" else _broth_color()
	var water: MeshInstance3D = _disc(0.112, broth, "Liquid")
	_liquid_y = 0.03 + (0.085 if scene == "boil" else 0.07)
	water.position = Vector3(0.0, _liquid_y, 0.0)
	_set.add_child(water)
	_n["liquid"] = water
	_boil = 1.0
	if scene == "boil":
		_add(_set, "Tray", KitchenProps.mesh("plate"), Vector3(0.23, 0.0, 0.09))
		for i: int in total:
			var p: Node3D = _piece_node(pot_ids[i % pot_ids.size()])
			p.position = Vector3(0.2 + 0.03 * float(i % 2), 0.016, 0.05 + 0.03 * float(i))
			_n["piece%d" % i] = p
	else:
		for i: int in 9:
			var p: Node3D = _piece_node(pot_ids[i % pot_ids.size()], water)
			var a: float = TAU * float(i) / 9.0
			p.position = Vector3(cos(a) * 0.06, 0.004, sin(a) * 0.06)
			_n["float%d" % i] = p
		var ladle: Node3D = Node3D.new()
		ladle.position = Vector3(0.0, _liquid_y - 0.03, 0.0)
		_set.add_child(ladle)
		_add(ladle, "Mesh", KitchenProps.mesh("ladle"), Vector3(0.05, 0.0, 0.0)).rotation.y = PI * 0.15
		_n["ladle"] = ladle


func _broth_color() -> Color:
	if recipe != null and (recipe.id.contains("stew") or recipe.id.contains("spicy") or recipe.id == "galbijjim"):
		return Color("#C8502E")
	if recipe != null and recipe.id.contains("braise"):
		return Color("#7A4A28")
	return Color("#D8B878")


## 찌기: 화구 위 냄비 + 찜기, 옆 쟁반의 재료 · 물 주전자.
func _scene_steam() -> void:
	_add(_set, "Pot", KitchenProps.mesh("pot"), Vector3(0.0, 0.03, 0.0))
	var basket: MeshInstance3D = _add(_set, "Steamer", KitchenProps.mesh("steamer"), Vector3(0.0, 0.15, 0.0))
	_n["steamer"] = basket
	_flame_want = 1.0
	_add(_set, "Tray", KitchenProps.mesh("plate"), Vector3(0.24, 0.0, 0.1))
	var items: int = maxi(1, total - 3)
	for i: int in items:
		var p: Node3D = _piece_node(pot_ids[i % pot_ids.size()])
		p.scale = Vector3.ONE * 1.4
		p.position = Vector3(0.21 + 0.035 * float(i % 2), 0.016, 0.06 + 0.035 * float(i))
		_n["piece%d" % i] = p
	var pitcher: Node3D = Node3D.new()
	pitcher.position = Vector3(-0.22, 0.0, -0.06)
	_set.add_child(pitcher)
	_add(pitcher, "Mesh", KitchenProps.mesh("pitcher"), Vector3.ZERO).rotation.y = 0.0
	_n["pitcher"] = pitcher
	var lid: Node3D = Node3D.new()
	lid.position = Vector3(-0.2, 0.0, 0.14)
	_set.add_child(lid)
	_add(lid, "Mesh", KitchenProps.mesh("steamer_lid"), Vector3.ZERO)
	_n["lid"] = lid


## 튀기기: 기름 냄비 위 바구니, 튀김옷 입힌 재료.
func _scene_fry() -> void:
	var basket: Node3D = Node3D.new()
	basket.position = Vector3(0.0, 0.2, 0.0)
	_set.add_child(basket)
	_add(basket, "Mesh", KitchenProps.mesh("basket"), Vector3.ZERO).rotation.y = PI
	_n["basket"] = basket
	for i: int in 6:
		var p: Node3D = _piece_node(main_id, basket)
		p.scale = Vector3.ONE * 1.3
		var a: float = TAU * float(i) / 6.0
		p.position = Vector3(cos(a) * 0.04, 0.012 + 0.008 * float(i % 2), sin(a) * 0.04)
		p.rotation.y = a
		_track_cook(p, 0.0)
		_tint(p, Color(1.0, 0.97, 0.88))


## 담기: 빈 접시가 옆에서 미끄러져 들어오고, 요리 · 고명이 올라간다.
func _scene_plate() -> void:
	var plate: Node3D = Node3D.new()
	plate.position = Vector3(0.45, 0.0, 0.0)
	_set.add_child(plate)
	_add(plate, "Mesh", KitchenProps.mesh("plate"), Vector3.ZERO)
	_n["plate"] = plate
	var dish: MeshInstance3D = MeshInstance3D.new()
	dish.mesh = DishArt.mesh(recipe.id) if recipe != null else null
	dish.material_override = CLAY
	# 요리 모형의 접시(지름 40cm)를 실제 접시(24cm)에 맞춘다.
	dish.scale = Vector3.ONE * 0.001
	dish.visible = false
	plate.add_child(dish)
	_n["dish"] = dish


# ---- 누름 → 동작 ----

## 동작 한 번 (누를 때마다). grade 가 MISS 면 서툴게 (헛손질 · 엇나감).
func act(grade: int) -> void:
	if done >= total:
		_whiff()
		return
	var i: int = done
	done += 1
	var good: bool = grade >= CookRules.Grade.GOOD
	match scene:
		"chop":
			_act_chop(i)
		"season":
			_act_season()
		"skewer":
			_act_skewer(i)
		"knead":
			_act_knead()
		"mix":
			_act_mix()
		"grill", "flip":
			_act_pan(i)
		"wok":
			_act_wok(good)
		"boil":
			_act_boil(i)
		"simmer":
			_act_simmer(i)
		"steam":
			_act_steam(i)
		"fry":
			_act_fry(i)
		"plate":
			_act_plate(i)


## 다 못 했어도 동작이 끝나면 마저 해 둔다 (다음 장면으로 넘어가기 전 그림).
func finish_rest() -> void:
	while done < total:
		act(CookRules.Grade.OK)


func _whiff() -> void:
	var target: Node3D = _n.get("knife", _n.get("turner", _n.get("body")))
	if target != null:
		_shake(target, 0.01)


func _act_chop(i: int) -> void:
	var knife: Node3D = _n["knife"]
	var x: float = _cut_x()
	var tw: Tween = _tween()
	tw.tween_property(knife, "position:y", 0.026, 0.05).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		# 한 토막이 떨어져 나와 오른쪽으로 쌓인다.
		var slice: Node3D = _piece_node(chop_id)
		slice.position = Vector3(x + 0.004, 0.024, 0.0)
		slice.rotation.y = _rng.randf_range(-0.3, 0.3)
		var t2: Tween = _tween()
		t2.tween_property(slice, "position", Vector3(0.11 + 0.012 * float(i % 3), 0.024 + 0.005 * float(i / 3), -0.07 + 0.045 * float(i % 4)), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# 왼쪽 끝은 그대로, 오른쪽이 줄어든다.
		var body: Node3D = _n["body"]
		var left: float = _left(i + 1)
		body.scale.x = left
		body.position.x = -0.06 - 0.085 * (1.0 - left)
		_puff(_set.position + Vector3(x, 0.04, 0.0), Color(1, 1, 1, 0.5), 0.02, 0.3))
	tw.tween_property(knife, "position:y", 0.024 + 0.075, 0.14).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(knife, "position:x", _cut_x(), 0.14)


func _act_season() -> void:
	var shaker: Node3D = _n["shaker"]
	var tw: Tween = _tween()
	tw.tween_property(shaker, "rotation:z", deg_to_rad(165.0), 0.06)
	tw.tween_property(shaker, "rotation:z", deg_to_rad(140.0), 0.1)
	var body: Node3D = _n["body"]
	for k: int in 14:
		var grain: MeshInstance3D = _add(body, "Salt", KitchenProps.piece("garlic"), Vector3(_rng.randf_range(-0.05, 0.05), 0.03, _rng.randf_range(-0.035, 0.035)))
		grain.scale = Vector3.ONE * 0.25
		grain.rotation.y = _rng.randf() * TAU
		_flyers.append({"node": grain, "v": Vector3(_rng.randf_range(-0.05, 0.05), -0.2, 0.0), "y0": grain.position.y + 0.17, "land": 0.028, "t": 0.0})
		grain.position.y += 0.17


func _act_skewer(i: int) -> void:
	var p: Node3D = _n.get("piece%d" % i)
	if p == null:
		return
	var to: Vector3 = Vector3(_slot_x(i), 0.03, -0.03)
	var tw: Tween = _tween()
	tw.tween_property(p, "position", (p.position + to) * 0.5 + Vector3(0.0, 0.06, 0.0), 0.08)
	tw.tween_property(p, "position", to, 0.08)
	tw.parallel().tween_property(p, "rotation:y", 0.0, 0.16)


func _act_knead() -> void:
	var dough: Node3D = _n["body"]
	var tw: Tween = _tween()
	tw.tween_property(dough, "scale", Vector3(1.3, 0.6, 1.25), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(dough, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(dough, "rotation:y", dough.rotation.y + PI * 0.5, 0.22)
	_puff(_set.position + Vector3(0.05, 0.03, 0.0), Color(1, 1, 1, 0.7), 0.04, 0.4)
	_puff(_set.position + Vector3(-0.05, 0.03, 0.02), Color(1, 1, 1, 0.7), 0.04, 0.4)


func _act_mix() -> void:
	var holder: Node3D = _n["holder"]
	var spoon: Node3D = _n["spoon"]
	var tw: Tween = _tween()
	tw.tween_property(holder, "rotation:y", holder.rotation.y + PI * 0.45, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spoon, "rotation:y", spoon.rotation.y + PI * 0.6, 0.2)
	for c: Node in holder.get_children():
		var p: Node3D = c as Node3D
		if p != null and _rng.randf() < 0.5:
			var hop: Tween = _tween()
			hop.tween_property(p, "position:y", p.position.y + _rng.randf_range(0.015, 0.035), 0.08)
			hop.tween_property(p, "position:y", p.position.y, 0.1)


func _act_pan(i: int) -> void:
	var body: Node3D = _n["body"]
	var verbs: Array = step.get("verbs", [])
	var verb: String = str(verbs[i]) if i < verbs.size() else ""
	var turner: Node3D = _n.get("turner")
	match verb:
		"올리기":
			_arc(body, Vector3(0.0, 0.04, 0.0), 0.16, 0.08)
			_track_cook(body, 0.0)
			_puff(_set.position + Vector3(0.0, 0.06, 0.0), Color(1, 1, 1, 0.6), 0.05, 0.8)
		"붓기":
			body.visible = true
			_track_cook(body, 0.0)
			var tw: Tween = _tween()
			tw.tween_property(body, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"뒤집기":
			# 공중에서 한 바퀴 반 뒤집는다 — 아랫면(노릇)이 위로.
			var tw: Tween = _tween()
			tw.tween_property(body, "position:y", 0.13, 0.12).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(body, "rotation:x", body.rotation.x + PI, 0.24)
			tw.tween_property(body, "position:y", 0.04, 0.1).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void: _puff(_set.position + Vector3(0.0, 0.06, 0.0), Color(1, 1, 1, 0.6), 0.05, 0.6))
			_flip_cook(body)
			if turner != null:
				var t2: Tween = _tween()
				t2.tween_property(turner, "position", Vector3(0.04, 0.05, 0.0), 0.06)
				t2.tween_property(turner, "position", Vector3(0.16, 0.12, -0.12), 0.2)
		"꺼내기":
			_stop_cook(body)
			_arc(body, Vector3(0.24, 0.016, 0.08), 0.16, 0.1)
			_flame_want = 0.4
	if verb == "꺼내기" or i == total - 1:
		_flame_want = 0.4


func _act_wok(good: bool) -> void:
	var wok: Node3D = _n["wok"]
	var tw: Tween = _tween()
	tw.tween_property(wok, "position", Vector3(-0.025, 0.045, 0.0), 0.06)
	tw.parallel().tween_property(wok, "rotation:z", -0.18, 0.06)
	tw.tween_property(wok, "position", Vector3(0.0, 0.03, 0.0), 0.14)
	tw.parallel().tween_property(wok, "rotation:z", 0.0, 0.14)
	for c: Node in wok.get_children():
		var p: Node3D = c as Node3D
		if p == null or p.name == "Mesh":
			continue
		_flyers.append({"node": p, "v": Vector3(_rng.randf_range(0.05, 0.25), _rng.randf_range(0.5, 0.8), _rng.randf_range(-0.12, 0.12)), "y0": p.position.y, "land": p.position.y, "t": 0.0, "spin": _rng.randf_range(-8.0, 8.0)})
	# 잘 맞으면 불이 확 오른다 (불맛).
	_flame_burst(1.8 if good else 1.2)
	for c2: Dictionary in _cooking:
		c2["cook"] = minf(1.05, float(c2["cook"]) + 0.12)


func _act_boil(i: int) -> void:
	var p: Node3D = _n.get("piece%d" % i)
	if p == null:
		return
	var a: float = _rng.randf() * TAU
	var to: Vector3 = Vector3(cos(a) * 0.05, _liquid_y - 0.004, sin(a) * 0.05)
	var tw: Tween = _tween()
	tw.tween_property(p, "position", (p.position + to) * 0.5 + Vector3(0.0, 0.12, 0.0), 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "position", to, 0.08).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_splash(_set.position + Vector3(to.x, _liquid_y + 0.005, to.z))
		_track_cook(p, 0.0))


func _act_simmer(i: int) -> void:
	var ladle: Node3D = _n["ladle"]
	var liquid: Node3D = _n["liquid"]
	if i == total - 1:
		# 불 끄기: 불꽃이 줄고 거품이 멎는다.
		_flame_want = 0.0
		_boil = 0.15
		return
	var tw: Tween = _tween()
	tw.tween_property(ladle, "rotation:y", ladle.rotation.y - TAU, 0.42).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(liquid, "rotation:y", liquid.rotation.y - PI * 0.6, 0.6).set_ease(Tween.EASE_OUT)
	# 졸아든다.
	_liquid_y -= 0.006
	liquid.position.y = _liquid_y
	_tint(liquid, Color(1.0, 1.0, 1.0).darkened(0.05 * float(i + 1)))


func _act_steam(i: int) -> void:
	var items: int = maxi(1, total - 3)
	if i < items:
		var p: Node3D = _n.get("piece%d" % i)
		if p != null:
			var to: Vector3 = Vector3(-0.05 + 0.05 * float(i % 3), 0.17, -0.03 + 0.05 * float(i / 3))
			_arc(p, to, 0.14, 0.1)
			_track_cook(p, 0.0)
		return
	match i - items:
		0:
			# 물 붓기: 주전자를 기울인다.
			var pitcher: Node3D = _n["pitcher"]
			var tw: Tween = _tween()
			tw.tween_property(pitcher, "position", Vector3(-0.15, 0.12, -0.02), 0.12)
			tw.parallel().tween_property(pitcher, "rotation:z", -0.9, 0.12)
			tw.tween_callback(func() -> void: _splash(_set.position + Vector3(-0.08, 0.15, 0.0)))
			tw.tween_property(pitcher, "rotation:z", 0.0, 0.2)
			tw.parallel().tween_property(pitcher, "position", Vector3(-0.22, 0.0, -0.06), 0.25)
			_boil = 0.6
		1:
			var lid: Node3D = _n["lid"]
			_arc(lid, Vector3(0.0, 0.222, 0.0), 0.12, 0.12)
			_boil = 1.0
		_:
			var lid2: Node3D = _n["lid"]
			_arc(lid2, Vector3(-0.2, 0.0, 0.14), 0.16, 0.1)
			for k: int in 6:
				_puff(_set.position + Vector3(_rng.randf_range(-0.06, 0.06), 0.24, _rng.randf_range(-0.06, 0.06)), Color(1, 1, 1, 0.8), 0.08, 1.4)
			for c: Dictionary in _cooking:
				c["cook"] = 1.0
				c["rate"] = 0.0


func _act_fry(i: int) -> void:
	var basket: Node3D = _n["basket"]
	var verbs: Array = step.get("verbs", [])
	var verb: String = str(verbs[i]) if i < verbs.size() else ""
	match verb:
		"넣기":
			var tw: Tween = _tween()
			tw.tween_property(basket, "position:y", 0.04 - 0.0, 0.14).set_ease(Tween.EASE_IN)
			_boil = 1.6
			for c: Dictionary in _cooking:
				c["rate"] = 0.32
		"흔들기":
			var tw: Tween = _tween()
			tw.tween_property(basket, "position:x", 0.012, 0.04)
			tw.tween_property(basket, "position:x", -0.012, 0.06)
			tw.tween_property(basket, "position:x", 0.0, 0.05)
			_boil = 1.4
		"건지기":
			var tw: Tween = _tween()
			tw.tween_property(basket, "position:y", 0.21, 0.18).set_ease(Tween.EASE_OUT)
			_boil = 0.35
			for c: Dictionary in _cooking:
				c["rate"] = 0.0


func _act_plate(i: int) -> void:
	var plate: Node3D = _n["plate"]
	var dish: Node3D = _n["dish"]
	var verbs: Array = step.get("verbs", [])
	var verb: String = str(verbs[i]) if i < verbs.size() else ""
	match verb:
		"접시 놓기":
			var tw: Tween = _tween()
			tw.tween_property(plate, "position", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"담기":
			dish.visible = true
			var tw: Tween = _tween()
			tw.tween_property(dish, "scale", Vector3.ONE * 0.6, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"고명", "소스":
			for k: int in 5:
				var bit: Node3D = _piece_node("scallion" if verb == "고명" else "garlic", plate)
				bit.scale = Vector3.ONE * (0.5 if verb == "고명" else 0.4)
				bit.position = Vector3(_rng.randf_range(-0.05, 0.05), 0.07, _rng.randf_range(-0.05, 0.05))
				if verb == "소스":
					_tint(bit, Color(0.55, 0.32, 0.18))
		_:
			for k: int in 5:
				_puff(_set.position + Vector3(_rng.randf_range(-0.08, 0.08), 0.06, _rng.randf_range(-0.08, 0.08)), Color(1.0, 0.95, 0.6, 0.9), 0.025, 0.6)
			var tw: Tween = _tween()
			tw.tween_property(plate, "scale", Vector3.ONE * 1.08, 0.08)
			tw.tween_property(plate, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ---- 매 프레임 ----

func _process(delta: float) -> void:
	_time += delta
	if _cam_t < 1.0:
		_cam_t = minf(1.0, _cam_t + delta / 0.5)
		var e: float = _cam_t * _cam_t * (3.0 - 2.0 * _cam_t)
		_place_camera(_cam_from.lerp(_cam_to, e))
	_flame_on = move_toward(_flame_on, _flame_want, delta * 3.0)
	_update_flame(_flame, _flame_on)
	# 익는 재료.
	for c: Dictionary in _cooking:
		if not is_instance_valid(c["node"]):
			continue
		c["cook"] = minf(2.0, float(c["cook"]) + float(c["rate"]) * delta)
		_tint(c["node"], _cook_tint(float(c["cook"]) if bool(c.get("shown", true)) else 0.0))
	# 날아오르는 조각 (웍 · 소금): 포물선으로 떨어져 제자리.
	for k: int in range(_flyers.size() - 1, -1, -1):
		var f: Dictionary = _flyers[k]
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			_flyers.remove_at(k)
			continue
		f["t"] = float(f["t"]) + delta
		var v: Vector3 = f["v"]
		v.y -= 2.6 * delta
		f["v"] = v
		node.position += v * delta
		node.rotation.x += float(f.get("spin", 0.0)) * delta
		# 웍 안으로 돌아오게 가운데로 당긴다.
		if f.has("spin"):
			node.position.x = lerpf(node.position.x, 0.0, delta * 2.0)
			node.position.z = lerpf(node.position.z, 0.0, delta * 2.0)
		if node.position.y <= float(f["land"]) and v.y < 0.0:
			node.position.y = float(f["land"])
			_flyers.remove_at(k)
	# 끓는 거품 · 김.
	if _boil > 0.0 and scene in ["boil", "simmer", "fry", "steam"]:
		if _rng.randf() < delta * 18.0 * _boil:
			_spawn_bubble()
		if _rng.randf() < delta * 3.0 * _boil:
			var top: float = _liquid_y + 0.02 if scene != "steam" else 0.24
			if scene == "fry":
				top = 0.13
			_puff(_set.position + Vector3(_rng.randf_range(-0.05, 0.05), top, _rng.randf_range(-0.05, 0.05)), Color(1, 1, 1, 0.45), 0.05, 1.2)
	if scene in ["grill", "flip", "wok"] and done > 0 and done < total and _rng.randf() < delta * 5.0:
		_puff(_set.position + Vector3(_rng.randf_range(-0.05, 0.05), 0.07, _rng.randf_range(-0.04, 0.04)), Color(1, 1, 1, 0.35), 0.035, 0.9)
	_update_bubbles(delta)
	_update_puffs(delta)
	# 졸이기: 떠 있는 재료가 천천히 맴돈다.
	if scene == "simmer" and _n.has("liquid"):
		_n["liquid"].rotation.y -= delta * 0.25 * _boil
	# 칼은 다음 자를 곳 위에서 기다린다.
	if scene == "chop" and _n.has("knife"):
		var knife: Node3D = _n["knife"]
		knife.position.z = 0.03 + 0.003 * sin(_time * 4.0)


# ---- 익힘 ----

func _track_cook(node: Node3D, rate: float) -> void:
	for c: Dictionary in _cooking:
		if c["node"] == node:
			return
	_cooking.append({"node": node, "cook": 0.0, "rate": rate if rate > 0.0 else _cook_rate(), "shown": scene != "grill" and scene != "flip"})


## 이 장면에서 날것이 알맞게 익는 데 걸리는 빠르기 (1 / 초).
func _cook_rate() -> float:
	var interval: float = float(step.get("interval_ms", 536)) / 1000.0
	var span: float = CookRules.last_hit_ms(step) / 1000.0 + interval
	return 1.0 / maxf(span, 0.5)


## 굽기: 뒤집으면 노릇해진 아랫면이 위로 — 그때부터 익힘이 보인다.
func _flip_cook(node: Node3D) -> void:
	for c: Dictionary in _cooking:
		if c["node"] == node:
			c["shown"] = true
			c["cook"] = maxf(float(c["cook"]), 0.9)
			_grill_marks(node)


func _stop_cook(node: Node3D) -> void:
	for c: Dictionary in _cooking:
		if c["node"] == node:
			c["rate"] = 0.0
			c["shown"] = true
			c["cook"] = clampf(float(c["cook"]), 0.85, 1.1)


func _cook_tint(cook: float) -> Color:
	if cook <= 1.0:
		return RAW_TINT.lerp(GOLD_TINT, smoothstep(0.0, 1.0, cook))
	return GOLD_TINT.lerp(BURNT_TINT, clampf(cook - 1.0, 0.0, 1.0))


## 석쇠 자국 (굽기에서 뒤집으면): 짙은 줄 세 개.
func _grill_marks(node: Node3D) -> void:
	if scene != "grill" or node.has_node("Marks"):
		return
	var marks: Node3D = Node3D.new()
	marks.name = "Marks"
	node.add_child(marks)
	for k: int in 3:
		var m: MeshInstance3D = _add(marks, "Mark%d" % k, KitchenProps.piece("razor_clam"), Vector3(-0.03 + 0.03 * float(k), -0.003, 0.0))
		m.scale = Vector3(0.5, 0.2, 0.08)
		m.rotation.y = 0.6
		_tint(m, Color(0.25, 0.15, 0.1))


# ---- 만드는 도우미 ----

func _add(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = CLAY
	mi.position = at
	parent.add_child(mi)
	return mi


## 재료 한 덩이 (물고기는 옆으로 누운 진짜 모양).
func _food_node(id: String, whole: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Food"
	_set.add_child(root)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	if GameData.fish.has(id) and whole:
		var fish: FishInfo = GameData.fish[id]
		mi.mesh = FishModel.mesh(fish)
		mi.material_override = (FishModel.material(fish, CLAY) as Material).duplicate()
		# 몸길이 62cm 모형 → 접시에 오를 크기 (약 24cm), 옆으로 눕혀 위에서 옆모습이 보이게.
		var size: float = {"S": 0.32, "M": 0.4, "L": 0.48, "XL": 0.55}.get(fish.size, 0.4)
		mi.scale = Vector3.ONE * size
		mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		mi.position.y = 0.035 * size / 0.4
	else:
		mi.mesh = KitchenProps.food(id)
		mi.material_override = CLAY.duplicate()
	root.add_child(mi)
	return root


func _piece_node(id: String, parent: Node3D = null) -> Node3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Piece"
	mi.mesh = KitchenProps.piece(id)
	mi.material_override = CLAY.duplicate()
	(parent if parent != null else _set).add_child(mi)
	return mi


## 재료 색 입히기 (점토 머티리얼의 albedo 를 곱한다).
func _tint(node: Node, color: Color) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi == null:
		mi = node.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null:
		return
	var mat: ShaderMaterial = mi.material_override as ShaderMaterial
	if mat == null:
		return
	if mat == CLAY:
		mat = (CLAY as ShaderMaterial).duplicate()
		mi.material_override = mat
	mat.set_shader_parameter("albedo", color)


func _disc(r: float, color: Color, node_name: String) -> MeshInstance3D:
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_lathe(st, PackedVector2Array([Vector2(0.0, -0.002), Vector2(r, -0.002), Vector2(r, 0.0), Vector2(0.0, 0.0)]), 64, Transform3D(), color)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = ClayMesh.commit(st)
	mi.material_override = CLAY.duplicate()
	return mi


func _tween() -> Tween:
	var tw: Tween = create_tween()
	_tweens.append(tw)
	if _tweens.size() > 64:
		_tweens = _tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	return tw


## 포물선으로 옮기기 (집어서 놓기).
func _arc(node: Node3D, to: Vector3, height: float, t: float) -> void:
	var from: Vector3 = node.position
	var tw: Tween = _tween()
	tw.tween_method(func(k: float) -> void:
		node.position = from.lerp(to, k) + Vector3(0.0, sin(k * PI) * height, 0.0), 0.0, 1.0, t * 2.0).set_trans(Tween.TRANS_SINE)


func _shake(node: Node3D, amount: float) -> void:
	var base: Vector3 = node.position
	var tw: Tween = _tween()
	tw.tween_property(node, "position", base + Vector3(amount, 0.0, 0.0), 0.04)
	tw.tween_property(node, "position", base - Vector3(amount, 0.0, 0.0), 0.06)
	tw.tween_property(node, "position", base, 0.04)


# ---- 불꽃 · 거품 · 김 ----

func _make_flame() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Flame"
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 18
	for k: int in n:
		var a: float = TAU * float(k) / float(n)
		var a2: float = TAU * (float(k) + 0.5) / float(n)
		var base0: Vector3 = Vector3(cos(a - 0.12), 0.0, sin(a - 0.12)) * 0.05
		var base1: Vector3 = Vector3(cos(a + 0.12), 0.0, sin(a + 0.12)) * 0.05
		var tip: Vector3 = Vector3(cos(a2) * 0.07, 0.03, sin(a2) * 0.07)
		for v: Array in [[base0, Color(0.25, 0.45, 1.0, 0.9)], [base1, Color(0.25, 0.45, 1.0, 0.9)], [tip, Color(0.6, 0.8, 1.0, 0.0)]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Blue"
	mi.mesh = st.commit()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var orange: MeshInstance3D = mi.duplicate() as MeshInstance3D
	orange.name = "Burst"
	var mat2: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	mat2.vertex_color_use_as_albedo = false
	mat2.albedo_color = Color(1.0, 0.5, 0.12, 0.7)
	orange.material_override = mat2
	orange.scale = Vector3(1.4, 0.001, 1.4)
	root.add_child(orange)
	return root


func _update_flame(root: Node3D, on: float) -> void:
	if root == null:
		return
	var blue: Node3D = root.get_node("Blue")
	blue.visible = on > 0.02
	var flick: float = 1.0 + 0.12 * sin(_time * 31.0) * sin(_time * 17.0)
	blue.scale = Vector3(0.8 + 0.25 * on, maxf(on, 0.01) * flick, 0.8 + 0.25 * on)
	var burst: Node3D = root.get_node("Burst")
	burst.scale.y = move_toward(burst.scale.y, 0.001, get_process_delta_time() * 6.0)
	burst.visible = burst.scale.y > 0.05


func _flame_burst(power: float) -> void:
	var burst: Node3D = _flame.get_node("Burst")
	burst.scale = Vector3(1.4 + 0.3 * power, power * 2.2, 1.4 + 0.3 * power)


func _spawn_bubble() -> void:
	var r: float = 0.1 if scene != "fry" else 0.1
	var a: float = _rng.randf() * TAU
	var d: float = sqrt(_rng.randf()) * r
	var y: float = _liquid_y if scene != "fry" else 0.11
	if scene == "steam":
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = KitchenProps.piece("garlic")
	mi.material_override = CLAY
	mi.position = Vector3(cos(a) * d, y + 0.001, sin(a) * d)
	var size: float = _rng.randf_range(0.5, 1.2) * (1.3 if scene == "fry" else 1.0)
	mi.scale = Vector3(size, 0.6 * size, size) * 0.001
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_set if scene != "fry" else self).add_child(mi)
	if scene == "fry":
		mi.position += STATIONS["fryer"]
	_bubbles.append({"node": mi, "t": 0.0, "life": _rng.randf_range(0.25, 0.6), "size": size})


func _update_bubbles(delta: float) -> void:
	for k: int in range(_bubbles.size() - 1, -1, -1):
		var b: Dictionary = _bubbles[k]
		var mi: MeshInstance3D = b["node"]
		b["t"] = float(b["t"]) + delta
		var u: float = float(b["t"]) / float(b["life"])
		if u >= 1.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_bubbles.remove_at(k)
			continue
		var s: float = float(b["size"]) * sin(u * PI) * 1.2
		mi.scale = Vector3(s, 0.6 * s, s)


## 김 · 연기 한 덩이 (화면을 향한 부드러운 원판, 위로 오르며 흐려진다).
func _puff(at: Vector3, color: Color, size: float, life: float) -> void:
	var q: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	q.mesh = quad
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = _puff_texture
	mat.albedo_color = color
	mat.no_depth_test = false
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.position = at
	q.scale = Vector3.ONE * size
	add_child(q)
	_puffs.append({"node": q, "t": 0.0, "life": life, "size": size, "alpha": color.a})
	if _puffs.size() > 40:
		var old: Dictionary = _puffs.pop_front()
		if is_instance_valid(old["node"]):
			(old["node"] as Node).queue_free()


func _update_puffs(delta: float) -> void:
	for k: int in range(_puffs.size() - 1, -1, -1):
		var p: Dictionary = _puffs[k]
		var q: MeshInstance3D = p["node"]
		if not is_instance_valid(q):
			_puffs.remove_at(k)
			continue
		p["t"] = float(p["t"]) + delta
		var u: float = float(p["t"]) / float(p["life"])
		if u >= 1.0:
			q.queue_free()
			_puffs.remove_at(k)
			continue
		q.position.y += delta * 0.08
		q.scale = Vector3.ONE * float(p["size"]) * (1.0 + u * 1.6)
		(q.material_override as StandardMaterial3D).albedo_color.a = float(p["alpha"]) * (1.0 - u)


## 풍덩: 물보라 김 몇 덩이.
func _splash(at: Vector3) -> void:
	for k: int in 4:
		_puff(at + Vector3(_rng.randf_range(-0.02, 0.02), 0.0, _rng.randf_range(-0.02, 0.02)), Color(0.85, 0.95, 1.0, 0.7), 0.025, 0.35)
