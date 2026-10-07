class_name PickupTag
extends Node3D
## 주울 수 있는 것에 다가가면 그 위에 뜨는 이름표 (v13). "목재 ×3", "선물 풍선", "나무 의자" 처럼 무엇인지 알려 준다.
## 대상이 바뀌면 톡 튀어 오르고, 떠 있는 동안 살짝 위아래로 흔들린다. 화면 크기가 거리와 상관없이 같다(fixed_size).

@export_range(16, 96, 1) var font_size: int = 40
@export var text_color: Color = Color(0.36, 0.24, 0.14)
@export var outline_color: Color = Color(1.0, 0.97, 0.88)

var _label: Label3D = null
var _target_key: String = ""
var _base: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _pop: Tween = null


func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = font_size
	_label.outline_size = 22
	_label.modulate = text_color
	_label.outline_modulate = outline_color
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.outline_render_priority = 9
	_label.double_sided = true
	add_child(_label)
	visible = false


## 이름표를 at(월드) 위에 띄운다. key 가 바뀌면(다른 물건) 톡 튀어 오른다. text 가 비면 숨긴다.
func show_at(key: String, at: Vector3, text: String) -> void:
	if text.is_empty():
		hide_tag()
		return
	_base = at
	_label.text = text
	if key != _target_key or not visible:
		_target_key = key
		visible = true
		global_position = _base
		if _pop != null and _pop.is_valid():
			_pop.kill()
		scale = Vector3.ONE * 0.4
		_pop = create_tween()
		_pop.tween_property(self, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_tag() -> void:
	_target_key = ""
	visible = false


func current_text() -> String:
	return _label.text if visible and _label != null else ""


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	global_position = _base + Vector3(0.0, sin(_time * 2.6) * 0.04, 0.0)
