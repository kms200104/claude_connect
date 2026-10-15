class_name AwakenHud
extends Control
## v0.28.5 헌터 각성 (HUD · 그림, 판정은 서버 hunter.js awaken_use): 고른 '쓰는 각성'마다 상황 버튼 왼쪽에 둥근 단추
## (그림자 걸음 · 마력 방패) — 누르면 Net.awaken_use, 다시 쓰기까지 남은 초를 단추 위에 덮어 보인다.
## 효과 (나 · 동료 모두, awaken_fx): 그림자 걸음 = 몸이 보랏빛으로 반쯤 비치고 걸음이 빨라진다 (내 것만 빠르기),
## 마력 방패 = 몸을 감싼 푸른 빛 껍질, 막을 때마다 번쩍 · 소리 (shield_blocked). 터치는 단추만 받는다.

const BTN: float = 110.0
const ICONS: Dictionary[String, String] = {"shadow": "影", "shield": "盾"}
const COLORS: Dictionary[String, Color] = {"shadow": Color("#7A4AD8"), "shield": Color("#3A9AF0")}

var player: Player = null
var _buttons: Dictionary[String, Button] = {}
var _cool: Dictionary[String, Label] = {}
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
	for e: Dictionary in GameData.hunter.awakens:
		var aid: String = str(e.get("id", ""))
		if bool(e.get("active", false)) and Net.has_awaken(aid):
			want.append(aid)
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
		b.offset_top = -440.0 + float(i) * (BTN + 14.0)
		b.offset_bottom = b.offset_top + BTN
		HudLayout.landscape_shift(b, -170.0)


func _make_button(aid: String) -> Button:
	var e: Dictionary = GameData.hunter.awaken(aid)
	var b: Button = Button.new()
	b.name = "Awaken_%s" % aid
	b.text = ICONS.get(aid, "◆")
	b.tooltip_text = str(e.get("name", aid))
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.add_theme_font_size_override("font_size", 44)
	var col: Color = COLORS.get(aid, Color("#888888"))
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
		Net.awaken_use(aid))
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


## 단추 이름 (점검용): 이 각성 단추가 있는지.
func has_button(aid: String) -> bool:
	return _buttons.has(aid)


## 효과가 보이는지 (점검용).
func fx_active(player_id: int, aid: String) -> bool:
	return (_fx.get(player_id, {}) as Dictionary).has(aid)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for aid: String in _buttons:
		var left: int = int(Net.awaken_ready_at.get(aid, 0)) - now
		_buttons[aid].disabled = left > 0 or Net.state != Net.State.ONLINE
		_cool[aid].text = "%d" % ceili(left / 1000.0) if left > 0 else ""
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
