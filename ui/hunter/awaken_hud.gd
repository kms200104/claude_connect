class_name AwakenHud
extends Control
## v0.28.5 헌터 각성 (HUD · 그림, 판정은 서버 hunter.js awaken_use): 고른 '쓰는 각성'마다 상황 버튼 왼쪽에 둥근 단추
## (그림자 걸음 · 마력 방패) — 누르면 Net.awaken_use, 다시 쓰기까지 남은 초를 단추 위에 덮어 보인다.
## 효과 (나 · 동료 모두, awaken_fx): 그림자 걸음 = 몸이 보랏빛으로 반쯤 비치고 걸음이 빨라진다 (내 것만 빠르기),
## 마력 방패 = 몸을 감싼 푸른 빛 껍질, 막을 때마다 번쩍 · 소리 (shield_blocked). 터치는 단추만 받는다.
## v0.28.8 배운 직업 액티브 기술 (회전 베기 · 그림자 일격 · 관통 사격 · 치유의 빛) 도 같은 둥근 단추로 각성 단추 위에 (Net.skill_use, 이름 sk_<id>).

const BTN: float = 110.0
const ICONS: Dictionary[String, String] = {"shadow": "影", "shield": "盾"}
const COLORS: Dictionary[String, Color] = {"shadow": Color("#7A4AD8"), "shield": Color("#3A9AF0")}

var player: Player = null
var _buttons: Dictionary[String, Button] = {}
var _cool: Dictionary[String, Label] = {}
## v0.28.9 다시 쓸 수 있게 되는 순간 단추가 반짝 (톡 커졌다 돌아오고 테두리 빛 · 작은 소리 · 진동).
var _cooling: Dictionary[String, bool] = {}
## 효과: 플레이어 id → {a: {"until": ms, "node": Node3D}}.
var _fx: Dictionary[int, Dictionary] = {}
static var _shell_mat: StandardMaterial3D = null


func _ready() -> void:
	name = "AwakenHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Net.hunter_changed.connect(_rebuild)
	Net.awaken_fx.connect(_on_fx)
	Net.shield_blocked.connect(_on_block)
	_rebuild()


func _rebuild() -> void:
	var want: Array[String] = []
	for a: String in Net.job_actives():
		want.append("sk_" + a)
	for e: Dictionary in GameData.hunter.awakens:
		var aid: String = str(e.get("id", ""))
		if bool(e.get("active", false)) and Net.has_awaken(aid):
			want.append(aid)
	var skills: int = 0
	for k: String in want:
		if k.begins_with("sk_"):
			skills += 1
	for aid: String in _buttons.keys():
		if not want.has(aid):
			_buttons[aid].queue_free()
			_buttons.erase(aid)
			_cool.erase(aid)
	for i: int in want.size():
		var aid: String = want[i]
		if not _buttons.has(aid):
			_buttons[aid] = _make_button(aid)
		var b: Button = _buttons[aid]
		b.offset_left = -410.0
		b.offset_right = -410.0 + BTN
		b.offset_top = -440.0 + float(i - skills) * (BTN + 14.0)
		b.offset_bottom = b.offset_top + BTN
		HudLayout.landscape_shift(b, -170.0)


func _make_button(aid: String) -> Button:
	var skill: String = aid.trim_prefix("sk_") if aid.begins_with("sk_") else ""
	var e: Dictionary = GameData.hunter.job_actives.get(skill, {}) if not skill.is_empty() else GameData.hunter.awaken(aid)
	var b: Button = Button.new()
	b.add_to_group(MultiTouch.GROUP)
	b.name = ("Skill_%s" % skill) if not skill.is_empty() else ("Awaken_%s" % aid)
	b.text = str(e.get("icon", "◆")) if not skill.is_empty() else ICONS.get(aid, "◆")
	b.tooltip_text = str(e.get("name", aid))
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.add_theme_font_size_override("font_size", 44)
	var col: Color = Color(str(e.get("color", "#888888"))) if not skill.is_empty() else COLORS.get(aid, Color("#888888"))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.45), 0.85)
	sb.border_color = col.lightened(0.3)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(int(BTN * 0.5))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var pressed: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	pressed.bg_color = col
	b.add_theme_stylebox_override("pressed", pressed)
	var dis: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color(0.12, 0.12, 0.14, 0.85)
	dis.border_color = Color(0.4, 0.4, 0.45)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_to_group(&"blocks_joystick")
	b.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		if skill.is_empty():
			Net.awaken_use(aid)
		else:
			Net.skill_use(skill))
	var cool: Label = Label.new()
	cool.name = "Cool"
	cool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cool.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cool.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cool.add_theme_font_size_override("font_size", 40)
	cool.add_theme_constant_override("outline_size", 8)
	cool.add_theme_color_override("font_outline_color", Color.BLACK)
	cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cool)
	add_child(b)
	_cool[aid] = cool
	return b


