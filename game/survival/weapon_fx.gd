class_name WeaponFx
extends RefCounted
## v0.28.8 무기마다 다른 휘두르기 · 맞히기 (소리 · 궤적 · 맞은 자리 효과 · 글자 · 흔들림 · 멈칫). 그림만 — 피해 · 판정은 서버 (survival.js).
## swing(): 휘두르는 사람 앞에 궤적 띠 (Fx.slash, 쇠창은 찌르는 빛줄기) + 바람 소리. hit(): CreatureField 가 creature_hit 의 w (무기 · 기술 id) 로 부른다.

class Style:
	## 휘두르기 소리 · 맞히기 소리 · 떠오르는 글자.
	var swing_sfx: String = "swing_light"
	var hit_sfx: String = "hit_fist"
	var word: String = "퍽!"
	## 맞은 자리 효과 갈래: fist · blunt · metal · nails · blade · stab · fire · bolt · light · whirl · pierce.
	var kind: String = "fist"
	## 궤적 색 · 휘는 각 (도) · 반지름 (m) · 굵기 · 기울기 (위에서 내려치면 +) · 길이 (초).
	var color: Color = Color(1, 1, 1)
	var sweep: float = 120.0
	var radius: float = 1.1
	var width: float = 0.3
	var tilt: float = 0.0
	var dur: float = 0.18
	## 화면 흔들림 · 맞은 크리처가 멈칫하는 시간 (초) · 핏방울 양.
	var shake: float = 0.05
	var hitstop: float = 0.04
	var blood: float = 0.6


static var _styles: Dictionary[String, Style] = {}


static func _make(swing: String, hit: String, word: String, kind: String, color: Color, sweep: float, radius: float, width: float, tilt: float, dur: float, shake: float, hitstop: float, blood: float) -> Style:
	var s: Style = Style.new()
	s.swing_sfx = swing
	s.hit_sfx = hit
	s.word = word
	s.kind = kind
	s.color = color
	s.sweep = sweep
	s.radius = radius
	s.width = width
	s.tilt = tilt
	s.dur = dur
	s.shake = shake
	s.hitstop = hitstop
	s.blood = blood
	return s


static func style(weapon_id: String) -> Style:
	if _styles.is_empty():
		_styles["hands"] = _make("swing_light", "hit_fist", "퍽!", "fist", Color("#F0E6D2"), 90.0, 0.9, 0.22, 0.0, 0.14, 0.04, 0.03, 0.4)
		_styles["flashlight"] = _make("swing_light", "hit_fist", "툭!", "light", Color("#CFE6FF"), 100.0, 1.0, 0.22, 0.0, 0.15, 0.04, 0.03, 0.4)
		_styles["axe"] = _make("swing_blade", "hit_blade", "서걱!", "blade", Color("#E8EEF2"), 130.0, 1.25, 0.32, 0.35, 0.18, 0.08, 0.06, 1.0)
		_styles["shovel"] = _make("swing_heavy", "hit_metal", "땡!", "metal", Color("#D8D2C4"), 130.0, 1.3, 0.34, 0.2, 0.2, 0.09, 0.06, 0.7)
		_styles["wooden_club"] = _make("swing_heavy", "hit_wood", "빡!", "blunt", Color("#E8C890"), 140.0, 1.3, 0.36, 0.25, 0.2, 0.1, 0.07, 0.8)
		_styles["pipe_spear"] = _make("swing_thrust", "hit_stab", "푹!", "stab", Color("#E6F0FF"), 0.0, 2.5, 0.22, 0.0, 0.14, 0.07, 0.05, 1.0)
		_styles["iron_pipe"] = _make("swing_light", "hit_metal", "깡!", "metal", Color("#D6E2EE"), 130.0, 1.35, 0.3, 0.1, 0.16, 0.08, 0.05, 0.7)
		_styles["nail_bat"] = _make("swing_heavy", "hit_nails", "콰직!", "nails", Color("#F2C8A0"), 150.0, 1.4, 0.4, 0.3, 0.22, 0.14, 0.09, 1.6)
		_styles["fire_axe"] = _make("swing_heavy", "hit_blade", "쩌억!", "blade", Color("#FF7A5A"), 160.0, 1.45, 0.46, 0.55, 0.24, 0.16, 0.1, 1.8)
		_styles["crossbow"] = _make("", "hit_bolt", "턱!", "bolt", Color("#E8E0C8"), 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.04, 0.8)
		_styles["torch"] = _make("swing_fire", "hit_fire", "치익!", "fire", Color("#FF9A3A"), 130.0, 1.2, 0.34, 0.15, 0.22, 0.07, 0.05, 0.4)
		# v0.28.9 직업 전용 무기.
		_styles["greatsword"] = _make("swing_heavy", "hit_blade", "쩡!", "blade", Color("#BFE0FF"), 170.0, 1.75, 0.55, 0.4, 0.26, 0.18, 0.1, 1.6)
		_styles["twin_daggers"] = _make("swing_blade", "hit_stab", "슥!", "blade", Color("#C8A8FF"), 100.0, 0.95, 0.2, -0.2, 0.1, 0.04, 0.03, 0.8)
		_styles["repeater_crossbow"] = _make("", "hit_bolt", "탁!", "bolt", Color("#BFE6FF"), 0.0, 0.0, 0.0, 0.0, 0.0, 0.06, 0.04, 0.9)
		_styles["healing_staff"] = _make("swing_light", "hit_wood", "퉁!", "light", Color("#9AF0B0"), 120.0, 1.3, 0.3, 0.1, 0.18, 0.06, 0.04, 0.5)
		# 직업 기술.
		_styles["whirl"] = _make("skill_whirl", "hit_blade", "베기!", "whirl", Color("#E0603A"), 360.0, 2.6, 0.55, 0.0, 0.34, 0.12, 0.08, 1.2)
		_styles["pierce"] = _make("skill_pierce", "hit_bolt", "관통!", "pierce", Color("#7AC8FF"), 0.0, 0.0, 0.0, 0.0, 0.0, 0.08, 0.06, 1.0)
	return _styles.get(weapon_id, _styles["hands"])


