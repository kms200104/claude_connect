class_name FontScaler
extends Node
## 글자 크기 설정 (v16): 화면의 글자(Label · Button · LineEdit · TextEdit · RichTextLabel)를 Prefs.font_scale() 배로.
## 창마다 글자 크기를 직접 정해 두었으니(add_theme_font_size_override), 처음 정한 크기를 기억해 두고(meta) 배율만 곱한다.
## 새로 생기는 컨트롤은 트리에 들어온 다음 프레임에 맞추고, 설정을 바꾸면 화면의 것을 모두 다시 맞춘다.
## ScreenFit 이 루트에 하나 붙인다.

const META: StringName = &"font_base"
const KEYS: Dictionary[String, StringName] = {"RichTextLabel": &"normal_font_size"}

var _scale: float = 1.0


func _ready() -> void:
	_scale = Prefs.font_scale()
	get_tree().node_added.connect(_on_node_added)
	Prefs.events.changed.connect(func(key: String) -> void:
		if key == Prefs.FONT:
			_scale = Prefs.font_scale()
			_apply_all(get_tree().root))


func _on_node_added(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit or node is TextEdit or node is RichTextLabel:
		_apply.call_deferred(node)


func _apply_all(node: Node) -> void:
	if node is Control:
		_apply(node)
	for child: Node in node.get_children():
		_apply_all(child)


func _apply(node: Node) -> void:
	var c: Control = node as Control
	if c == null or not is_instance_valid(c) or not (c is Label or c is Button or c is LineEdit or c is TextEdit or c is RichTextLabel):
		return
	var key: StringName = KEYS.get(c.get_class(), &"font_size")
	var current: int = c.get_theme_font_size(key)
	var base: int = int(c.get_meta(META, 0))
	# 코드가 나중에 크기를 바꿨으면(배율을 곱한 값이 아니면) 그 크기를 새 기준으로.
	if base <= 0 or current != roundi(base * float(c.get_meta(&"font_scale", 1.0))):
		base = current
	c.set_meta(META, base)
	c.set_meta(&"font_scale", _scale)
	var want: int = maxi(8, roundi(base * _scale))
	if want != current:
		c.add_theme_font_size_override(key, want)
