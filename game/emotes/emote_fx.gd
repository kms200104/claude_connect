class_name EmoteFx
extends RefCounted
## 감정표현 하는 동안 머리 둘레에 떠다니는 작은 도형·글자 (CharacterRig.play_emote 가 띄운다 — 나 · 상대 · 주민 모두 같다).
##   sad 눈물 방울이 볼에서 떨어지고 · sleepy Z 가 커지며 비스듬히 떠오르고 · love 하트가 몽글몽글 떠오르고
##   angry 분노 마크가 머리 옆에서 콩닥 · surprise 느낌표 · think 물음표 · happy/laugh/clap/hello 반짝이 별.
## 도형은 납작한 판(정점 색)을 화면 쪽으로 돌려 그린다 (반투명 없음, 다른 물체에 가리지 않게 맨 위에).

const NODE_NAME: String = "EmoteFx"
const TEAR: Color = Color("#7CC6F2")
const HEART: Color = Color("#F2647E")
const ANGER: Color = Color("#E8463C")
const STAR: Color = Color("#FFD24A")
const INK: Color = Color("#5A3E26")
## 효과를 붙이는 감정표현 (나머지는 몸짓만).
const KINDS: PackedStringArray = ["sad", "sleepy", "love", "angry", "surprise", "think", "happy", "laugh", "clap", "hello"]

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _material: StandardMaterial3D = null


## holder(리그 Visual, 머리 가운데가 y 0.4 쯤) 둘레에 emote_id 의 효과를 length 초 동안. 이미 떠 있던 건 걷어 낸다.
static func play(holder: Node3D, emote_id: String, length: float) -> void:
	if holder == null or not holder.is_inside_tree() or not emote_id in KINDS:
		return
	var old: Node = holder.get_node_or_null(NODE_NAME)
	if old != null:
		old.name = "%s_old" % NODE_NAME
		old.queue_free()
	var root: Node3D = Node3D.new()
	root.name = NODE_NAME
	holder.add_child(root)
	match emote_id:
		"sad":
			for i: int in 4:
				for side: float in [-1.0, 1.0]:
					_drop(root, Vector3(0.2 * side, 0.27, -0.33), 0.12 + float(i) * 0.42 + (0.2 if side > 0.0 else 0.0))
		"sleepy":
			for i: int in 3:
				_float_text(root, "Z", Vector3(0.28, 0.75, -0.05), Vector3(0.22, 0.42, 0.0), 0.35 + float(i) * 0.45, 1.1, 30 + i * 10)
		"love":
			for i: int in 5:
				var a: float = -0.9 + float(i) * 0.45
				_rise(root, _shape(root, "heart", HEART, 0.06 + float(i % 2) * 0.03), Vector3(sin(a) * 0.38, 0.62, -0.1), 0.1 + float(i) * 0.2, 0.9)
		"angry":
			_pulse(root, _shape(root, "anger", ANGER, 0.13), Vector3(0.36, 0.72, -0.12), minf(length, 1.0))
		"surprise":
			_float_text(root, "!", Vector3(0.0, 0.95, 0.0), Vector3(0.0, 0.12, 0.0), 0.04, 0.8, 70, STAR)
		"think":
			_float_text(root, "?", Vector3(0.3, 0.86, 0.0), Vector3(0.05, 0.12, 0.0), 0.3, maxf(length - 0.6, 0.6), 64)
		_:
			var count: int = 3 if emote_id == "hello" else 6
			for i: int in count:
				var a: float = TAU * float(i) / float(count) + 0.4
				_rise(root, _shape(root, "star", STAR, 0.05), Vector3(cos(a) * 0.5, 0.45 + sin(a * 1.7) * 0.25, -0.05), 0.1 + float(i) * 0.12, 0.6)
	root.get_tree().create_timer(length + 0.3).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())


