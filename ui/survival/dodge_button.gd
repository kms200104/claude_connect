class_name DodgeButton
extends Button
## v0.28.7 회피 구르기 단추 (오른쪽, 행동 단추 위): 누르면 서버에 구르기를 청한다 (Net.dodge).
## 서버가 허락하면 (Net.dodged) 플레이어가 미는 방향으로 구르고, 구르는 처음 동안은 맞지 않는다 (서버 판정).
## 다시 쓸 수 있을 때까지 남은 초를 단추 위에 보여 준다. 탈것을 타거나 쓰러져 있으면 숨긴다.

const SIZE: float = 120.0

var player: Player = null
var _cool: Label = null
var _pending_until: int = 0


func _ready() -> void:
	name = "DodgeButton"
	focus_mode = Control.FOCUS_NONE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -235.0
	offset_right = -235.0 + SIZE
	offset_top = -595.0
	offset_bottom = -595.0 + SIZE
	add_to_group(&"blocks_joystick")
	add_to_group(MultiTouch.GROUP)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	style.border_color = Color("#E8E0D0")
	style.set_border_width_all(4)
	style.set_corner_radius_all(int(SIZE * 0.5))
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, style)
	text = "구르기"
	add_theme_font_size_override("font_size", 28)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color.BLACK)
	_cool = Label.new()
	_cool.name = "Cool"
	_cool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cool.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cool.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cool.add_theme_font_size_override("font_size", 40)
	_cool.add_theme_constant_override("outline_size", 8)
	_cool.add_theme_color_override("font_outline_color", Color.BLACK)
	_cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cool.visible = false
	add_child(_cool)
	pressed.connect(_press)
	Net.dodged.connect(_on_dodged)
	Net.request_failed.connect(func(kind: String, _code: String) -> void:
		if kind == "dodge":
			_pending_until = 0)


func _press() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _pending_until or now < Net.dodge_ready_at:
		return
	if player != null and (player.is_rolling() or player.is_riding()):
		return
	_pending_until = now + 800
	Net.dodge()


func _on_dodged(ms: int, dist: float) -> void:
	_pending_until = 0
	if player != null:
		player.start_dodge(ms, dist)
	Prefs.vibrate(20, 0.3)


func _process(_delta: float) -> void:
	var down: bool = Net.downed.has(Net.my_id)
	var show: bool = Net.state == Net.State.ONLINE and not down and not (player != null and player.is_riding())
	if visible != show:
		visible = show
	var left: int = Net.dodge_ready_at - Time.get_ticks_msec()
	_cool.visible = left > 0
	if left > 0:
		_cool.text = "%.1f" % (float(left) / 1000.0)
	modulate.a = 0.5 if left > 0 else 1.0
	add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.0 if left > 0 else 1.0))
