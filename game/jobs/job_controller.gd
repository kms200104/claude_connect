class_name JobController
extends Node
## 일거리 (v0.12): 배달 알바의 화면. 휴대폰 '일거리' 앱에서 받으면 (Economy.take_job)
## 받을 곳 → 주민 집 차례로 땅에 빛기둥 표식을 세우고, 화면 위쪽 칩에 남은 거리·시간을 보여 준다.
## 가까이 가면 상황 버튼("물건 받기" · "배달하기")이 뜬다. 판정(거리 · 삯 · 팁 · 같이 배달)은 서버가 한다.
## v0.13.7: 캐릭터 발밑 둘레에 가야 할 쪽(받을 곳 · 집)을 가리키는 화살표, 연속 팁(서버 jobs.json streak) 표시.

@export var player: Player
## 칩을 붙일 곳.
@export var hud: CanvasLayer
## 결과 문구 (낚시 HUD 의 토스트).
@export var toast_hud: FishingHud

@export_group("Feel")
## 서버 판정 거리보다 이만큼 안쪽에서만 버튼을 보여 준다.
@export_range(0.0, 1.0, 0.05, "suffix:m") var safety_margin: float = 0.4
## 표식 빛기둥 높이.
@export_range(1.0, 12.0, 0.5, "suffix:m") var beacon_height: float = 6.0
## 방향 화살표: 캐릭터에서 이만큼 떨어진 둘레에 놓고, 목적지가 이보다 가까우면 감춘다 (빛기둥이 보이니까).
@export_range(0.5, 4.0, 0.05, "suffix:m") var arrow_radius: float = 1.7
@export_range(1.0, 15.0, 0.5, "suffix:m") var arrow_hide_within: float = 5.0

const TARGET_PICK: String = "job_pick"
const TARGET_DROP: String = "job_drop"
const PICK_COLOR: Color = Color("#F2B33D")
const DROP_COLOR: Color = Color("#4CC38A")
## 떠 있는 물건 모형 (캐릭터 손에 든 도구와 같은 버텍스 컬러 머티리얼).
const BEACON_MATERIAL: Material = preload("res://assets/materials/foliage.tres")

var _beacon: Node3D = null
var _beacon_ring: MeshInstance3D = null
var _beacon_pillar: MeshInstance3D = null
var _beacon_box: MeshInstance3D = null
var _chip: Button = null
var _arrow: Node3D = null
var _arrow_material: StandardMaterial3D = null
var _confirm_quit: bool = false
var _t: float = 0.0


func _ready() -> void:
	_build_beacon()
	_build_arrow()
	_build_chip()
	Economy.job_changed.connect(_refresh)
	Economy.job_done.connect(_on_done)
	Economy.failed.connect(_on_failed)
	Net.state_changed.connect(func(_s: int) -> void:
		if Net.state == Net.State.ONLINE:
			Economy.ask_jobs()
		_refresh())
	if Net.state == Net.State.ONLINE:
		Economy.ask_jobs()
	_refresh()


## 상황 버튼 대상 (받을 곳·집 곁이면 TARGET_*, 아니면 빈 문자열).
func pick_target(position: Vector3) -> String:
	var j: Dictionary = Economy.job()
	if j.is_empty() or Home.is_inside():
		return ""
	var rules: JobRules = GameData.jobs
	if str(j.get("stage", "")) == "pickup":
		if _flat_distance(position, _point(j.get("from", {}))) <= rules.range - safety_margin:
			return TARGET_PICK
	elif _flat_distance(position, _point(j.get("to", {}))) <= rules.house_range - safety_margin:
		return TARGET_DROP
	return ""


func target_label(target: String) -> String:
	return "물건 받기" if target == TARGET_PICK else "배달하기"


func activate(target: String) -> void:
	if target == TARGET_PICK:
		player.play_plant()
		Economy.pick_job()
	else:
		var to: Vector3 = _point(Economy.job().get("to", {}))
		player.look_toward(to - player.global_position)
		Economy.drop_job()


## 지금 칩에 적힌 글 (테스트용).
func chip_text() -> String:
	return _chip.text if _chip != null and _chip.visible else ""


func _process(delta: float) -> void:
	var j: Dictionary = Economy.job()
	if j.is_empty() or Net.state != Net.State.ONLINE:
		return
	_t += delta
	var carry: bool = str(j.get("stage", "")) == "carry"
	var at: Vector3 = _point(j.get("to" if carry else "from", {}))
	_beacon.global_position = at
	_beacon_box.position.y = 2.4 + sin(_t * 2.4) * 0.25
	_beacon_box.rotation.y = _t * 1.2
	var pulse: float = 1.0 + sin(_t * 3.0) * 0.08
	_beacon_ring.scale = Vector3(pulse, 1.0, pulse)
	_beacon.visible = not Home.is_inside()
	_place_arrow(at)
	if not _confirm_quit:
		_chip.text = _chip_line(j, at)