func _ready_flash(b: Button) -> void:
	Audio.play_ui("twinkle")
	Prefs.vibrate(25, 0.3)
	b.pivot_offset = b.size * 0.5
	var ring: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.border_color = Color("#FFE8A0")
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(int(BTN * 0.5) + 8)
	ring.add_theme_stylebox_override("panel", sb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.offset_left = -8.0
	ring.offset_top = -8.0
	ring.offset_right = 8.0
	ring.offset_bottom = 8.0
	ring.pivot_offset = (b.size + Vector2(16.0, 16.0)) * 0.5
	b.add_child(ring)
	var tw: Tween = b.create_tween().set_parallel(true)
	tw.tween_property(b, "scale", Vector2.ONE * 1.18, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector2.ONE * 1.35, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.5)
	tw.chain().tween_property(b, "scale", Vector2.ONE, 0.18)
	tw.chain().tween_callback(ring.queue_free)


## 단추 이름 (점검용): 이 각성 단추가 있는지.
func has_button(aid: String) -> bool:
	return _buttons.has(aid)


## 효과가 보이는지 (점검용).
func fx_active(player_id: int, aid: String) -> bool:
	return (_fx.get(player_id, {}) as Dictionary).has(aid)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for aid: String in _buttons:
		var left: int = (int(Net.skill_ready_at.get(aid.trim_prefix("sk_"), 0)) if aid.begins_with("sk_") else int(Net.awaken_ready_at.get(aid, 0))) - now
		_buttons[aid].disabled = left > 0 or Net.state != Net.State.ONLINE
		_cool[aid].text = "%d" % ceili(left / 1000.0) if left > 0 else ""
		if left > 0:
			_cooling[aid] = true
		elif bool(_cooling.get(aid, false)):
			_cooling[aid] = false
			_ready_flash(_buttons[aid])
	for pid: int in _fx.keys():
		var by: Dictionary = _fx[pid]
		for aid: String in by.keys():
			var f: Dictionary = by[aid]
			var node: Node3D = f.get("node")
			if now >= int(f["until"]) or node == null or not is_instance_valid(node):
				_end_fx(pid, aid)
				continue
			if aid == "shield" and f.has("shell"):
				var shell: MeshInstance3D = f["shell"]
				if is_instance_valid(shell):
					shell.scale = shell.scale.lerp(Vector3.ONE, 0.15)
					shell.rotation.y += 0.02


func _who(player_id: int) -> Node3D:
	if player_id == Net.my_id:
		return player
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator != null:
		for r: RemotePlayer in replicator.remote_nodes():
			if r.player_id == player_id:
				return r
	return null


func _on_fx(player_id: int, aid: String, ms: int) -> void:
	var node: Node3D = _who(player_id)
	if node == null:
		return
	_end_fx(player_id, aid)
	var f: Dictionary = {"until": Time.get_ticks_msec() + ms, "node": node}
	match aid:
		"shadow":
			# 몸이 보랏빛 그림자처럼 반쯤 비친다 · 보랏빛 연기.
			for m: MeshInstance3D in _meshes(node):
				m.transparency = 0.62
			Puff.burst(node.get_parent(), node.global_position + Vector3(0.0, 0.8, 0.0), Color(0.35, 0.2, 0.6, 0.85), 16, 1.2, 0.4, 0.12, 0.7)
			Audio.play_at("emote_down", node.global_position, -2.0, 0.6)
			if player_id == Net.my_id and player != null:
				player.speed_fx = 1.0 + float(GameData.hunter.awaken("shadow").get("speed", 0.2))
		"shield":
			# 몸을 감싼 푸른 빛 껍질.
			var shell: MeshInstance3D = MeshInstance3D.new()
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.85
			sphere.height = 1.9
			sphere.radial_segments = 24
			sphere.rings = 12
			shell.mesh = sphere
			shell.material_override = _shell()
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shell.position = Vector3(0.0, 0.95, 0.0)
			shell.scale = Vector3.ONE * 0.3
			node.add_child(shell)
			f["shell"] = shell
			Audio.play_at("twinkle", node.global_position, 0.0, 0.8)
	if not _fx.has(player_id):
		_fx[player_id] = {}
	(_fx[player_id] as Dictionary)[aid] = f


func _end_fx(player_id: int, aid: String) -> void:
	var by: Dictionary = _fx.get(player_id, {})
	if not by.has(aid):
		return
	var f: Dictionary = by[aid]
	by.erase(aid)
	var node: Node3D = f.get("node")
	match aid:
		"shadow":
			if node != null and is_instance_valid(node):
				for m: MeshInstance3D in _meshes(node):
					m.transparency = 0.0
			if player_id == Net.my_id and player != null:
				player.speed_fx = 1.0
		"shield":
			var shell: MeshInstance3D = f.get("shell")
			if shell != null and is_instance_valid(shell):
				shell.queue_free()


func _on_block(player_id: int, left: int) -> void:
	var f: Dictionary = (_fx.get(player_id, {}) as Dictionary).get("shield", {})
	var shell: MeshInstance3D = f.get("shell")
	if shell != null and is_instance_valid(shell):
		shell.scale = Vector3.ONE * 1.25
		Puff.burst(shell.get_parent().get_parent(), shell.global_position, Color(0.4, 0.75, 1.0, 0.9), 10, 1.0, 0.5, 0.1, 0.4)
		Audio.play_at("chop", shell.global_position, -4.0, 1.6)
		if left <= 0:
			_end_fx(player_id, "shield")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
		out.append_array(_meshes(c))
	return out


static func _shell() -> StandardMaterial3D:
	if _shell_mat == null:
		_shell_mat = StandardMaterial3D.new()
		_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shell_mat.albedo_color = Color(0.25, 0.6, 1.0, 0.28)
		_shell_mat.rim_enabled = false
	return _shell_mat
