class_name MultiTouch
extends Node
## v0.28.16 두 번째 손가락으로도 누르는 단추: Godot 은 첫 손가락만 마우스로 흉내 내서 (emulate_mouse_from_touch),
## 조이스틱을 쥔 채 다른 손가락으로 '구르기' · 상황 단추 · 기술 단추를 누르면 Button 이 받지 못했다 (움직이며 구르기 불가).
## 그룹 GROUP 의 단추는 첫 손가락이 아닌 터치 (index > 0) 가 닿는 순간 pressed 를 낸다. 첫 손가락은 원래대로 (마우스 흉내).

const GROUP: StringName = &"multi_touch"


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null or not touch.pressed or touch.index == 0:
		return
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var b: BaseButton = node as BaseButton
		if b == null or b.disabled or not b.is_visible_in_tree():
			continue
		if b.get_global_rect().has_point(touch.position):
			get_viewport().set_input_as_handled()
			b.pressed.emit()
			return