func _chip_line(j: Dictionary, at: Vector3) -> String:
	var dist: int = roundi(_flat_distance(player.global_position, at)) if player != null else 0
	if str(j.get("stage", "")) != "carry":
		return "📦 %s · %s 에서 받기 · %dm" % [str(j.get("name", "")), str(j.get("from", {}).get("name", "")), dist]
	var left_s: int = maxi(0, ceili((Economy.job_due_ms - Time.get_ticks_msec()) / 1000.0))
	var who: String = "%s네 집" % GameData.npc_name(str(j.get("to", {}).get("npc", "")))
	var streak: int = int(Economy.jobs.get("streak", 0))
	if left_s > 0 and streak > 0:
		return "📦 %s · %dm · 팁까지 %d:%02d · 🔥연속 %d" % [who, dist, left_s / 60, left_s % 60, streak]
	if left_s > 0:
		return "📦 %s · %dm · 팁까지 %d:%02d" % [who, dist, left_s / 60, left_s % 60]
	return "📦 %s · %dm · (팁 시간 지남)" % [who, dist]


func _refresh() -> void:
	var j: Dictionary = Economy.job()
	var active: bool = not j.is_empty() and Net.state == Net.State.ONLINE
	_confirm_quit = false
	_chip.visible = active
	_beacon.visible = active
	_arrow.visible = active
	_wear_uniform(active)
	if not active:
		return
	var carry: bool = str(j.get("stage", "")) == "carry"
	var color: Color = DROP_COLOR if carry else PICK_COLOR
	(_beacon_pillar.material_override as StandardMaterial3D).albedo_color = Color(color, 0.32)
	(_beacon_ring.material_override as StandardMaterial3D).albedo_color = Color(color, 0.75)
	_beacon_box.mesh = CharacterModel.carry_prop(str(j.get("item", "parcel")))
	_beacon_box.visible = not carry
	_arrow_material.albedo_color = color
	_chip.add_theme_color_override("font_color", color.darkened(0.45))


## 배달하는 동안은 파란 헬멧(쓰던 모자 자리)과 "배달의 솔" 가방 (v0.15). 받을 때 · 끝낼 때 탈의소에서 갈아입는다.
func _wear_uniform(on: bool) -> void:
	if player == null or player.rig == null:
		return
	var rig: CharacterRig = player.rig
	# 갈아입는 중이면 커튼이 닫힐 때 그때의 복장으로 입힌다.
	if OutfitBooth.is_pending(rig) or rig.is_uniformed() == on:
		return
	# 킥보드를 타고 있으면 탈의소 없이 뿅 (짜잔 자세가 발판 위에서 어긋난다).
	if player.is_inside_tree() and player.body.visible and not player.is_riding():
		OutfitBooth.play(rig, OutfitBooth.apply_local.bind(rig), player)
	else:
		rig.set_uniform(on)


func _on_done(r: Dictionary) -> void:
	Audio.play_sfx("coin", -4.0)
	if bool(r.get("helper", false)):
		toast_hud.show_toast("%s 님 배달을 같이 했어요! 같이 보너스 +%s" % [GameData.player_name(int(r.get("by", 0))), Money.short(int(r.get("bonus", 0)))], true)
		return
	var parts: PackedStringArray = ["삯 %s" % Money.short(int(r.get("pay", 0)))]
	if int(r.get("tip", 0)) > 0:
		parts.append("빨리 와서 팁 %s" % Money.short(int(r.get("tip", 0))))
	if int(r.get("bonus", 0)) > 0:
		parts.append("같이 배달 %s" % Money.short(int(r.get("bonus", 0))))
	if int(r.get("streakBonus", 0)) > 0:
		parts.append("🔥연속 팁 %d번 %s" % [int(r.get("streak", 0)), Money.short(int(r.get("streakBonus", 0)))])
	elif bool(r.get("onTime", true)) == false:
		parts.append("시간이 지나 연속 팁이 끊겼어요")
	toast_hud.show_toast("%s 님께 배달 완료! +%s (%s)" % [GameData.npc_name(str(r.get("npc", ""))), Money.short(int(r.get("total", 0))), " · ".join(parts)], true)
	var actor: NpcActor = NpcActor.find(get_tree(), str(r.get("npc", "")))
	if actor != null:
		actor.play_emote("happy")


func _on_failed(kind: String, code: String) -> void:
	if not kind.begins_with("job_"):
		return
	var text: String = {
		NetProtocol.ERR_JOB_BUSY: "하던 배달을 먼저 끝내요.",
		NetProtocol.ERR_JOB_LIMIT: "오늘 일거리는 다 했어요. 내일 또 와요!",
		NetProtocol.ERR_NOT_AT_JOB: "조금 더 가까이 가요.",
		NetProtocol.ERR_NO_JOB: "받은 배달이 없어요.",
	}.get(code, "")
	if not text.is_empty():
		toast_hud.show_toast(text, false)