## 볼에서 떨어지는 눈물 방울 (아래로 가며 작아진다).
static func _drop(root: Node3D, at: Vector3, delay: float) -> void:
	var node: Node3D = _shape(root, "tear", TEAR, 0.05)
	node.position = at
	node.visible = false
	var tween: Tween = node.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void: node.visible = true)
	tween.tween_property(node, "position", at + Vector3(0.0, -0.32, -0.04), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(node, "scale", Vector3.ONE * 0.4, 0.5)
	tween.tween_callback(func() -> void: node.visible = false)


## 떠오르며 커졌다 작아지는 도형 (하트 · 별).
static func _rise(root: Node3D, node: Node3D, at: Vector3, delay: float, duration: float) -> void:
	node.position = at
	node.scale = Vector3.ONE * 0.01
	var tween: Tween = node.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(node, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "position", at + Vector3(at.x * 0.3, 0.38, 0.0), duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, 0.2)


## 그 자리에서 콩닥콩닥 커졌다 작아지는 도형 (분노 마크).
static func _pulse(root: Node3D, node: Node3D, at: Vector3, duration: float) -> void:
	node.position = at
	node.scale = Vector3.ONE * 0.01
	var tween: Tween = node.create_tween()
	tween.tween_interval(0.1)
	tween.tween_property(node, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i: int in maxi(int(duration / 0.3), 1):
		tween.tween_property(node, "scale", Vector3.ONE * 0.85, 0.13)
		tween.tween_property(node, "scale", Vector3.ONE * 1.15, 0.13)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, 0.15)


## 글자 하나가 커지며 drift 만큼 떠오른다 (Z · ? · !).
static func _float_text(root: Node3D, text: String, at: Vector3, drift: Vector3, delay: float, duration: float, font_size: int, color: Color = Color.WHITE) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 3
	label.position = at
	label.scale = Vector3.ONE * 0.01
	root.add_child(label)
	var tween: Tween = label.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position", at + drift, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "scale", Vector3.ONE * 0.01, 0.18)


## 도형 하나: 바깥 노드(돌려주는 것, 위치·크기 트윈용) 안에 size 배로 줄인 판을 둔다.
static func _shape(root: Node3D, kind: String, color: Color, size: float) -> Node3D:
	var node: Node3D = Node3D.new()
	root.add_child(node)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh(kind, color)
	mi.material_override = _flat_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	node.add_child(mi)
	return node


## 반지름 1 의 납작한 도형 (XY 평면, 머티리얼이 화면 쪽으로 돌린다). 모양·색마다 한 번만 만든다.
static func _mesh(kind: String, color: Color) -> ArrayMesh:
	var key: String = "%s|%s" % [kind, color.to_html(false)]
	if _meshes.has(key):
		return _meshes[key]
	var outline: PackedVector2Array = PackedVector2Array()
	var tris: PackedVector2Array = PackedVector2Array()
	match kind:
		"tear":
			# 위가 뾰족한 물방울.
			for i: int in 20:
				var t: float = TAU * float(i) / 20.0
				var r: float = 1.0 if sin(t) < 0.0 else lerpf(1.0, 0.0, pow(sin(t), 1.6))
				outline.append(Vector2(cos(t) * r * 0.75, sin(t) * (1.4 if sin(t) > 0.0 else 0.8)))
		"heart":
			for i: int in 28:
				var t: float = TAU * float(i) / 28.0
				outline.append(Vector2(16.0 * pow(sin(t), 3.0), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) / 16.0)
		"star":
			for i: int in 8:
				var a: float = PI * 0.5 + PI * float(i) / 4.0
				outline.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.32))
		"anger":
			# 분노 마크: 네 모서리에서 가운데 쪽으로 휜 굵은 고리 넷.
			for q: int in 4:
				var c: Vector2 = Vector2(1.0 if q % 2 == 0 else -1.0, 1.0 if q < 2 else -1.0) * 0.55
				var start: float = atan2(-c.y, -c.x) - 1.1
				var inner: PackedVector2Array = PackedVector2Array()
				var outer: PackedVector2Array = PackedVector2Array()
				for k: int in 7:
					var a: float = start + 2.2 * float(k) / 6.0
					outer.append(c + Vector2(cos(a), sin(a)) * 0.5)
					inner.append(c + Vector2(cos(a), sin(a)) * 0.24)
				for k: int in 6:
					tris.append_array(PackedVector2Array([outer[k], outer[k + 1], inner[k + 1], outer[k], inner[k + 1], inner[k]]))
	if tris.is_empty():
		for i: int in Geometry2D.triangulate_polygon(outline):
			tris.append(outline[i])
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector2 in tris:
		st.set_color(color)
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(p.x, p.y, 0.0))
	var mesh: ArrayMesh = st.commit()
	_meshes[key] = mesh
	return mesh


## 조명 없이 정점 색 그대로, 화면을 향하고, 양면, 다른 물체에 가리지 않는다.
static func _flat_material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.billboard_keep_scale = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.render_priority = 2
	return _material
