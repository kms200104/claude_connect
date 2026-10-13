class_name StoreApp
extends PhoneApp
## 앱 스토어 (v0.20): 휴대폰에 앱을 받아 설치한다. 받기 → 내려받는 막대(크기만큼 걸린다) → 설치 → 홈 화면에 아이콘이 생긴다.
## 받은 앱은 열기 · 삭제할 수 있다 (Prefs.APPS, 이 휴대폰에만). 기본 앱은 지울 수 없다.

const BLUE: Color = Color("#3A7BEA")
## 받을 수 있는 앱: kind(홈 아이콘) · 이름 · 만든 곳 · 크기(MB) · 별점 · 설명.
const CATALOG: Array[Dictionary] = [
	{"kind": "steps", "name": "솔걸음", "dev": "솔바람 헬스케어", "mb": 12.4, "rating": 4.8, "tag": "건강 · 만보기",
		"desc": "휴대폰을 들고 걸으면 걸음을 세어 줘요. 하루 1천 · 3천 · 5천 · 1만 걸음을 넘기면 솔을 받아요. (게임이 켜져 있는 동안 가속도 센서로 세요)"},
	{"kind": "safety", "name": "안전알림", "dev": "솔바람시청 · 민방위", "mb": 8.1, "rating": 4.6, "tag": "생활 · 안전",
		"desc": "받은 재난문자를 모아 보고, 가까운 민방위 대피소와 다음 민방위 훈련 일정, 낙뢰 · 폭염 · 한파 행동요령을 알려 줘요."},
]
## 내려받기 빠르기 (MB/초) — 실제처럼 크기만큼 걸린다.
const MB_PER_SECOND: float = 6.0

## 내려받는 중인 앱 → 0~1.
var _progress: Dictionary[String, float] = {}
var _confirm_delete: String = ""


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _progress.is_empty():
		return
	var finished: Array[String] = []
	for kind: String in _progress:
		var mb: float = float(_entry(kind).get("mb", 10.0))
		_progress[kind] = minf(1.0, _progress[kind] + delta * MB_PER_SECOND / mb)
		var bar: Node = find_child("Progress_%s" % kind, true, false)
		if bar != null:
			(bar as ProgressBar).value = _progress[kind] * 100.0
		if _progress[kind] >= 1.0:
			finished.append(kind)
	for kind: String in finished:
		_progress.erase(kind)
		if phone != null:
			phone.set_installed(kind, true)
		Audio.play_sfx("quest_done", -8.0)
		_build()


## 테스트: 바로 다 받은 것으로.
func finish_downloads() -> void:
	for kind: String in _progress.keys():
		_progress[kind] = 1.0
	_process(0.0)


func _entry(kind: String) -> Dictionary:
	for e: Dictionary in CATALOG:
		if str(e["kind"]) == kind:
			return e
	return {}


func _installed(kind: String) -> bool:
	return phone != null and phone.is_installed(kind)


func _build() -> void:
	clear()
	var head: VBoxContainer = card()
	head.add_child(label("솔바람 앱 스토어", 34, INK))
	head.add_child(label("필요한 앱을 받아 홈 화면에 두세요. 받은 앱은 언제든 지울 수 있어요.", 24, SOFT))
	add_child(label("추천 앱", 30, INK))
	for e: Dictionary in CATALOG:
		_app_card(e)
	add_child(label("기본 앱 (지울 수 없어요)", 26, SOFT))
	var basics: PackedStringArray = []
	for i: int in PhoneWindow.TAB_NAMES.size():
		if not PhoneWindow.DOWNLOADABLE.has(i) and i != PhoneWindow.Tab.STORE:
			basics.append(PhoneWindow.TAB_NAMES[i])
	add_child(label(" · ".join(basics), 22, SOFT))


func _app_card(e: Dictionary) -> void:
	var kind: String = str(e["kind"])
	var c: VBoxContainer = card()
	c.get_parent().name = "Store_%s" % kind
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	c.add_child(row)
	var i: int = PhoneWindow.APP_KINDS.find(kind)
	var icon: PhoneAppIcon = PhoneAppIcon.new(kind, PhoneProp.ICON_COLORS[i] if i >= 0 else BLUE, 116.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(label(str(e["name"]), 32, INK, false))
	info.add_child(label("%s · %s" % [str(e["dev"]), str(e["tag"])], 22, SOFT, false))
	info.add_child(label("★ %.1f · %.1fMB · 무료" % [float(e["rating"]), float(e["mb"])], 22, SOFT, false))
	c.add_child(label(str(e["desc"]), 23, INK))
	if _progress.has(kind):
		var bar: ProgressBar = ProgressBar.new()
		bar.name = "Progress_%s" % kind
		bar.custom_minimum_size = Vector2(0, 36)
		bar.value = _progress[kind] * 100.0
		c.add_child(bar)
		c.add_child(label("내려받는 중… (%.1fMB)" % float(e["mb"]), 22, SOFT))
		return
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	c.add_child(buttons)
	if _installed(kind):
		var open: Button = button("열기", 28, Color.WHITE)
		open.name = "Open_%s" % kind
		open.add_theme_stylebox_override("normal", EventHud._box(BLUE, BLUE.darkened(0.2), 22, 3, 10))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(func() -> void:
			if phone != null:
				phone.open_app(PhoneWindow.APP_KINDS.find(kind)))
		buttons.add_child(open)
		var del: Button = button("정말 지울까요?" if _confirm_delete == kind else "삭제", 26, WARN if _confirm_delete == kind else SOFT)
		del.name = "Delete_%s" % kind
		del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		del.pressed.connect(func() -> void:
			if _confirm_delete != kind:
				_confirm_delete = kind
				_build()
				return
			_confirm_delete = ""
			if phone != null:
				phone.set_installed(kind, false)
			_build())
		buttons.add_child(del)
	else:
		var get_button: Button = button("받기", 30, Color.WHITE)
		get_button.name = "Get_%s" % kind
		get_button.add_theme_stylebox_override("normal", EventHud._box(BLUE, BLUE.darkened(0.2), 22, 3, 10))
		get_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		get_button.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			_progress[kind] = 0.0
			_build())
		buttons.add_child(get_button)
