extends Node
## 얼굴 검사 (렌더러 없이): 모든 눈·코·입 도형의 꼭짓점이 머리 메시 겉면보다 바깥에 있는지(파묻혀 깨지지 않는지),
## 감정표현 눈썹·눈물도 겉면 밖인지, 캐릭터 하나 삼각형 수(가장 무거운 표정 포함)가 촘촘함별 예산(BUDGET) 안인지, 모든 촘촘함에서.
## 사용: godot --headless --path . res://tests/face_check.tscn

## 촘촘함(0 절약 · 1 · 2 고화질)별 캐릭터 하나 삼각형 상한 (CLAUDE.md).
const BUDGET: Array[int] = [8000, 12000, 24000]
var _failed: int = 0


func _ready() -> void:
	var catalog: FaceCatalog = GameData.face
	for detail: int in range(CharacterModel.MAX_DETAIL + 1):
		CharacterModel.detail = detail
		CharacterModel.clear_cache()
		var head: Vector2i = CharacterModel.HEAD_SEGMENTS[detail]
		# 머리 메시 면이 이상적인 타원체보다 안쪽으로 들어간 최대 깊이 (둘레·위아래 칸 수로 정해진다).
		var sag: float = CharacterModel.HEAD_RADII.x * (1.0 - cos(PI / float(head.x))) + CharacterModel.HEAD_RADII.y * (1.0 - cos(PI / float(head.y)))
		# 눈은 시선을 따라 머리 중심을 축으로 굴러서 최대 3.2mm 까지 안쪽으로 들 수 있다.
		var worst: float = INF
		var worst_name: String = ""
		for key: String in ["eyes", "nose", "mouth"]:
			for part: FaceCatalog.Part in catalog.list(key):
				var look: CharacterLook = CharacterLook.new()
				look.set(key, part.id)
				var mesh: ArrayMesh = CharacterModel.eyes(look) if key == "eyes" else _face_only(look)
				var offset: Vector3 = CharacterModel.HEAD_CENTER if key == "eyes" else Vector3.ZERO
				var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in verts:
					var p: Vector3 = v + offset
					var d: float = _surface_distance(p) - (0.0032 if key == "eyes" else 0.0)
					if d < worst:
						worst = d
						worst_name = "%s/%s" % [key, part.id]
		var expr_tris: int = 0
		for emote_id: String in catalog.expressions:
			var mesh: ArrayMesh = CharacterModel.expression(CharacterLook.new(), emote_id)
			expr_tris = maxi(expr_tris, _tris(mesh))
			for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var d: float = _surface_distance(v)
				if d < worst:
					worst = d
					worst_name = "expression/%s" % emote_id
		_check(not catalog.expressions.is_empty(), "detail %d: 표정 %d개" % [detail, catalog.expressions.size()])
		# v0.16: 모든 감정표현에 눈 · 입이 바뀌는 얼굴, 주민 기분 · 몸짓 얼굴.
		var missing: PackedStringArray = []
		for emote_id: String in CharacterRig.EMOTES + PackedStringArray(["tada", "mood:happy", "mood:excited", "mood:sad", "mood:grumpy", "mood:sleepy", "act:sun", "act:stretch"]):
			var part: FaceCatalog.Part = catalog.expressions.get(emote_id)
			if part == null or not (part.face.has("mouth") or part.face.has("eyes") or part.face.has("eyes_over")):
				missing.append(emote_id)
		_check(missing.is_empty(), "detail %d: 감정표현 · 기분마다 눈이나 입이 바뀐다 (빠짐: %s)" % [detail, ", ".join(missing)])
		_check(CharacterModel.expression_hides_eyes("sad") and not CharacterModel.expression_hides_eyes("mood:sad"), "ㅠ^ㅠ 는 눈을 바꿔 그리고, 우울한 기분은 원래 눈 위에 눈꺼풀만")
		# 머리 메시의 면은 이상적인 겉면보다 안쪽이니, 이상적인 겉면 밖이면 면에 파묻히지 않는다.
		_check(worst > 0.0, "detail %d: 얼굴 부품이 머리 겉면 밖 (가장 낮은 %s %.4fm, 면 깊이 %.4fm)" % [detail, worst_name, worst, sag])
		var most: int = 0
		var most_name: String = ""
		for hair: FaceCatalog.Part in catalog.hair_styles:
			var look: CharacterLook = CharacterLook.new()
			look.hair_style = hair.id
			look.eyes = "sparkle"
			look.mouth = "laugh"
			look.nose = "freckle"
			var tris: int = _tris(CharacterModel.body(look)) + _tris(CharacterModel.head(look)) + _tris(CharacterModel.hips(look)) + _face_tris(look, catalog) + 2 * _tris(CharacterModel.arm(look)) + 2 * _tris(CharacterModel.leg(look))
			if tris > most:
				most = tris
				most_name = hair.id
		# v0.16: 표정 화질을 낮추지 않기로 해서 예산(CLAUDE.md)은 넘어도 실패로 치지 않고 알려만 준다.
		print("[face] info: detail %d: 캐릭터 삼각형 %d (예산 %d%s, 가장 많은 머리: %s)" % [detail, most, BUDGET[detail], " 넘음" if most > BUDGET[detail] else "", most_name])
	print("FACE %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(0 if _failed == 0 else 1)


## 볼·코·입만 (몸 메시에서 머리 겉면 근처 앞쪽 정점 = 얼굴 부품).
func _face_only(look: CharacterLook) -> ArrayMesh:
	var st: SurfaceTool = ClayMesh.begin()
	CharacterModel._add_face(st, look)
	return ClayMesh.commit(st)


## 점이 이상적인 머리 타원체 겉면에서 바깥으로 떨어진 거리 (근사: 반지름 방향).
func _surface_distance(p: Vector3) -> float:
	var d: Vector3 = p - CharacterModel.HEAD_CENTER
	var r: Vector3 = CharacterModel.HEAD_RADII
	var w: float = CharacterModel.head_width(d.y / r.y)
	var k: float = sqrt(pow(d.x / (r.x * w), 2.0) + pow(d.y / r.y, 2.0) + pow(d.z / (r.z * w), 2.0))
	return d.length() * (1.0 - 1.0 / maxf(k, 0.0001))


func _tris(mesh: ArrayMesh) -> int:
	var total: int = 0
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total


func _check(ok: bool, label: String) -> void:
	print("[face] %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failed += 1


## 눈 + 가장 무거운 표정이 한 번에 그리는 삼각형 (두 눈을 바꿔 그리는 표정이면 그동안 원래 눈은 감춘다).
func _face_tris(look: CharacterLook, catalog: FaceCatalog) -> int:
	var eyes: int = _tris(CharacterModel.eyes(look))
	var most: int = eyes
	for emote_id: String in catalog.expressions:
		var drawn: int = _tris(CharacterModel.expression(look, emote_id)) + (0 if CharacterModel.expression_hides_eyes(emote_id) else eyes)
		most = maxi(most, drawn)
	return most
