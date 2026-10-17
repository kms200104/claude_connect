class_name JobLook
extends RefCounted
## v0.28.9 직업 겉모습: 목에 직업 색 스카프 (2차 전직이면 금빛 테두리) · 등에 직업 휘장 (둥근 판 + 직업 글자) · 다른 사람 이름표 위에 '旋 전사' 띠.
## 그림만 — 직업은 서버 (hunter.job · adv, 다른 사람은 players 의 hj · ha / hunter_job). HunterController 가 나 · 동료에게 붙인다.

## 스카프 · 휘장 자리 (리그 Neck · Upper 기준, 모형 정면 -Z → 등은 +Z).
const SCARF_Y: float = 0.02
const SCARF_RING: float = 0.17
const SCARF_TUBE: float = 0.055
const EMBLEM_AT: Vector3 = Vector3(0.0, -0.26, 0.255)
const GOLD: Color = Color("#E8B830")
const MATERIAL: Material = preload("res://assets/materials/foliage.tres")

static var _scarves: Dictionary[String, ArrayMesh] = {}


## 직업마다 등 휘장 글자 (그 직업 액티브 기술 그림).
static func icon_of(job_id: String) -> String:
	for n: Variant in GameData.hunter.job(job_id).get("tree", []):
		var a: String = str((n as Dictionary).get("active", ""))
		if not a.is_empty():
			return str((GameData.hunter.job_actives.get(a, {}) as Dictionary).get("icon", "◆"))
	return "◆"


static func color_of(job_id: String, adv: bool) -> Color:
	var def: Dictionary = GameData.hunter.job(job_id)
	var key: Dictionary = def.get("advance", {}) if adv and def.has("advance") else def
	return Color(str(key.get("color", def.get("color", "#FFFFFF"))))


static func title_of(job_id: String, adv: bool) -> String:
	var def: Dictionary = GameData.hunter.job(job_id)
	return str((def.get("advance", {}) as Dictionary).get("name", def.get("name", ""))) if adv else str(def.get("name", ""))


static func _scarf_mesh(c: Color, adv: bool) -> ArrayMesh:
	var key: String = "%s%s" % [c.to_html(false), "a" if adv else ""]
	if not _scarves.has(key):
		var st: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_torus(st, Vector3.ZERO, SCARF_RING, SCARF_TUBE, c, 20, 8)
		# 등 뒤로 늘어진 두 자락.
		ClayMesh.add_rounded_box(st, Vector3(0.05, -0.1, SCARF_RING + 0.02), Vector3(0.06, 0.16, 0.025), 0.5, c.darkened(0.08), Basis(Vector3.RIGHT, 0.25) * Basis(Vector3.FORWARD, 0.15))
		ClayMesh.add_rounded_box(st, Vector3(-0.04, -0.08, SCARF_RING + 0.015), Vector3(0.055, 0.13, 0.025), 0.5, c.darkened(0.15), Basis(Vector3.RIGHT, 0.3) * Basis(Vector3.FORWARD, -0.2))
		if adv:
			ClayMesh.add_torus(st, Vector3(0.0, -SCARF_TUBE * 0.7, 0.0), SCARF_RING + 0.012, SCARF_TUBE * 0.35, GOLD, 20, 6)
		_scarves[key] = ClayMesh.commit(st)
	return _scarves[key]


## who 의 리그에 직업 겉모습을 입힌다 (job 이 비면 벗긴다). name_label 이 있으면 (동료) 그 위에 직업 띠.
static func apply(who: Node3D, rig: CharacterRig, job_id: String, adv: bool, name_label: Label3D = null) -> void:
	if rig == null or rig.neck == null or rig.upper == null:
		return
	var scarf: MeshInstance3D = rig.neck.get_node_or_null("JobScarf") as MeshInstance3D
	var emblem: Node3D = rig.upper.get_node_or_null("JobEmblem") as Node3D
	var badge: Label3D = who.get_node_or_null("JobBadge") as Label3D if who != null else null
	if job_id.is_empty() or GameData.hunter.job(job_id).is_empty():
		for n: Node in [scarf, emblem, badge]:
			if n != null:
				n.queue_free()
		return
	var c: Color = color_of(job_id, adv)
	if scarf == null:
		scarf = MeshInstance3D.new()
		scarf.name = "JobScarf"
		scarf.material_override = MATERIAL
		scarf.position = Vector3(0.0, SCARF_Y, 0.0)
		rig.neck.add_child(scarf)
	scarf.mesh = _scarf_mesh(c, adv)
	if emblem != null:
		emblem.queue_free()
	emblem = Node3D.new()
	emblem.name = "JobEmblem"
	emblem.position = EMBLEM_AT
	rig.upper.add_child(emblem)
	var plate: MeshInstance3D = MeshInstance3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.085, 0.085, 0.018), c.darkened(0.35), 16, 6)
	ClayMesh.add_torus(st, Vector3(0.0, 0.0, 0.008), 0.085, 0.012, GOLD if adv else c.lightened(0.35), 20, 5, Basis(Vector3.RIGHT, PI * 0.5))
	plate.mesh = ClayMesh.commit(st)
	plate.material_override = MATERIAL
	emblem.add_child(plate)
	var glyph: Label3D = Label3D.new()
	glyph.text = icon_of(job_id)
	glyph.font_size = 64
	glyph.pixel_size = 0.0018
	glyph.modulate = Color.WHITE
	glyph.outline_size = 0
	glyph.position = Vector3(0.0, 0.0, 0.02)
	glyph.double_sided = false
	emblem.add_child(glyph)
	if name_label == null:
		return
	if badge == null:
		badge = Label3D.new()
		badge.name = "JobBadge"
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.no_depth_test = true
		badge.pixel_size = 0.0065
		badge.font_size = 48
		badge.outline_size = 12
		badge.outline_modulate = Color("#1A1410")
		who.add_child(badge)
	badge.position = name_label.position + Vector3(0.0, 0.34, 0.0)
	badge.text = "%s %s" % [icon_of(job_id), title_of(job_id, adv)]
	badge.modulate = c.lightened(0.25) if adv else c.lightened(0.1)
