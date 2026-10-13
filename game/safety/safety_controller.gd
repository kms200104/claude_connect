class_name SafetyController
extends Node
## 폰다운 기능 (v0.20): 솔걸음 만보기 · 재난문자 · 민방위 훈련을 마을에 잇는다 (EconomyController 가 붙인다).
## - 만보기(Pedometer): 솔걸음 앱을 받아야 센다. 목표를 넘겨 서버가 솔을 주면 알림.
## - 재난문자(alert): 화면 위 재난문자 창 + 소리 · 진동, 안전알림 앱 기록(AlertLog). 늦게 들어와 받은 오늘 문자는 기록만.
## - 민방위 훈련(drill): 사이렌, 화면 위 안내 띠(대피소까지 거리 · 방향 · 남은 시간), 대피소에 빛기둥.
##   대피소에 들어가면 서버가 보상(drill_done). 대피소 표지판(초록)은 늘 서 있다.

const SIREN_SECONDS: float = 40.0
const SIGN_GREEN: Color = Color("#1E8E4E")

var hud: CanvasLayer = null
var player: Node3D = null
var phone: PhoneWindow = null
var toast: FishingHud = null
var pedometer: Pedometer = null

var _banner: Label = null
var _banner_box: PanelContainer = null
## 지금 훈련 안내를 띄울 차례인지 (훈련 중 · 아직 대피 전).
var _guiding: bool = false
var _siren: AudioStreamPlayer = null
var _siren_left: float = 0.0
var _beam: MeshInstance3D = null
var _sign: Label3D = null
var _queue: Array[Dictionary] = []
var _current: DisasterAlert = null


func _ready() -> void:
	pedometer = Pedometer.new()
	pedometer.name = "Pedometer"
	add_child(pedometer)
	_refresh_installed()
	if phone != null:
		phone.app_installed.connect(func(_k: String, _on: bool) -> void: _refresh_installed())
	Net.alert_received.connect(_on_alert)
	Net.drill_changed.connect(_on_drill)
	Net.drill_finished.connect(_on_drill_done)
	Net.steps_updated.connect(_on_steps)
	_siren = AudioStreamPlayer.new()
	_siren.bus = "Sfx"
	_siren.stream = AlertSounds.get_stream("siren")
	_siren.volume_db = -8.0
	add_child(_siren)
	_banner_box = PanelContainer.new()
	_banner_box.name = "DrillBannerBox"
	_banner_box.add_theme_stylebox_override("panel", EventHud._box(Color(0.78, 0.12, 0.1, 0.88), Color(1, 1, 1, 0.9), 26, 3, 14))
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.visible = false
	HudLayout.center_top(_banner_box, 1000.0, 300.0)
	_banner = Label.new()
	_banner.name = "DrillBanner"
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.add_theme_color_override("font_color", Color.WHITE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.add_child(_banner)
	if hud != null:
		hud.add_child.call_deferred(_banner_box)
	_place_shelter.call_deferred()
	if not Net.drill.is_empty():
		_on_drill(Net.drill)


func _refresh_installed() -> void:
	pedometer.enabled = phone == null or phone.is_installed("steps")


## 대피소 표지판 (늘) · 훈련 때 빛기둥.
func _place_shelter() -> void:
	var world: Node = player.get_parent() if player != null else null
	if world == null:
		return
	var at: Vector2 = GameData.safety.shelter
	_sign = Label3D.new()
	_sign.name = "ShelterSign"
	_sign.text = "민방위 대피소"
	_sign.font_size = 56
	_sign.pixel_size = 0.006
	_sign.modulate = SIGN_GREEN
	_sign.outline_modulate = Color.WHITE
	_sign.outline_size = 14
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.no_depth_test = false
	_sign.position = Vector3(at.x, 4.2, at.y)
	world.add_child(_sign)
	_beam = MeshInstance3D.new()
	_beam.name = "ShelterBeam"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 30.0
	cyl.radial_segments = 24
	cyl.rings = 1
	_beam.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.35, 1.0, 0.55, 0.28)
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(at.x, 15.0, at.y)
	_beam.visible = not Net.drill.is_empty()
	world.add_child(_beam)


