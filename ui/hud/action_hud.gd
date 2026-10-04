class_name ActionHud
extends Control
## 상황 버튼 하나 (대화 / 베기). 낚시 버튼(FishingHud)과 같은 자리에 뜨고, 둘 중 하나만 보인다.

signal action_pressed

@onready var _button: Button = %ActionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.pressed.connect(func() -> void: action_pressed.emit())
	_button.add_to_group(&"blocks_joystick")
	hide_action()


func show_action(text: String) -> void:
	_button.text = text
	_button.visible = true


func hide_action() -> void:
	_button.visible = false


func is_showing() -> bool:
	return _button.visible


func current_text() -> String:
	return _button.text if _button.visible else ""
