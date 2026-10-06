class_name FishingHud
extends Control
## 낚시 버튼, 입질 표시(!), 챔질 제한 시간 막대, 결과 문구. 판단은 하지 않고 신호만 보낸다.

signal action_pressed
signal cancel_pressed

@export var toast_seconds: float = 1.8

@onready var _action: Button = %ActionButton
@onready var _cancel: Button = %CancelButton
@onready var _status: Label = %StatusLabel
@onready var _bite_mark: Label = %BiteMark
@onready var _window_bar: ProgressBar = %WindowBar
@onready var _toast: Label = %ToastLabel

var _window_started_ms: float = 0.0
var _window_ms: float = 0.0
var _toast_token: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action.pressed.connect(func() -> void: action_pressed.emit())
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	# 가로 화면: 상황 버튼(ActionHud)과 같은 자리로 비킨다.
	HudLayout.landscape_shift(_action, -170.0)
	HudLayout.landscape_shift(_cancel, -170.0)
	reset()


func _process(_delta: float) -> void:
	if _window_bar.visible and _window_ms > 0.0:
		var left: float = 1.0 - (Time.get_ticks_msec() - _window_started_ms) / _window_ms
		_window_bar.value = clampf(left, 0.0, 1.0) * 100.0


func reset() -> void:
	_action.visible = false
	_cancel.visible = false
	_status.visible = false
	_bite_mark.visible = false
	_window_bar.visible = false
	_window_ms = 0.0


const FISHING_ICON: Texture2D = preload("res://assets/ui/icons/fishing.png")


func show_cast_available(available: bool) -> void:
	if _cancel.visible or _status.visible:
		return
	_action.visible = available
	_action.disabled = false
	_action.text = "낚시"
	_action.icon = FISHING_ICON


func show_casting() -> void:
	_action.disabled = true
	_status.visible = true
	_status.text = "던지는 중…"


func show_waiting() -> void:
	_action.visible = true
	_action.disabled = false
	_action.text = "당기기"
	_cancel.visible = true
	_status.visible = true
	_status.text = "찌를 지켜보세요…"
	_bite_mark.visible = false
	_window_bar.visible = false


func show_nibble() -> void:
	_status.text = "톡톡… 아직이에요!"
	var tween: Tween = create_tween()
	_status.pivot_offset = _status.size * 0.5
	tween.tween_property(_status, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(_status, "scale", Vector2.ONE, 0.16)


func show_bite(window_ms: int) -> void:
	_status.text = "지금이에요!"
	_bite_mark.visible = true
	_action.text = "당겨!"
	_window_ms = float(window_ms)
	_window_started_ms = Time.get_ticks_msec()
	_window_bar.visible = true
	_window_bar.value = 100.0
	_bite_mark.pivot_offset = _bite_mark.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(_bite_mark, "scale", Vector2(1.35, 1.35), 0.1)
	tween.tween_property(_bite_mark, "scale", Vector2.ONE, 0.2)


## 끌어올리기 연타: 큰 단추를 계속 누른다. 위쪽 막대는 남은 시간.
func show_reel(taps: int, _ms: int) -> void:
	_window_ms = 0.0
	_bite_mark.visible = false
	_action.visible = true
	_action.disabled = false
	_action.text = "감아올려!"
	_cancel.visible = false
	_status.visible = true
	_window_bar.visible = true
	_window_bar.value = 100.0
	update_reel(0, taps, 1.0)


func update_reel(count: int, need: int, time_left: float) -> void:
	_status.text = "연타! %d / %d" % [mini(count, need), need]
	_window_bar.value = clampf(time_left, 0.0, 1.0) * 100.0
	if count > 0:
		_action.pivot_offset = _action.size * 0.5
		var tween: Tween = create_tween()
		tween.tween_property(_action, "scale", Vector2(0.92, 0.92), 0.04)
		tween.tween_property(_action, "scale", Vector2.ONE, 0.08)


func show_hooked() -> void:
	_action.disabled = true
	_status.text = "…"


func show_result(text: String, success: bool) -> void:
	_action.visible = false
	_cancel.visible = false
	_status.visible = false
	_bite_mark.visible = false
	_window_bar.visible = false
	show_toast(text, success)


func show_toast(text: String, success: bool) -> void:
	_toast.text = text
	_toast.modulate = Color(0.75, 1.0, 0.8) if success else Color(1.0, 0.85, 0.7)
	# 빈 글이면 토스트 없이 조작 단추만 숨긴다 (자랑 카드가 대신 뜰 때).
	_toast.visible = not text.is_empty()
	_toast_token += 1
	var token: int = _toast_token
	await get_tree().create_timer(toast_seconds).timeout
	if token == _toast_token:
		_toast.visible = false