func _on_alert(alert: Dictionary) -> void:
	var fresh: bool = AlertLog.add(alert)
	if not fresh or bool(alert.get("late", false)):
		return
	_queue.append(alert)
	_show_next()


## 재난문자는 한 장씩 (진짜 휴대폰처럼 확인하면 다음 문자).
func _show_next() -> void:
	if hud == null or _queue.is_empty() or (_current != null and is_instance_valid(_current) and not _current.is_queued_for_deletion()):
		return
	_current = DisasterAlert.pop(hud, _queue.pop_front())
	_current.tree_exited.connect(func() -> void:
		_current = null
		_show_next.call_deferred())


func _on_drill(info: Dictionary) -> void:
	var on: bool = bool(info.get("on", false))
	if _beam != null:
		_beam.visible = on
	_guiding = on and not bool(info.get("done", false))
	if on and not bool(info.get("done", false)):
		_siren_left = SIREN_SECONDS
		_siren.volume_db = -8.0
		_siren.play()
	else:
		_siren.stop()


func _on_drill_done(info: Dictionary) -> void:
	_guiding = false
	_siren.stop()
	if toast != null:
		toast.show_toast("대피 완료! 민방위 훈련에 참여했어요 (+%s)" % Money.short(int(info.get("reward", 0))), true)
	Prefs.vibrate(200, 0.6)
	Audio.play_sfx("quest_done", -4.0)


func _on_steps(info: Dictionary) -> void:
	var reward: int = int(info.get("reward", 0))
	if reward <= 0 or toast == null:
		return
	toast.show_toast("솔걸음 목표 달성! 오늘 %s걸음 (+%s)" % [_comma(int(info.get("today", 0))), Money.short(reward)], true)
	Audio.play_sfx("coin", -4.0)


func _process(delta: float) -> void:
	if _siren_left > 0.0:
		_siren_left -= delta
		if _siren_left < 4.0:
			_siren.volume_db = lerpf(-40.0, -8.0, maxf(_siren_left, 0.0) / 4.0)
		if _siren_left <= 0.0:
			_siren.stop()
	# 휴대폰을 보는 동안은 가리지 않게 숨긴다.
	_banner_box.visible = _guiding and player != null and (phone == null or not phone.visible)
	if _banner_box.visible:
		_banner.text = banner_text()


## 훈련 안내 한 줄: "⚠ 민방위 훈련 중 · 대피소까지 85m ↗ · 남은 시간 12:30".
func banner_text() -> String:
	var at: Vector2 = GameData.safety.shelter
	var to: Vector2 = at - Vector2(player.global_position.x, player.global_position.z)
	var arrow: String = ""
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and to.length() > 1.0:
		var fwd: Vector3 = -cam.global_transform.basis.z
		var right: Vector3 = cam.global_transform.basis.x
		var a: float = atan2(to.dot(Vector2(right.x, right.z)), to.dot(Vector2(fwd.x, fwd.z).normalized()))
		var arrows: PackedStringArray = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
		arrow = arrows[posmod(roundi(a / (TAU / 8.0)), 8)]
	var left_ms: float = float(Net.drill.get("until", 0)) - Net.game_ms()
	var left: String = "" if left_ms <= 0.0 else " · 남은 시간 %d:%02d" % [int(left_ms / 60000.0), int(fmod(left_ms / 1000.0, 60.0))]
	return "⚠ 민방위 훈련 중 · %s까지 %dm %s%s" % [GameData.safety.shelter_name, roundi(maxf(0.0, to.length() - GameData.safety.shelter_radius)), arrow, left]


static func _comma(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
