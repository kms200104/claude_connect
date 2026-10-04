class_name DialogueBox
extends Control
## 주민 대사 창 (화면 아래, 퀵슬롯 위). 글자가 한 자씩 나오고, 누르면 다 보이거나 다음으로 넘어간다.
## 선택지가 있으면 버튼으로 고른다. 대화 흐름은 DialogueController 가 정하고 여기서는 보여 주기만 한다.

## 대사를 다 본 뒤 눌렀다.
signal advanced
## 선택지를 골랐다 (창이 닫히면 -1).
signal chosen(index: int)

@export_range(5.0, 200.0, 1.0, "suffix:자/초") var chars_per_second: float = 40.0

@onready var _panel: PanelContainer = %Panel
@onready var _name_tag: Label = %NameTag
@onready var _text: Label = %Text
@onready var _next_mark: Label = %NextMark
@onready var _choices: VBoxContainer = %Choices

## 말하는 사람의 목소리 높이 (1 = 보통, 0 = 말소리 없음). 글자가 나올 때마다 '웅앵' 음절을 낸다.
var voice: float = 0.0

var _typing_tween: Tween = null
var _waiting_choice: bool = false
var _spoken: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.gui_input.connect(_on_panel_input)
	_panel.add_to_group(&"blocks_joystick")
	_choices.add_to_group(&"blocks_joystick")
	close()


func is_open() -> bool:
	return _panel.visible


func is_typing() -> bool:
	return _typing_tween != null and _typing_tween.is_valid() and _typing_tween.is_running()


func show_line(speaker: String, text: String, color: Color = Color.WHITE) -> void:
	_panel.visible = true
	_clear_choices()
	_name_tag.text = speaker
	_name_tag.add_theme_color_override("font_color", color)
	_text.text = text
	_text.visible_ratio = 0.0
	_spoken = 0
	_next_mark.visible = false
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = create_tween()
	_typing_tween.tween_property(_text, "visible_ratio", 1.0, maxf(text.length() / chars_per_second, 0.05))
	_typing_tween.finished.connect(func() -> void: _next_mark.visible = not _waiting_choice)


func _process(_delta: float) -> void:
	if voice <= 0.0 or not is_typing():
		return
	# 새로 보인 글자 중 두 글자마다 한 음절 (너무 수다스럽지 않게).
	var shown: int = int(_text.visible_ratio * _text.text.length())
	while _spoken < shown:
		if _spoken % 2 == 0:
			Audio.babble(_text.text[_spoken], voice)
		_spoken += 1


func show_choices(options: PackedStringArray) -> void:
	_finish_typing()
	_clear_choices()
	_waiting_choice = true
	_next_mark.visible = false
	for i: int in options.size():
		var b: Button = Button.new()
		b.text = options[i]
		b.custom_minimum_size = Vector2(0, 96)
		b.add_theme_font_size_override("font_size", 40)
		b.pressed.connect(_on_choice.bind(i))
		_choices.add_child(b)
	_choices.visible = true


## 화면 밖에서(테스트·자동 진행) 대사를 넘긴다. 글자가 나오는 중이면 끝까지 보여 준다.
func press() -> void:
	if not _panel.visible or _waiting_choice:
		return
	Audio.play_ui(Audio.SFX_CLICK)
	if is_typing():
		_finish_typing()
		return
	advanced.emit()


## 창을 닫는다. 기다리던 쪽이 멈춰 있지 않게 신호를 한 번 보낸다.
func close() -> void:
	var was_open: bool = _panel.visible
	_panel.visible = false
	_clear_choices()
	if was_open:
		advanced.emit()
		chosen.emit(-1)


## 기다리는 쪽을 깨우지 않고 창만 숨긴다 (대화 도중 다른 창을 잠깐 열 때).
func close_quietly() -> void:
	_panel.visible = false
	_clear_choices()


func _on_panel_input(event: InputEvent) -> void:
	# 폰의 터치는 마우스 클릭으로도 들어온다(emulate_mouse_from_touch). 두 번 넘어가지 않게 마우스만 본다.
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		press()


func _finish_typing() -> void:
	if _typing_tween != null and _typing_tween.is_valid():
		_typing_tween.kill()
	_text.visible_ratio = 1.0
	_next_mark.visible = not _waiting_choice


func _on_choice(index: int) -> void:
	Audio.play_ui(Audio.SFX_CONFIRM)
	_clear_choices()
	chosen.emit(index)


func _clear_choices() -> void:
	_waiting_choice = false
	for child: Node in _choices.get_children():
		child.queue_free()
	_choices.visible = false
