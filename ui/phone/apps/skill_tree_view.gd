class_name SkillTreeView
extends Control
## v0.28.8 헌터넷 '전직' 탭의 기술 나무: 줄 (row 1~4, 위에서 아래) × 칸 (col) 에 둥근 기술 단추, 앞 기술 → 뒤 기술을 선으로 잇는다.
## 배운 기술은 직업 색으로 채우고 단계 (1/5) 를, 지금 배울 수 있는 것은 테두리가 반짝인다. 잠긴 것은 흐리다.
## 누르면 picked(node_id) — 앱이 아래에 설명 · '배우기' 를 띄운다. 판정은 서버 (Net.skill_up).

signal picked(node_id: String)

const NODE: float = 132.0
const ROW_H: float = 210.0
const INK: Color = Color("#3A3028")
const LOCKED: Color = Color("#B8B0A4")

var job_id: String = ""
var color: Color = Color("#E0603A")
var learned: Dictionary = {}
var points: int = 0
var selected: String = ""
## v0.28.9 2차 전직을 했는지 (5 · 6줄 adv 기술이 열린다) · 2차 직업 색.
var advanced: bool = false
var adv_color: Color = Color("#C8302A")
var _buttons: Dictionary[String, Button] = {}
var _time: float = 0.0


func setup(p_job: String, p_learned: Dictionary, p_points: int, p_selected: String, width: float, p_advanced: bool = false) -> void:
	job_id = p_job
	learned = p_learned
	points = p_points
	selected = p_selected
	advanced = p_advanced
	var job: Dictionary = GameData.hunter.job(job_id)
	color = Color(str(job.get("color", "#E0603A")))
	adv_color = Color(str((job.get("advance", {}) as Dictionary).get("color", job.get("color", "#C8302A"))))
	var rows: int = 1
	var cols: int = 1
	for n: Variant in job.get("tree", []):
		rows = maxi(rows, int((n as Dictionary).get("row", 1)))
		cols = maxi(cols, int((n as Dictionary).get("col", 0)) + 1)
	custom_minimum_size = Vector2(width, rows * ROW_H + 20.0)
	for b: Button in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for n: Variant in job.get("tree", []):
		var node: Dictionary = n
		var id: String = str(node.get("id", ""))
		var b: Button = Button.new()
		b.name = "Node_%s" % id
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.size = Vector2(NODE, NODE)
		b.position = node_center(node, width, cols) - Vector2(NODE, NODE) * 0.5
		b.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			picked.emit(id))
		b.draw.connect(_draw_node.bind(b, node))
		add_child(b)
		_buttons[id] = b
	queue_redraw()


func node_center(node: Dictionary, width: float, cols: int) -> Vector2:
	var col: int = int(node.get("col", 0))
	var x: float = width * (float(col) + 0.5) / float(maxi(cols, 1))
	# 칸이 하나뿐인 줄 (액티브 줄) 은 가운데보다 왼쪽 칸에 둔다 (왼쪽 갈래에서 이어진다).
	return Vector2(x, 20.0 + (float(node.get("row", 1)) - 0.5) * ROW_H)


func node_button(id: String) -> Button:
	return _buttons.get(id)


func _process(delta: float) -> void:
	_time += delta
	# 배울 수 있는 기술 테두리가 은은하게 숨 쉰다.
	for b: Button in _buttons.values():
		b.queue_redraw()


func _draw() -> void:
	# 2차 전직 줄 (adv) 위에 구분선과 이름.
	var first_adv: int = 99
	for n: Variant in GameData.hunter.job(job_id).get("tree", []):
		if bool((n as Dictionary).get("adv", false)):
			first_adv = mini(first_adv, int((n as Dictionary).get("row", 99)))
	if first_adv < 99:
		var y: float = 20.0 + (float(first_adv) - 1.0) * ROW_H - 6.0
		draw_dashed_line(Vector2(20.0, y), Vector2(size.x - 20.0, y), Color(adv_color, 0.7 if advanced else 0.35), 4.0, 16.0)
		var adv_name: String = str((GameData.hunter.job(job_id).get("advance", {}) as Dictionary).get("name", "2차 전직"))
		draw_string(get_theme_default_font(), Vector2(24.0, y + 30.0), "%s%s" % [adv_name, "" if advanced else " (Lv.%d)" % GameData.hunter.job_advance_level], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(adv_color, 1.0 if advanced else 0.55))
	# 앞 기술 → 뒤 기술 선 (배웠으면 직업 색, 아니면 흐린 회색).
	for n: Variant in GameData.hunter.job(job_id).get("tree", []):
		var node: Dictionary = n
		var to: Button = _buttons.get(str(node.get("id", "")))
		if to == null:
			continue
		for r: Variant in node.get("req", []):
			var from: Button = _buttons.get(str(r))
			if from == null:
				continue
			var on: bool = int(learned.get(str(r), 0)) > 0
			var a: Vector2 = from.position + from.size * 0.5 + Vector2(0.0, NODE * 0.5)
			var b: Vector2 = to.position + to.size * 0.5 - Vector2(0.0, NODE * 0.5)
			draw_line(a, b, color if on else LOCKED, 10.0 if on else 6.0, true)


func _draw_node(b: Button, node: Dictionary) -> void:
	var id: String = str(node.get("id", ""))
	var rank: int = int(learned.get(id, 0))
	var mx: int = int(node.get("max", 1))
	var block: String = GameData.hunter.job_node_block(job_id, learned, points, id, advanced)
	var can: bool = block.is_empty()
	var locked: bool = rank == 0 and not can and not block.begins_with("기술 포인트")
	var nc: Color = adv_color if bool(node.get("adv", false)) else color
	var c: Vector2 = b.size * 0.5
	var r: float = NODE * 0.46
	var active: bool = not str(node.get("active", "")).is_empty()
	var fill: Color = nc if rank > 0 else (Color("#F6F0E4") if not locked else Color("#E2DCD2"))
	if active:
		# 액티브 기술은 마름모.
		var pts: PackedVector2Array = [c + Vector2(0, -r * 1.08), c + Vector2(r * 1.08, 0), c + Vector2(0, r * 1.08), c + Vector2(-r * 1.08, 0)]
		b.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		b.draw_polyline(pts, INK if not locked else LOCKED, 5.0, true)
	else:
		b.draw_circle(c, r, fill)
		b.draw_arc(c, r, 0.0, TAU, 48, INK if not locked else LOCKED, 5.0, true)
	if can:
		var glow: float = 0.5 + 0.5 * sin(_time * 4.0)
		b.draw_arc(c, r + 9.0, 0.0, TAU, 48, Color("#FFD24A", 0.45 + 0.5 * glow), 6.0, true)
	if id == selected:
		b.draw_arc(c, r + 16.0, 0.0, TAU, 48, Color("#3A9AF0"), 5.0, true)
	var font: Font = get_theme_default_font()
	var name_txt: String = str(node.get("name", id))
	var txt_c: Color = Color.WHITE if rank > 0 else (INK if not locked else LOCKED)
	var fs: int = 26 if name_txt.length() <= 3 else 22
	b.draw_string(font, Vector2(4.0, c.y + 2.0), name_txt, HORIZONTAL_ALIGNMENT_CENTER, NODE - 8.0, fs, txt_c)
	b.draw_string(font, Vector2(4.0, c.y + 32.0), "%d/%d" % [rank, mx], HORIZONTAL_ALIGNMENT_CENTER, NODE - 8.0, 22, txt_c)
