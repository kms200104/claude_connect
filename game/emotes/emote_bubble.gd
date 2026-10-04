class_name EmoteBubble
extends RefCounted
## 머리 위 말풍선: 감정표현 아이콘(Sprite3D)이 퐁 하고 떠올랐다가 사라지고, 짧은 대사(Label3D)를 띄우기도 한다.
## 아이콘은 assets/ui/emotes/<id>.png (알파 시저, 화면을 향함, 다른 물체에 가리지 않음).

const ICON_NAME: String = "EmoteBubble"
const SAY_NAME: String = "SayBubble"


## parent 머리 위(height)에 감정표현 아이콘을 띄운다. 이미 떠 있던 건 바꾼다.
static func pop(parent: Node3D, emote_id: String, height: float = 2.3, hold: float = 1.8) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var texture: Texture2D = EmoteInfo.icon(emote_id)
	if texture == null:
		return
	var old: Node = parent.get_node_or_null(ICON_NAME)
	if old != null:
		old.name = "%s_old" % ICON_NAME
		old.queue_free()
	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = ICON_NAME
	sprite.texture = texture
	sprite.pixel_size = 0.0042
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 2
	parent.add_child(sprite)
	sprite.position = Vector3(0.0, height, 0.0)
	sprite.scale = Vector3(0.05, 0.05, 0.05)
	var tween: Tween = sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "position:y", height + 0.15, 0.28)
	tween.tween_property(sprite, "position:y", height + 0.25, hold).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, "scale", Vector3(0.05, 0.05, 0.05), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(sprite.queue_free)


## parent 머리 위에 짧은 대사를 잠깐 띄운다 (주민이 감정표현에 반응할 때).
static func say(parent: Node3D, text: String, height: float = 2.95, hold: float = 2.6) -> void:
	if parent == null or not parent.is_inside_tree() or text.is_empty():
		return
	var old: Node = parent.get_node_or_null(SAY_NAME)
	if old != null:
		old.name = "%s_old" % SAY_NAME
		old.queue_free()
	var label: Label3D = Label3D.new()
	label.name = SAY_NAME
	label.text = text
	label.font_size = 34
	label.pixel_size = 0.0068
	label.outline_size = 14
	label.modulate = Color("#FFF8EA")
	label.outline_modulate = Color("#5A3E26")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = 330.0
	label.render_priority = 3
	parent.add_child(label)
	label.position = Vector3(0.0, height, 0.0)
	label.modulate.a = 0.0
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.18)
	tween.tween_interval(hold)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.queue_free)
