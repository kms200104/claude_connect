class_name ActionHud
extends Control
## 상황 버튼 하나 (대화 / 베기). 낚시 버튼(FishingHud)과 같은 자리에 뜨고, 둘 중 하나만 보인다.

signal action_pressed

@onready var _button: Button = %ActionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.pressed.connect(func() -> void: action_pressed.emit())
	_button.add_to_group(&"blocks_joystick")
	# 가로 화면: 오른쪽 단추 줄(휴대폰 · 감정표현) 왼쪽으로 비킨다.
	HudLayout.landscape_shift(_button, -170.0)
	hide_action()


## 버튼 글자 위에 그릴 그림 (없으면 글자만).
const ICONS: Dictionary[String, String] = {
	"베기": "res://assets/icons/items/axe.png",
	"들어가기": "res://assets/ui/icons/shop.png",
	"나가기": "res://assets/ui/icons/shop.png",
	"줍기": "res://assets/icons/items/log_stool.png",
	"선물 줍기": "res://assets/ui/icons/gift.png",
	"별 줍기": "res://assets/icons/items/star_fragment.png",
}


func show_action(text: String) -> void:
	if _button.text != text or not _button.visible:
		var path: String = ICONS.get(text, "")
		_button.icon = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	_button.text = text
	_button.visible = true


func hide_action() -> void:
	_button.visible = false


func is_showing() -> bool:
	return _button.visible


func current_text() -> String:
	return _button.text if _button.visible else ""