func _on_chip_pressed() -> void:
	if _confirm_quit:
		Economy.quit_job()
		toast_hud.show_toast("배달을 그만뒀어요.", false)
		return
	_confirm_quit = true
	_chip.text = "📦 배달을 그만둘까요? (한 번 더 누르기)"
	get_tree().create_timer(2.5).timeout.connect(func() -> void: _confirm_quit = false)


func _build_chip() -> void:
	_chip = Button.new()
	_chip.name = "JobChip"
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.position = Vector2(24, 352)
	_chip.custom_minimum_size = Vector2(0, 72)
	_chip.add_theme_font_size_override("font_size", 28)
	for state: String in ["normal", "hover", "pressed"]:
		_chip.add_theme_stylebox_override(state, EventHud._box(Color(1.0, 0.97, 0.88, 0.95), Color(0.55, 0.42, 0.3), 36, 4))
	_chip.pressed.connect(_on_chip_pressed)
	_chip.add_to_group(&"blocks_joystick")
	_chip.visible = false
	if hud != null:
		hud.add_child.call_deferred(_chip)


## 화살표: 캐릭터 둘레(arrow_radius)에서 목적지 쪽을 가리킨다. 목적지가 가까우면(빛기둥이 보이면) · 집 안이면 감춘다.
func _place_arrow(at: Vector3) -> void:
	if player == null:
		return
	var from: Vector3 = player.global_position
	var flat: Vector2 = Vector2(at.x - from.x, at.z - from.z)
	var show: bool = flat.length() > arrow_hide_within and not Home.is_inside()
	_arrow.visible = show
	if not show:
		return
	var dir: Vector2 = flat.normalized()
	# 앞으로 살짝 밀었다 당기며 (가는 쪽을 알기 쉽게).
	var push: float = arrow_radius + 0.18 * sin(_t * 4.0)
	_arrow.global_position = Vector3(from.x + dir.x * push, from.y + 0.25, from.z + dir.y * push)
	# 화살표 모형의 앞은 -Z.
	_arrow.rotation = Vector3(0.0, atan2(-dir.x, -dir.y), 0.0)


## 납작한 화살표 (머리 삼각형 + 몸통), 위아래 두 장: 아래는 짙은 테두리라 풀밭 · 모래 어디서나 보인다.
func _build_arrow() -> void:
	_arrow = Node3D.new()
	_arrow.name = "JobArrow"
	add_child(_arrow)
	_arrow.top_level = true
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_material.albedo_color = PICK_COLOR
	var rim: StandardMaterial3D = StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.albedo_color = Color(0.25, 0.18, 0.1)
	for layer: Array in [[1.25, rim, 0.0], [1.0, _arrow_material, 0.02]]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = _arrow_mesh(float(layer[0]))
		mi.material_override = layer[1]
		mi.position.y = float(layer[2])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arrow.add_child(mi)
	_arrow.visible = false


static func _arrow_mesh(scale: float) -> ArrayMesh:
	# 앞(-Z)을 가리키는 화살표 윤곽 (반시계, 위에서 볼 때).
	var outline: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -0.55), Vector2(0.42, -0.05), Vector2(0.16, -0.05), Vector2(0.16, 0.4),
		Vector2(-0.16, 0.4), Vector2(-0.16, -0.05), Vector2(-0.42, -0.05),
	])
	var center: Vector2 = Vector2(0.0, -0.05)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in tris.size():
		var p: Vector2 = center + (outline[tris[i]] - center) * scale
		st.add_vertex(Vector3(p.x, 0.0, p.y))
	return st.commit()


func _build_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "JobBeacon"
	add_child(_beacon)
	_beacon.top_level = true
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var pillar: CylinderMesh = CylinderMesh.new()
	pillar.top_radius = 0.35
	pillar.bottom_radius = 0.6
	pillar.height = beacon_height
	pillar.radial_segments = 12
	pillar.cap_top = false
	pillar.cap_bottom = false
	_beacon_pillar = MeshInstance3D.new()
	_beacon_pillar.mesh = pillar
	_beacon_pillar.material_override = glow
	_beacon_pillar.position.y = beacon_height * 0.5
	_beacon_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.add_child(_beacon_pillar)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 1.1
	ring.outer_radius = 1.35
	ring.rings = 24
	ring.ring_segments = 6
	_beacon_ring = MeshInstance3D.new()
	_beacon_ring.mesh = ring
	_beacon_ring.material_override = glow.duplicate()
	_beacon_ring.position.y = 0.08
	_beacon_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.add_child(_beacon_ring)
	_beacon_box = MeshInstance3D.new()
	_beacon_box.scale = Vector3.ONE * 2.2
	_beacon_box.material_override = BEACON_MATERIAL
	_beacon.add_child(_beacon_box)
	_beacon.visible = false


func _point(d: Variant) -> Vector3:
	if not d is Dictionary:
		return Vector3.ZERO
	var dict: Dictionary = d
	return Vector3(float(dict.get("x", 0.0)), 0.0, float(dict.get("z", 0.0)))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
