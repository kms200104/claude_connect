class_name WaypointMarker
extends Node3D
## v0.28.1 웨이포인트 (지도에 찍은 자리, Waypoint): 마을에 하늘색 빛기둥 · 땅의 고리 · 머리 위 거리 글자,
## HUD 에 카메라 기준 방향 화살표 · "웨이포인트 Nm". 4m 안에 오면 "도착!" 하고 지운다. 판정과 상관없는 그림.

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud

const GLOW: Material = preload("res://assets/materials/lamp_glow.tres")
const COLOR: Color = Color("#22C3E6")
const BEAM_H: float = 26.0

var _beam: Node3D = null
var _ring: Node3D = null
var _label: Label3D = null
var _chip: HBoxContainer = null
var _arrow: Label = null
var _text: Label = null
var _seen: int = -1
var _time: float = 0.0
static var _material: ShaderMaterial = null


func _ready() -> void:
	name = "Waypoint"
	_build()
	visible = false
	_chip = HBoxContainer.new()
	_chip.name = "WaypointChip"
	_chip.position = Vector2(28.0, 544.0)
	_chip.add_theme_constant_override("separation", 10)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.visible = false
	_arrow = _hud_label("▲", 40)
	_arrow.custom_minimum_size = Vector2(44.0, 44.0)
	_arrow.pivot_offset = Vector2(22.0, 22.0)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip.add_child(_arrow)
	_text = _hud_label("웨이포인트", 28)
	_text.name = "WaypointText"
	_chip.add_child(_text)
	if hud != null:
		hud.add_child.call_deferred(_chip)


func _process(delta: float) -> void:
	_time += delta
	if Waypoint.version != _seen:
		_seen = Waypoint.version
		visible = Waypoint.is_set()
		if visible:
			var at: Vector3 = Vector3(Waypoint.at.x, 0.0, Waypoint.at.y)
			global_position = Vector3(at.x, _ground_y(at), at.z)
	var show: bool = Waypoint.is_set() and player != null and not Home.is_inside() and Net.state == Net.State.ONLINE
	_chip.visible = show
	if not show:
		return
	var to: Vector3 = Vector3(Waypoint.at.x, 0.0, Waypoint.at.y) - player.global_position
	to.y = 0.0
	var d: float = to.length()
	if d <= Waypoint.ARRIVE:
		Waypoint.clear()
		if toast_hud != null:
			toast_hud.show_toast("웨이포인트에 도착했어요", true)
		Audio.play_sfx("twinkle", -6.0)
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_arrow.rotation = atan2(to.dot(Vector3(-fwd.z, 0.0, fwd.x)), to.dot(fwd))
	_text.text = "웨이포인트 %dm" % roundi(d)
	_label.text = "%dm" % roundi(d)
	# 빛기둥은 천천히 숨쉬고, 땅 고리는 돈다.
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.4)
	_beam.scale = Vector3(0.8 + pulse * 0.4, 1.0, 0.8 + pulse * 0.4)
	_ring.rotation.y += delta * 0.8


func _build() -> void:
	_beam = Node3D.new()
	_beam.name = "Beam"
	add_child(_beam)
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_rod(st, Vector3.ZERO, Vector3(0.0, BEAM_H, 0.0), 0.18, 0.04, Color.WHITE, 8)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.mesh = ClayMesh.commit(st)
	beam.material_override = _glow()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(beam)
	_ring = Node3D.new()
	_ring.name = "Ring"
	add_child(_ring)
	var b: BoxBatch = BoxBatch.new()
	for i: int in 12:
		var a: float = TAU * float(i) / 12.0
		b.box(Vector3(cos(a) * 1.4, 0.04, sin(a) * 1.4), Vector3(0.5, 0.03, 0.14), Color.WHITE, Basis(Vector3.UP, -a + PI * 0.5))
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.mesh = b.commit()
	ring.material_override = _glow()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(ring)
	_label = Label3D.new()
	_label.name = "Distance"
	_label.font_size = 56
	_label.pixel_size = 0.01
	_label.outline_size = 12
	_label.modulate = COLOR.lightened(0.4)
	_label.outline_modulate = Color("#0A2A34")
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, 3.2, 0.0)
	add_child(_label)


static func _glow() -> ShaderMaterial:
	if _material == null:
		_material = (GLOW as ShaderMaterial).duplicate() as ShaderMaterial
		_material.set_shader_parameter("albedo", COLOR.lightened(0.3))
		_material.set_shader_parameter("emission", COLOR)
		_material.set_shader_parameter("emission_energy", 2.4)
	return _material


func _hud_label(text: String, size: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color("#0A2A34"))
	l.add_theme_color_override("font_color", COLOR.lightened(0.25))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 6.0, at.z), Vector3(at.x, -3.0, at.z))
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() and (hit["position"] as Vector3).y < 0.6 else 0.0