## 휘두르기: who (Player · RemotePlayer) 앞에 궤적 · 바람 소리. 몸이 보는 쪽은 body.rotation.y (정면 -Z).
static func swing(parent: Node, who: Node3D, body: Node3D, weapon_id: String) -> void:
	if parent == null or who == null or not who.is_inside_tree():
		return
	var s: Style = style(weapon_id)
	if not s.swing_sfx.is_empty():
		Audio.play_at(s.swing_sfx, who.global_position, -6.0, randf_range(0.94, 1.08))
	var yaw: float = body.global_rotation.y if body != null else who.global_rotation.y
	if s.kind == "stab":
		# 쇠창: 앞으로 쭉 찌르는 빛줄기.
		var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var from: Vector3 = who.global_position + Vector3(0.0, 1.05, 0.0) + fwd * 0.4
		Fx.beam(parent, from, from + fwd * s.radius, s.color, s.width, 0.16)
		return
	if s.sweep <= 0.0:
		return
	# 번갈아 왼쪽 → 오른쪽, 오른쪽 → 왼쪽으로 벤다.
	var cw: bool = (Engine.get_process_frames() / 7) % 2 == 0
	Fx.slash(parent, who.global_position, yaw, s.color, s.radius, s.sweep, 1.0 - s.tilt * 0.3, s.dur, s.width, s.tilt, cw)
	if s.kind == "fire":
		Fx.embers(parent, who.global_position + Vector3(-sin(yaw), 1.1, -cos(yaw)) * Vector3(0.8, 1.0, 0.8), 8)


## 맞은 자리 효과 (소리는 부르는 쪽이). at = 가슴 높이, dir = 때린 쪽에서 맞은 쪽으로.
static func impact(parent: Node, at: Vector3, dir: Vector3, s: Style, crit: bool) -> void:
	var b: float = s.blood * (1.5 if crit else 1.0)
	match s.kind:
		"fist":
			Fx.flash(parent, at, Color("#FFF0D8"), 0.55)
			Fx.blood(parent, at, dir, b)
		"light":
			Fx.flash(parent, at, Color("#CFE6FF"), 0.6)
			Fx.sparks(parent, at, dir, 6, Color("#9AC8FF"))
			Fx.blood(parent, at, dir, b)
		"blunt":
			Fx.flash(parent, at, Color("#FFE6B0"), 0.85)
			Fx.blood(parent, at, dir, b)
			Fx.dust_ring(parent, Vector3(at.x, 0.05, at.z), 0.6, Color("#8A7A66"))
		"metal":
			Fx.flash(parent, at, Color("#FFF6D0"), 0.8)
			Fx.sparks(parent, at, dir, 18)
			Fx.blood(parent, at, dir, b)
		"nails":
			Fx.flash(parent, at, Color("#FFD0B0"), 1.0)
			Fx.blood(parent, at, dir, b)
			Fx.sparks(parent, at, dir, 6, Color("#C84A3A"))
		"blade":
			Fx.flash(parent, at, Color("#FFFFFF"), 0.75)
			Fx.blood(parent, at, dir, b)
			Fx.slash(parent, at - Vector3(0.0, 1.0, 0.0), atan2(dir.x, dir.z), Color("#C81A1A"), 0.55, 110.0, 1.0, 0.12, 0.16, 0.9)
		"stab":
			Fx.flash(parent, at, Color("#FFFFFF"), 0.6)
			Fx.blood(parent, at, dir, b)
		"fire":
			Fx.flash(parent, at, Color("#FF9A3A"), 0.9)
			Fx.embers(parent, at, 18)
			Fx.blood(parent, at, dir, b)
		"bolt":
			Fx.flash(parent, at, Color("#FFF0D0"), 0.5)
			Fx.blood(parent, at, dir, b)
		"whirl":
			Fx.flash(parent, at, Color("#FF8A5A"), 0.9)
			Fx.blood(parent, at, dir, b)
		"pierce":
			Fx.flash(parent, at, Color("#BFE6FF"), 0.8)
			Fx.sparks(parent, at, dir, 10, Color("#7AC8FF"))
			Fx.blood(parent, at, dir, b)
	if crit:
		Fx.flash(parent, at, Color("#FFD24A"), 1.4)
		Fx.sparks(parent, at, Vector3.UP, 12, Color("#FFD24A"))
