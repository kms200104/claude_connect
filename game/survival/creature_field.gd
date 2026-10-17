class_name CreatureField
extends Node3D
## v0.23 밤 크리처 그림 (Net.creatures — 서버가 자리 · 체력을 정한다).
## v0.28.3 무섭게: 관절이 있는 썩어 가는 몸 (CreatureModel) — 살갗은 멍 · 핏줄 · 축축한 광택, 퀭한 눈구멍 안에서 눈이 빛난다.
##   걸음: 어슬렁이는 한쪽 다리를 끌며 두 팔을 앞으로, 달리미는 앞으로 고꾸라질 듯 팔을 휘저으며, 퉁퉁이는 뒤뚱, 철갑이는 쿵쿵,
##   비명이는 고개가 옆으로 꺾인 채 비틀, 독침이는 웅크리고 독주머니가 숨쉬듯 부푼다, 기어미는 두 팔로 몸을 끌고 온다.
##   가만히 있어도 숨을 쉬고 턱을 우물거리며, 가끔 고개 · 어깨가 갑자기 꺾인다 (경련). 덮치면(a) 턱이 쩍 벌어지며 팔을 내지른다.
##   맞으면 고개가 젖혀지며 피가 튄다. 쓰러지면 무릎이 꺾여 앞으로 고꾸라지고 피가 고인다, 잠시 뒤 땅으로 꺼진다.
##   새로 나타나는 크리처는 땅을 헤집고 기어 나온다. 가끔 신음하고, 덮칠 때 으르렁, 맞으면 살 터지는 소리.
## 머리 위 이름 · 체력 칸 (가까울 때만).
## v0.26 탈것에 들이받히면 빠르기만큼 높이 · 멀리 빙글빙글 날아가 (서버가 미끄러지는 자리를 정한다) 눕고,
## 느리게 닿으면 털썩 넘어진다 (f: 1 날아감 · 2 넘어짐). 벽에 부딪히면 "쿵!".

@export var material: Material
@export_range(1.0, 20.0, 0.5) var follow: float = 8.0

## 종류마다 걸음 (보폭 m · 숙임 · 걸음 크기) — 그림만.
const GAIT: Dictionary = {
	"shambler": {"stride": 0.85, "hunch": -0.32, "swing": 0.45, "knee": 0.7},
	"runner": {"stride": 1.9, "hunch": -0.55, "swing": 0.95, "knee": 1.5},
	"bloated": {"stride": 0.62, "hunch": 0.06, "swing": 0.32, "knee": 0.45},
	"brute": {"stride": 1.05, "hunch": -0.28, "swing": 0.4, "knee": 0.6},
	"screamer": {"stride": 0.95, "hunch": -0.12, "swing": 0.42, "knee": 0.7},
	"spitter": {"stride": 0.85, "hunch": -0.48, "swing": 0.4, "knee": 0.7},
	"crawler": {"stride": 0.55, "hunch": -1.38, "swing": 0.0, "knee": 0.0},
}
const GROAN_RANGE: float = 22.0

class Actor:
	var root: Node3D
	## 날아가기 · 눕기 · 기어 나오기 (rig 의 부모).
	var body: Node3D
	var rig: CreatureModel.Rig
	var tag: Label3D
	## v0.28 게이트 우두머리 이름 · 게이트 크리처 최대 hp (0 = 종류 기본).
	var boss: String = ""
	var max_hp: int = 0
	var kind: String = ""
	var target: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var phase: float = 0.0
	var t: float = 0.0
	## v0.28.7 멀리 있으면 3프레임에 한 번만 몸짓을 계산한다 (밀린 시간을 모아서).
	var anim_acc: float = 0.0
	var anim_slot: int = 0
	var speed: float = 0.0
	var punch: float = 0.0
	var lunge: float = 0.0
	var lunge_heard: bool = false
	var scream: float = 0.0
	## 경련: 목표 (머리 x · y · z, 팔) · 지금 값 · 다음까지 · 붙잡는 시간.
	var tw_goal: Vector4 = Vector4.ZERO
	var tw: Vector4 = Vector4.ZERO
	var tw_next: float = 1.0
	var tw_hold: float = 0.0
	var groan_next: float = 3.0
	var groan: float = 0.0
	## 기어 나오는 중 (0 → 1).
	var emerge: float = 1.0
	## 0 서 있음 · 1 날아가는 중 · 2 넘어져 있음 (서버 f).
	var flag: int = 0
	## 들이받혀 공중에 뜬 시간 · 전체 · 높이 · 도는 빠르기 (rad/s).
	var air_t: float = 0.0
	var air_total: float = 0.0
	var air_h: float = 0.0
	var spin: float = 0.0
	## 쓰러지는 중 (초, 음수 = 아님) · 해가 떠서 · 사라져서 꺼지는지.
	var dead_t: float = -1.0
	var dead_quiet: bool = false
	var pool: MeshInstance3D
	## 다쳤는지 (이름표는 다쳤거나 아주 가까울 때만).
	var hurt: bool = false
	## v0.28.5 우두머리: 기 모으는 중 ("slam" · "charge", 빈 글자 = 아님) · 남은 시간 · 돌진 중.
	var cast: String = ""
	var cast_t: float = 0.0
	var dashing: bool = false
	## v0.28.5 못 박힌 방망이에 맞아 비틀거리는 남은 시간 (초).
	var stun: float = 0.0
	## v0.28.5 어둠 속 눈빛: 몸이 보이는 정도 (0 = 어둠에 묻혀 눈만, 1 = 다 보임) · 다음 깜빡임까지.
	var seen: float = 1.0
	var blink_next: float = 3.0

var _actors: Dictionary[String, Actor] = {}
var _dying: Array[Actor] = []
## 처음 동기화가 지난 뒤 나타나는 크리처만 땅에서 기어 나온다.
var _synced_once: bool = false
static var _pool_mesh: ArrayMesh = null


func _ready() -> void:
	add_to_group(&"creature_field")
	# v0.28.7 첫 화면에 있는 동안 크리처 모형을 미리 빚어 둔다 (일꾼 스레드).
	if GameData.survival != null:
		CreatureModel.prewarm(PackedStringArray(GameData.survival.creature_kinds.keys()))
	Net.creatures_updated.connect(_sync)
	Net.creature_hit.connect(_on_hit)
	Net.creature_dead.connect(_on_dead)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void:
		_synced_once = false
		_sync())
	# v0.28.2 독침이 침 · 비명이 비명 (그림 · 소리).
	Net.message_received.connect(_on_message)


func actor_position(id: String) -> Vector3:
	var a: Actor = _actors.get(id)
	return a.root.global_position if a != null else Vector3.INF


## 가장 가까운 크리처 id (range 안, 없으면 빈 글자).
func nearest(p: Vector3, range_m: float) -> String:
	var best: String = ""
	var best_d: float = range_m
	for id: String in _actors:
		var d: float = Vector2(_actors[id].root.global_position.x - p.x, _actors[id].root.global_position.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = id
	return best


func _sync() -> void:
	for id: String in Net.creatures:
		var c: Dictionary = Net.creatures[id]
		var a: Actor = _actors.get(id)
		if a == null:
			a = _spawn(id, str(c.get("k", "shambler")))
			a.root.position = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
			a.root.rotation.y = float(c.get("yaw", 0.0)) + PI
			# v0.28 게이트 우두머리: 크게 · 금빛 이름표 · 붉은 기운. 게이트 크리처는 푸른 이름표.
			if c.has("b"):
				a.root.scale = Vector3.ONE * float(c.get("s", 1.5))
				a.boss = str(c.get("b", ""))
				a.tag.modulate = Color("#FFD24A")
				a.tag.font_size = 34
				var aura: OmniLight3D = OmniLight3D.new()
				aura.light_color = a.rig.parts.eye_color.lerp(Color("#FF2A1A"), 0.5)
				aura.light_energy = 1.2
				aura.omni_range = 3.5
				aura.position = Vector3(0.0, 1.6, -0.3)
				a.root.add_child(aura)
			elif c.has("g"):
				a.tag.modulate = Color("#A8D8FF")
			if _synced_once and int(c.get("f", 0)) == 0 and player_near(a.root.global_position, 30.0):
				_begin_emerge(a)
		a.target = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
		a.yaw = float(c.get("yaw", 0.0))
		if int(c.get("a", 0)) == 1:
			if a.lunge < 0.5 and player_near(a.root.global_position, GROAN_RANGE):
				Audio.play_at("creature_snarl", a.root.global_position, -2.0, _pitch(a))
			a.lunge = 1.0
		a.flag = int(c.get("f", 0))
		a.max_hp = int(c.get("m", 0))
		_update_tag(a, int(c.get("hp", 1)))
	for id: String in _actors.keys():
		if not Net.creatures.has(id) and is_instance_valid(_actors[id].root):
			_actors[id].root.queue_free()
			_actors.erase(id)
	_synced_once = true


## v0.28.7 이보다 먼 크리처는 FAR_ANIM_EVERY 프레임에 한 번만 몸짓 · 어둠을 계산한다.
const FAR_ANIM_RANGE: float = 22.0
const FAR_ANIM_EVERY: int = 3


func _process(delta: float) -> void:
	var frame: int = Engine.get_process_frames()
	for a: Actor in _actors.values():
		if not is_instance_valid(a.root):
			continue
		a.t += delta
		var before: Vector3 = a.root.position
		a.root.position = before.lerp(a.target, minf(1.0, delta * (follow * 2.0 if a.flag != 0 or a.dashing else follow)))
		var moved: float = Vector2(a.root.position.x - before.x, a.root.position.z - before.z).length() / maxf(delta, 0.001)
		a.speed = lerpf(a.speed, moved, minf(1.0, delta * 6.0))
		if a.air_total > 0.0 or a.flag != 0:
			_tumble(a, delta)
			continue
		# 모형은 -Z 를 본다 (서버 yaw 는 +Z 기준 방향).
		a.root.rotation.y = lerp_angle(a.root.rotation.y, a.yaw + PI, minf(1.0, delta * 6.0))
		a.body.rotation.x = move_toward(a.body.rotation.x, 0.0, delta * 3.0)
		a.body.position.y = move_toward(a.body.position.y, 0.0, delta * 2.0) if a.emerge >= 1.0 else a.body.position.y
		a.anim_acc += delta
		if a.boss.is_empty() and a.lunge <= 0.05 and a.punch <= 0.05 and (frame + a.anim_slot) % FAR_ANIM_EVERY != 0 and not player_near(a.root.global_position, FAR_ANIM_RANGE):
			continue
		_animate(a, a.anim_acc)
		_darkness(a, a.anim_acc)
		a.anim_acc = 0.0
		if a.tag != null:
			a.tag.visible = a.seen > 0.5 and a.emerge >= 1.0 and (player_near(a.root.global_position, 3.0) or (a.hurt or not a.boss.is_empty()) and player_near(a.root.global_position, 14.0))
	for i: int in range(_dying.size() - 1, -1, -1):
		var d: Actor = _dying[i]
		if not is_instance_valid(d.root):
			_dying.remove_at(i)
			continue
		if _die_step(d, delta):
			_dying.remove_at(i)


## v0.28.5 어둠 속 눈빛: 밤 · 던전에서 내 불빛 (손전등 원뿔 · 횃불 · 맨손의 희미한 빛) · 동료 곁 밖에 있는 크리처는
## 몸이 어둠에 묻혀 빛나는 눈만 보인다 (가끔 깜빡인다). 불빛에 들어오면 서서히 드러난다. 맞거나 덮치는 중이면 보인다.
var _player: Player = null
## 프레임마다 한 번만 구하는 것 (밤 · 던전, 기척 감지 거리, 동료 자리).
var _light_frame: int = -1
var _dark_now: bool = false
var _sense_r: float = -1.0
var _mates: Array[Vector3] = []


func _refresh_light() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _light_frame:
		return
	_light_frame = frame
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
	_dark_now = false
	_mates.clear()
	if _player == null:
		return
	var night: bool = Net.state == Net.State.ONLINE and GameData.survival.is_night(Net.game_hour())
	_dark_now = night or not GameData.hunter.dungeon_spot_at(_player.global_position).is_empty()
	if not _dark_now:
		return
	_sense_r = float(GameData.hunter.awaken("sense").get("range", 40.0)) if Net.has_awaken("sense") else -1.0
	var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
	if replicator != null:
		for r: RemotePlayer in replicator.remote_nodes():
			_mates.append(r.global_position)


func is_lit(a: Actor) -> bool:
	_refresh_light()
	var player: Player = _player
	if player == null or not _dark_now:
		return true
	if a.punch > 0.05 or a.lunge > 0.05 or not a.boss.is_empty():
		return true
	var to: Vector3 = a.root.global_position - player.global_position
	to.y = 0.0
	var d: float = to.length()
	# v0.28.5 각성 '기척 감지': 둘레 크리처는 어둠 속에서도 몸이 보인다.
	if d <= _sense_r:
		return true
	match player.held_item:
		"flashlight":
			if d <= 4.6:
				return true
			var fwd: Vector3 = -player.body.global_basis.z if player.body != null else Vector3.FORWARD
			fwd.y = 0.0
			return d <= 15.5 and fwd.length() > 0.01 and to.normalized().dot(fwd.normalized()) >= cos(deg_to_rad(19.0))
		"torch":
			return d <= 7.5
	if d <= 4.6:
		return true
	# 동료 곁 (동료의 불빛).
	for m: Vector3 in _mates:
		if m.distance_to(a.root.global_position) <= 5.0:
			return true
	return false


func _darkness(a: Actor, delta: float) -> void:
	var goal: float = 1.0 if is_lit(a) else 0.0
	var before: float = a.seen
	a.seen = move_toward(a.seen, goal, delta * (2.5 if goal > a.seen else 1.6))
	if a.seen != before or (a.seen > 0.0 and a.seen < 1.0):
		var hide: bool = a.seen <= 0.01
		var fade: float = 0.0 if a.seen >= 0.99 else 1.0 - a.seen
		for m: MeshInstance3D in a.rig.body_meshes:
			m.visible = not hide
			m.transparency = fade
	# 눈: 어둠 속에서는 더 크게 빛나고, 가끔 깜빡인다.
	a.blink_next -= delta
	var blink: float = 1.0
	if a.blink_next < 0.0:
		blink = 0.08
		if a.blink_next < -0.14:
			a.blink_next = randf_range(1.5, 5.0)
	if a.rig.glint != null:
		var dark: float = 1.0 - a.seen
		a.rig.glint.visible = dark > 0.05 and blink > 0.5
		a.rig.glint.transparency = 1.0 - dark if dark < 0.99 else 0.0
		a.rig.halo.visible = a.rig.glint.visible
		a.rig.halo.transparency = a.rig.glint.transparency


## 몸이 어둠에 묻혀 눈만 보이는지 (점검용).
func only_eyes(id: String) -> bool:
	var a: Actor = _actors.get(id)
	return a != null and a.seen <= 0.01 and a.rig.body_meshes.all(func(m: MeshInstance3D) -> bool: return not m.visible)


func _pitch(a: Actor) -> float:
	match a.kind:
		"brute":
			return 0.62
		"bloated":
			return 0.74
		"runner", "crawler":
			return 1.12
		"screamer":
			return 1.25
	return 0.92


# ---- 움직임 ----

func _animate(a: Actor, delta: float) -> void:
	var r: CreatureModel.Rig = a.rig
	var g: Dictionary = GAIT.get(a.kind, GAIT["shambler"])
	var top: float = 3.4 if a.kind == "runner" else 1.6
	var go: float = clampf(a.speed / top, 0.0, 1.0)
	a.phase = wrapf(a.phase + delta * a.speed * TAU / float(g["stride"]), 0.0, TAU * 4.0)
	var ph: float = a.phase
	var breathe: float = sin(a.t * 1.7)
	# 경련: 가끔 고개 · 어깨가 갑자기 꺾였다가 천천히 돌아온다.
	a.tw_next -= delta
	if a.tw_next <= 0.0:
		var nervous: bool = a.kind == "screamer"
		a.tw_next = randf_range(0.35, 1.3) if nervous else randf_range(1.2, 3.6)
		a.tw_goal = Vector4(randf_range(-0.45, 0.45), randf_range(-0.8, 0.8), randf_range(-0.7, 0.7), randf_range(-0.7, 0.7))
		a.tw_hold = randf_range(0.1, 0.35)
	if a.tw_hold > 0.0:
		a.tw_hold -= delta
		a.tw = a.tw.lerp(a.tw_goal, minf(1.0, delta * 38.0))
	else:
		a.tw = a.tw.lerp(Vector4.ZERO, minf(1.0, delta * 3.0))
	# 신음 (가까울 때, 가끔).
	a.groan_next -= delta
	if a.groan_next <= 0.0:
		a.groan_next = randf_range(5.0, 12.0)
		if player_near(a.root.global_position, GROAN_RANGE) and a.emerge >= 1.0:
			Audio.play_at("creature_groan_%d" % randi_range(1, 3), a.root.global_position, -4.0, _pitch(a))
			a.groan = 1.0
	a.groan = maxf(0.0, a.groan - delta * 0.7)
	a.lunge = maxf(0.0, a.lunge - delta * 2.4)
	a.punch = maxf(0.0, a.punch - delta * 3.5)
	a.scream = maxf(0.0, a.scream - delta * 0.9)
	var l: float = ease(a.lunge, 0.6)
	var p: float = a.punch
	# 다리.
	var swing: float = float(g["swing"]) * go
	var knee: float = float(g["knee"]) * go
	var limp: bool = a.kind == "shambler"
	if a.kind == "crawler":
		_crawl(a, delta, go)
	else:
		r.thigh_l.rotation.x = sin(ph) * swing + 0.05
		r.knee_l.rotation.x = -(0.08 + knee * maxf(0.0, cos(ph)))
		var rs: float = swing * (0.4 if limp else 1.0)
		r.thigh_r.rotation.x = sin(ph + PI) * rs + (0.12 if limp else 0.05)
		r.knee_r.rotation.x = -(0.05 + knee * (0.15 if limp else 1.0) * maxf(0.0, cos(ph + PI)))
		r.thigh_l.rotation.z = -0.04
		r.thigh_r.rotation.z = 0.04 + (0.06 if limp else 0.0)
		# 엉덩이: 걸음마다 오르내리고, 저는 다리 쪽으로 푹 꺼진다.
		var bob: float = absf(sin(ph)) * 0.04 * go
		var drop: float = (maxf(0.0, -sin(ph)) * 0.06 * go) if limp else 0.0
		r.hips.position.y = r.parts.hip_y - 0.03 * go + bob - drop - 0.06 * l
		r.hips.rotation.z = sin(ph) * (0.05 + (0.06 if limp else 0.0)) * go + (0.1 * sin(ph) * go if a.kind == "bloated" else 0.0)
		r.hips.rotation.y = sin(ph) * 0.12 * go
		# 몸통: 숙임 · 걸음 흔들림 · 숨 · 덮치기 (앞으로) · 맞기 (뒤로).
		var hunch: float = float(g["hunch"]) * (0.55 + 0.45 * go) if a.kind == "runner" else float(g["hunch"])
		r.spine.rotation.x = hunch + breathe * 0.025 - 0.45 * l + 0.5 * p - 0.03 * sin(ph * 2.0) * go
		r.spine.rotation.z = -sin(ph) * 0.06 * go + a.tw.w * 0.15
		r.spine.rotation.y = -sin(ph) * 0.14 * go
		_arms(a, ph, go, l, p, breathe)
	# 목 · 머리: 숙인 만큼 얼굴을 들고, 늘어져 흔들리고, 경련에 꺾인다.
	var lift: float = -r.spine.rotation.x * 0.7
	r.neck.rotation.x = lift + 0.1 * sin(a.t * 0.9) - 0.2 * l - 0.3 * p
	r.head.rotation.x = 0.1 + a.tw.x - 0.25 * l + 0.45 * p + (0.7 * a.scream if a.kind == "screamer" else 0.0)
	r.head.rotation.y = a.tw.y + sin(a.t * 0.6) * 0.15
	var tilt: float = 0.45 if a.kind == "screamer" else 0.12
	r.head.rotation.z = tilt + sin(a.t * 0.75) * 0.12 + a.tw.z + sin(ph) * 0.08 * go
	# 턱: 늘 우물거리고, 신음하면 벌리고, 덮치면 쩍 (비명이는 빠질 듯).
	var wide: float = 1.45 if a.kind == "screamer" else 0.85
	var open: float = 0.12 + 0.08 * maxf(0.0, sin(a.t * 2.3)) + 0.35 * a.groan + wide * maxf(l, a.scream) + 0.3 * p
	r.jaw.rotation.x = -open
	# 독주머니가 숨쉬듯 부풀었다 오그라든다.
	if r.sac != null:
		r.sac.scale = Vector3.ONE * (1.0 + 0.14 * sin(a.t * 3.1) + 0.3 * l)
	# 기어 나오기.
	if a.emerge < 1.0:
		_emerge_step(a, delta)
	# 맞으면 뒤로 밀린다 · 덮치면 앞으로 튀어 나간다.
	a.body.position.z = -0.32 * l + 0.14 * p
	# 비틀거림: 몸이 크게 휘청이고 고개가 축 늘어진다.
	if a.stun > 0.0:
		a.stun = maxf(0.0, a.stun - delta)
		var k: float = minf(1.0, a.stun * 2.0)
		a.body.rotation.z = sin(a.t * 9.0) * 0.28 * k
		r.head.rotation.x += 0.6 * k
		r.head.rotation.z += sin(a.t * 7.0) * 0.4 * k
	elif a.body.rotation.z != 0.0:
		a.body.rotation.z = move_toward(a.body.rotation.z, 0.0, delta * 2.0)
	# 우두머리 기 모으기: 내려치기 = 두 팔을 머리 위로 치켜들고 몸을 젖힌다, 돌진 = 낮게 웅크리고 떤다.
	if not a.cast.is_empty():
		a.cast_t = maxf(0.0, a.cast_t - delta)
		var shake: float = sin(a.t * 40.0) * 0.04
		match a.cast:
			"slam":
				r.shoulder_l.rotation.x = 2.9
				r.shoulder_r.rotation.x = 2.9
				r.elbow_l.rotation.x = 0.4
				r.elbow_r.rotation.x = 0.4
				r.spine.rotation.x = 0.25 + shake
				r.jaw.rotation.x = -1.0
			"charge":
				r.spine.rotation.x = -0.9 + shake
				r.hips.position.y = r.parts.hip_y * 0.82
				r.shoulder_l.rotation.x = -0.4
				r.shoulder_r.rotation.x = -0.4
				r.jaw.rotation.x = -0.9
	if a.dashing:
		r.spine.rotation.x = -0.85
		r.shoulder_l.rotation.x = 1.6
		r.shoulder_r.rotation.x = 1.6
		if randf() < delta * 14.0:
			Puff.burst(self, a.root.global_position + Vector3(0.0, 0.1, 0.0), Color(0.55, 0.5, 0.45, 0.8), 3, 0.6, 0.3, 0.1, 0.4)


## 팔: 종류마다 다른 자세.
func _arms(a: Actor, ph: float, go: float, l: float, p: float, breathe: float) -> void:
	var r: CreatureModel.Rig = a.rig
	var sl: float = 0.0
	var sr: float = 0.0
	var el: float = 0.0
	var er: float = 0.0
	var zl: float = 0.0
	var zr: float = 0.0
	match a.kind:
		"runner":
			# 달리면 팔을 마구 휘젓고, 서 있으면 앞으로 늘어뜨린다.
			sl = lerpf(0.35, sin(ph + PI) * 1.1 - 0.2, go)
			sr = lerpf(0.5, sin(ph) * 1.1 - 0.2, go)
			el = lerpf(0.3, 1.3, go)
			er = lerpf(0.4, 1.3, go)
			zl = -0.15
			zr = 0.15
		"bloated":
			sl = 0.5 + sin(ph) * 0.2 * go
			sr = 0.5 - sin(ph) * 0.2 * go
			el = 0.5
			er = 0.5
			zl = -0.55
			zr = 0.55
		"brute":
			sl = 0.15 + sin(ph + PI) * 0.35 * go
			sr = 0.15 + sin(ph) * 0.35 * go
			el = 0.35
			er = 0.35
			zl = -0.28
			zr = 0.28
		"screamer":
			# 힘없이 늘어져 흔들린다. 비명이면 뒤로 활짝.
			sl = sin(ph) * 0.18 * go + 0.08 - 0.9 * a.scream
			sr = sin(ph + PI) * 0.18 * go + 0.05 - 0.9 * a.scream
			el = 0.1
			er = 0.15
			zl = -0.06 - 0.8 * a.scream
			zr = 0.06 + 0.8 * a.scream
		"spitter":
			sl = 0.55 + sin(ph) * 0.15 * go
			sr = 0.6 + sin(ph + PI) * 0.15 * go
			el = 0.7
			er = 0.6
			zl = -0.1
			zr = 0.1
		_:
			# 어슬렁이: 두 팔을 앞으로 내밀고 (한쪽이 더 처졌다) 흔들린다.
			sl = 1.25 + sin(ph) * 0.12 * go + breathe * 0.04
			sr = 1.05 + sin(ph + PI) * 0.12 * go - breathe * 0.04
			el = 0.18
			er = 0.32
			zl = 0.06
			zr = -0.04
	# 덮치기: 두 팔을 앞으로 쭉 · 할퀴듯. 맞기: 팔이 흔들려 벌어진다.
	r.shoulder_l.rotation.x = lerpf(sl, 1.75, l) - 0.4 * p + a.tw.w * 0.5
	r.shoulder_r.rotation.x = lerpf(sr, 1.55, l) - 0.4 * p
	r.shoulder_l.rotation.z = zl - 0.35 * p
	r.shoulder_r.rotation.z = zr + 0.35 * p
	r.elbow_l.rotation.x = lerpf(el, 0.05, l)
	r.elbow_r.rotation.x = lerpf(er, 0.25, l)


## 기어미: 배를 땅에 깔고, 두 팔을 번갈아 앞으로 뻗어 땅을 짚고 몸을 끌어당긴다. 짓이겨진 다리는 뒤로 끌린다.
func _crawl(a: Actor, _delta: float, go: float) -> void:
	var r: CreatureModel.Rig = a.rig
	var ph: float = a.phase
	var l: float = ease(a.lunge, 0.6)
	var pull: float = sin(ph)
	r.hips.position.y = 0.2 + 0.03 * absf(pull) * go
	r.hips.rotation.z = pull * 0.08 * go
	r.spine.rotation.x = -1.32 + 0.06 * absf(sin(ph)) * go + 0.25 * l + 0.4 * a.punch
	r.spine.rotation.z = pull * 0.1 * go
	r.spine.rotation.y = pull * 0.16 * go
	r.thigh_l.rotation.x = -1.4 + sin(ph * 0.5) * 0.08
	r.thigh_r.rotation.x = -1.48 - sin(ph * 0.5) * 0.06
	r.thigh_l.rotation.z = -0.18
	r.thigh_r.rotation.z = 0.22
	r.knee_l.rotation.x = 0.0
	r.knee_r.rotation.x = 0.0
	# 팔: 몸이 앞으로 누웠으니 어깨를 크게 돌려 머리 위(앞)로 뻗는다.
	r.shoulder_l.rotation.x = 2.55 + pull * 0.45 * go + 0.3 * l
	r.shoulder_r.rotation.x = 2.55 - pull * 0.45 * go + 0.3 * l
	r.shoulder_l.rotation.z = -0.35
	r.shoulder_r.rotation.z = 0.35
	r.elbow_l.rotation.x = 0.5 - 0.35 * maxf(0.0, pull) * go
	r.elbow_r.rotation.x = 0.5 - 0.35 * maxf(0.0, -pull) * go


## 새로 나타나는 크리처: 땅을 헤집고 머리부터 기어 나온다.
func _begin_emerge(a: Actor) -> void:
	a.emerge = 0.0
	a.body.position.y = -1.8
	Puff.burst(self, a.root.global_position + Vector3(0.0, 0.1, 0.0), Color(0.32, 0.26, 0.2, 0.9), 14, 1.0, 0.5, 0.12, 0.9)
	Audio.play_at("dig", a.root.global_position, -6.0, 0.6)
	Audio.play_at("creature_groan_%d" % randi_range(1, 3), a.root.global_position, -3.0, _pitch(a) * 0.9)
	# 갈라진 땅 (흙빛 원판, 잠시 뒤 사라진다).
	var crack: MeshInstance3D = MeshInstance3D.new()
	var st: SurfaceTool = ClayMesh.begin()
	ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.75, 0.02, 0.75), Color("#2A2018"), 14, 2, Basis(), ClayMesh.blob_wobble(3, 0.25, 5))
	crack.mesh = ClayMesh.commit(st)
	crack.material_override = material
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crack)
	crack.global_position = a.root.global_position + Vector3(0.0, 0.02, 0.0)
	var tween: Tween = crack.create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(crack, "scale", Vector3(0.01, 1.0, 0.01), 1.2)
	tween.tween_callback(crack.queue_free)


func _emerge_step(a: Actor, delta: float) -> void:
	a.emerge = minf(1.0, a.emerge + delta / 1.6)
	var k: float = ease(a.emerge, 0.45)
	a.body.position.y = lerpf(-1.8, 0.0, k)
	# 팔을 머리 위로 뻗어 허우적, 고개를 젖힌다.
	var up: float = 1.0 - smoothstep(0.55, 1.0, a.emerge)
	var r: CreatureModel.Rig = a.rig
	r.shoulder_l.rotation.x = lerpf(r.shoulder_l.rotation.x, 2.7 + sin(a.t * 9.0) * 0.35, up)
	r.shoulder_r.rotation.x = lerpf(r.shoulder_r.rotation.x, 2.5 + sin(a.t * 9.0 + 1.7) * 0.35, up)
	r.head.rotation.x -= 0.5 * up
	r.jaw.rotation.x = lerpf(r.jaw.rotation.x, -0.8, up)
	if randf() < delta * 5.0 * up:
		Puff.burst(self, a.root.global_position + Vector3(randf_range(-0.4, 0.4), 0.15, randf_range(-0.4, 0.4)), Color(0.3, 0.25, 0.2, 0.85), 4, 0.5, 0.4, 0.08, 0.6)


## 들이받혀 날아가는 동안 빙글빙글 (포물선), 내려앉으면 누워 있다가 일어난다.
func _tumble(a: Actor, delta: float) -> void:
	var r: CreatureModel.Rig = a.rig
	# 팔다리가 축 늘어져 흔들린다.
	r.shoulder_l.rotation.x = lerpf(r.shoulder_l.rotation.x, 2.4 + sin(a.t * 11.0) * 0.4, minf(1.0, delta * 6.0))
	r.shoulder_r.rotation.x = lerpf(r.shoulder_r.rotation.x, 2.2 + sin(a.t * 9.0) * 0.4, minf(1.0, delta * 6.0))
	r.jaw.rotation.x = -0.7
	if a.air_total > 0.0:
		a.air_t += delta
		var k: float = clampf(a.air_t / a.air_total, 0.0, 1.0)
		a.body.position.y = 4.0 * a.air_h * k * (1.0 - k)
		a.body.rotation.x += a.spin * delta
		if k >= 1.0:
			a.air_total = 0.0
			a.body.rotation.x = wrapf(a.body.rotation.x, -PI, PI)
			Puff.burst(self, a.root.global_position + Vector3(0.0, 0.1, 0.0), Color(0.75, 0.68, 0.55, 0.8), 8, 0.8, 0.2, 0.1, 0.5)
		return
	# 누워 있다 (f 2 · 미끄러지는 중 f 1), 일어나면 다시 선다.
	var lying: bool = a.flag != 0
	a.body.rotation.x = move_toward(a.body.rotation.x, -1.45 if lying else 0.0, delta * (6.0 if lying else 2.5))
	a.body.position.y = move_toward(a.body.position.y, 0.15 if lying else 0.0, delta * 2.0)
	a.body.rotation.z = move_toward(a.body.rotation.z, 0.0, delta * 2.0)
	if a.tag != null:
		a.tag.visible = player_near(a.root.global_position, 14.0)


func player_near(p: Vector3, d: float) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(p) < d + 10.0


func _on_hit(info: Dictionary) -> void:
	var a: Actor = _actors.get(str(info.get("id", "")))
	if a == null:
		return
	a.punch = 1.0
	if info.has("stun"):
		a.stun = float(info.get("stun", 0)) / 1000.0
	if info.has("shot"):
		_bolt(Vector3(float(info.get("sx", 0.0)), 1.3, float(info.get("sz", 0.0))), a)
	a.tw_goal = Vector4(randf_range(-0.3, 0.3), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), 0.0)
	a.tw_hold = 0.12
	_update_tag(a, int(info.get("hp", 0)))
	if info.has("ram"):
		var u: float = float(info.get("ram", 0.0))
		if u > 0.0:
			# 빠를수록 높이 · 오래 날고 빨리 돈다.
			a.flag = 1
			a.air_t = 0.0
			a.air_total = clampf(0.25 + u * 0.06, 0.3, 1.4)
			a.air_h = clampf(u * u / 70.0, 0.2, 3.6)
			a.spin = -u * 0.9
			_float_text(a.root.global_position + Vector3(0.0, 2.2, 0.0), "쾅!", Color("#FF9A5A"))
			_blood_spray(a, 14)
			Audio.play_at("creature_hit", a.root.global_position, 0.0, 0.7)
			Prefs.vibrate(90, 0.7)
		else:
			a.flag = 2
			_float_text(a.root.global_position + Vector3(0.0, 1.8, 0.0), "털썩", Color("#E8E0C8"))
			Audio.play_sfx("chop", -10.0, 0.6)
		return
	if int(info.get("wall", 0)) > 0:
		_float_text(a.root.global_position + Vector3(0.0, 1.6, 0.0), "쿵! -%d" % int(info.get("wall", 0)), Color("#FF6A5A"))
		Audio.play_sfx("chop", -3.0, 0.45)
		_blood_spray(a, 8)
		return
	_float_text(a.root.global_position + Vector3(0.0, 2.0, 0.0), "퍽!", Color("#FFE08A"))
	_blood_spray(a, 9)
	Audio.play_at("creature_hit", a.root.global_position, -2.0, randf_range(0.85, 1.1))


## v0.28.5 석궁 화살: 쏜 자리에서 크리처까지 빠르게 날아가 꽂힌다 (잠시 뒤 사라진다).
func _bolt(from: Vector3, a: Actor) -> void:
	var to: Vector3 = a.root.global_position + Vector3(0.0, 1.15 * a.rig.parts.scale * a.root.scale.y, 0.0)
	var info: ItemInfo = GameData.item("crossbow_bolt")
	if info == null or info.model.is_empty():
		return
	var bolt: MeshInstance3D = MeshInstance3D.new()
	bolt.mesh = PartMesh.get_mesh("crossbow_bolt", info.model)
	bolt.material_override = material
	add_child(bolt)
	bolt.global_position = from
	if from.distance_to(to) > 0.05:
		bolt.look_at_from_position(from, to, Vector3.UP)
	Audio.play_at("crossbow_shot", from, -2.0, randf_range(0.95, 1.08))
	var flight: float = clampf(from.distance_to(to) / 40.0, 0.04, 0.25)
	var tween: Tween = bolt.create_tween()
	tween.tween_property(bolt, "global_position", to, flight)
	tween.tween_callback(func() -> void:
		if is_instance_valid(a.root) and is_instance_valid(bolt):
			bolt.reparent(a.root, true))
	tween.tween_interval(2.5)
	tween.tween_callback(bolt.queue_free)


## 맞은 자리에서 검붉은 피가 튄다.
func _blood_spray(a: Actor, n: int) -> void:
	Puff.burst(self, a.root.global_position + Vector3(0.0, 1.2 * a.rig.parts.scale * a.root.scale.y, 0.0), Color(0.36, 0.03, 0.03, 0.95), n, 0.7, 0.9, 0.06, 0.5)


func _on_dead(info: Dictionary) -> void:
	var id: String = str(info.get("id", ""))
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		_actors.erase(id)
		return
	_actors.erase(id)
	a.root.set_meta(&"dying", true)
	if a.tag != null:
		a.tag.visible = false
	a.dead_quiet = bool(info.get("sun", false)) or bool(info.get("gone", false))
	a.dead_t = 0.0
	# 어둠 속에서 쓰러져도 몸이 드러난다 (눈빛만 떠 있지 않게).
	if a.rig.glint != null:
		a.rig.glint.visible = false
		a.rig.halo.visible = false
	if not a.dead_quiet:
		a.seen = 1.0
		for m: MeshInstance3D in a.rig.body_meshes:
			m.visible = true
			m.transparency = 0.0
		_float_text(a.root.global_position + Vector3(0.0, 2.2, 0.0), "쓰러뜨렸다!", Color("#FFFFFF"))
		_blood_spray(a, 16)
		if player_near(a.root.global_position, GROAN_RANGE):
			Audio.play_at("creature_die", a.root.global_position, 0.0, _pitch(a))
	_dying.append(a)


## 쓰러지기: 무릎이 꺾이고 앞으로 고꾸라진다 → 피가 번진다 → 땅으로 꺼진다. 끝나면 true.
func _die_step(a: Actor, delta: float) -> bool:
	a.dead_t += delta
	var t: float = a.dead_t
	var r: CreatureModel.Rig = a.rig
	if a.dead_quiet:
		# 해가 떴거나 멀어졌다: 그대로 땅으로 꺼진다.
		a.root.position.y = -1.9 * ease(clampf(t / 1.8, 0.0, 1.0), 2.0)
		if t >= 1.8:
			a.root.queue_free()
			return true
		return false
	var fall: float = ease(clampf(t / 0.75, 0.0, 1.0), 2.4)
	r.knee_l.rotation.x = lerpf(r.knee_l.rotation.x, -1.1, minf(1.0, delta * 8.0))
	r.knee_r.rotation.x = lerpf(r.knee_r.rotation.x, -0.8, minf(1.0, delta * 8.0))
	r.shoulder_l.rotation.x = lerpf(r.shoulder_l.rotation.x, 2.9, minf(1.0, delta * 4.0))
	r.shoulder_r.rotation.x = lerpf(r.shoulder_r.rotation.x, 2.2, minf(1.0, delta * 4.0))
	r.shoulder_l.rotation.z = lerpf(r.shoulder_l.rotation.z, -0.6, minf(1.0, delta * 4.0))
	r.head.rotation.z = lerpf(r.head.rotation.z, 0.9, minf(1.0, delta * 5.0))
	r.jaw.rotation.x = lerpf(r.jaw.rotation.x, -0.6, minf(1.0, delta * 5.0))
	if a.kind != "crawler":
		a.body.rotation.x = -1.42 * fall
		a.body.position.y = 0.12 * fall
	if t > 0.75 and a.pool == null:
		Puff.burst(self, a.root.global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 0.45, 0.4, 0.7), 10, 0.9, 0.2, 0.1, 0.5)
		Audio.play_at("chop", a.root.global_position, -8.0, 0.45)
		a.pool = MeshInstance3D.new()
		a.pool.mesh = _pool()
		a.pool.material_override = material
		a.pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.root.add_child(a.pool)
		a.pool.position = Vector3(0.0, 0.015, -0.9 if a.kind != "crawler" else -0.5)
		a.pool.scale = Vector3(0.05, 1.0, 0.05)
	if a.pool != null:
		var spread: float = clampf((t - 0.75) / 2.0, 0.0, 1.0)
		a.pool.scale = Vector3.ONE * lerpf(0.05, 1.0, ease(spread, 0.4))
		a.pool.scale.y = 1.0
	if t > 3.6:
		a.root.position.y = -1.2 * ease(clampf((t - 3.6) / 1.4, 0.0, 1.0), 2.0)
	if t >= 5.0:
		a.root.queue_free()
		return true
	return false


static func _pool() -> ArrayMesh:
	if _pool_mesh == null:
		var st: SurfaceTool = ClayMesh.begin()
		ClayMesh.add_ellipsoid(st, Vector3.ZERO, Vector3(0.7, 0.012, 0.55), CreatureModel.gore(Color("#3A0606")), 18, 2, Basis(), ClayMesh.blob_wobble(7, 0.22, 4))
		_pool_mesh = ClayMesh.commit(st)
	return _pool_mesh


func _float_text(at: Vector3, text: String, color: Color) -> void:
	var l: Label3D = Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.008
	l.outline_size = 16
	l.modulate = color
	l.outline_modulate = Color("#3A2A1A")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = at
	var tween: Tween = l.create_tween()
	tween.set_parallel(true)
	tween.tween_property(l, "position:y", l.position.y + 0.8, 0.7)
	tween.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(l.queue_free)


func _update_tag(a: Actor, hp: int) -> void:
	if a.tag == null:
		return
	var kind: SurvivalRules.CreatureKind = GameData.survival.creature_kinds.get(a.kind)
	var max_hp: int = a.max_hp if a.max_hp > 0 else (kind.hp if kind != null else maxi(hp, 1))
	var title: String = a.boss if not a.boss.is_empty() else (kind.name if kind != null else a.kind)
	a.hurt = hp < max_hp
	if max_hp > 10:
		# 체력이 많으면 10칸 막대로.
		var full: int = ceili(10.0 * float(maxi(hp, 0)) / float(max_hp))
		a.tag.text = "%s\n%s %d" % [title, "■".repeat(full) + "□".repeat(10 - full), maxi(hp, 0)]
	else:
		a.tag.text = "%s\n%s" % [title, "■".repeat(maxi(hp, 0)) + "□".repeat(maxi(max_hp - hp, 0))]


func _spawn(id: String, kind: String) -> Actor:
	var a: Actor = Actor.new()
	a.kind = kind
	a.anim_slot = randi() % FAR_ANIM_EVERY
	a.root = Node3D.new()
	a.root.name = "Creature_%s" % id
	add_child(a.root)
	a.body = Node3D.new()
	a.body.name = "Body"
	a.root.add_child(a.body)
	a.rig = CreatureModel.build(kind, material)
	a.body.add_child(a.rig.root)
	a.phase = randf() * TAU
	a.t = randf() * 10.0
	a.tw_next = randf_range(0.5, 3.0)
	a.groan_next = randf_range(1.5, 9.0)
	var p: CreatureModel.Parts = a.rig.parts
	a.tag = Label3D.new()
	a.tag.font_size = 30
	a.tag.pixel_size = 0.0065
	a.tag.outline_size = 8
	a.tag.modulate = Color("#D8604A")
	a.tag.outline_modulate = Color("#120606")
	a.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	a.tag.position = Vector3(0.0, 1.0 if kind == "crawler" else (p.hip_y + p.torso_h + p.neck_len + 0.45) * p.scale, 0.0)
	a.root.add_child(a.tag)
	_actors[id] = a
	return a


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"creature_spit":
			_spit(str(msg.get("id", "")), int(msg.get("to", 0)))
		"creature_scream":
			_scream(str(msg.get("id", "")))
		"boss_cast":
			_boss_cast(msg)


## v0.28.5 우두머리 패턴 (서버 boss_cast): 경고는 땅에 붉게 — 내려치기 = 대상 자리의 원 (가운데가 차오른다),
## 돌진 = 우두머리에서 끝 자리까지 붉은 길. 터지면 충격파 · 화면 흔들림, 소환은 포효.
func _boss_cast(msg: Dictionary) -> void:
	var a: Actor = _actors.get(str(msg.get("id", "")))
	var at: Vector3 = Vector3(float(msg.get("x", 0.0)), 0.03, float(msg.get("z", 0.0)))
	var ms: float = float(msg.get("ms", 0)) / 1000.0
	match str(msg.get("k", "")):
		"slam":
			if a != null:
				a.cast = "slam"
				a.cast_t = ms
			_warn_circle(at, float(msg.get("r", 3.0)), ms)
			Audio.play_at("creature_snarl", at, 2.0, 0.55)
		"slam_hit":
			if a != null:
				a.cast = ""
				a.punch = 0.6
			for i: int in 3:
				Puff.burst(self, at + Vector3(0.0, 0.1, 0.0), Color(0.5, 0.42, 0.36, 0.9), 14, float(msg.get("r", 3.0)) * (0.5 + i * 0.25), 0.4, 0.14, 0.6)
			Audio.play_at("chop", at, 4.0, 0.35)
			_shake_if_near(at, 0.28)
		"charge":
			if a != null:
				a.cast = "charge"
				a.cast_t = ms
			_warn_path(Vector3(float(msg.get("sx", 0.0)), 0.03, float(msg.get("sz", 0.0))), at, float(msg.get("w", 1.5)), ms + 0.6)
			Audio.play_at("creature_shriek", at, -2.0, 0.6)
		"charge_end":
			if a != null:
				a.cast = ""
				a.dashing = false
		"summon":
			if a != null:
				a.scream = 1.0
			_scream(str(msg.get("id", "")))
			_shake_if_near(at, 0.18)
	# 돌진 경고가 끝나면 내달린다.
	if str(msg.get("k", "")) == "charge" and a != null:
		# (서버가 돌진을 미뤘으면 charge_end 가 먼저 와 cast 가 비어 있다. 늦어도 2.5초 뒤에는 멈춘 자세로.)
		get_tree().create_timer(ms).timeout.connect(func() -> void:
			if is_instance_valid(a.root) and a.cast == "charge":
				a.cast = ""
				a.dashing = true
				get_tree().create_timer(2.5).timeout.connect(func() -> void:
					if is_instance_valid(a.root):
						a.dashing = false))


static var _warn_mat: StandardMaterial3D = null


static func _warn_material() -> StandardMaterial3D:
	if _warn_mat == null:
		_warn_mat = StandardMaterial3D.new()
		_warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_warn_mat.albedo_color = Color(1.0, 0.12, 0.08, 0.32)
		_warn_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _warn_mat


func _flat_disc(r: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.02
	cyl.radial_segments = 40
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = _warn_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 내려치기 경고: 바깥 원 (테두리처럼 옅게) + 가운데서 차오르는 원 → 다 차면 터진다.
func _warn_circle(at: Vector3, r: float, ms: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "BossWarn"
	holder.add_to_group(&"boss_warn")
	add_child(holder)
	holder.global_position = at
	var outer: MeshInstance3D = _flat_disc(r)
	holder.add_child(outer)
	var inner: MeshInstance3D = _flat_disc(r)
	inner.position.y = 0.01
	inner.scale = Vector3(0.05, 1.0, 0.05)
	holder.add_child(inner)
	var tween: Tween = holder.create_tween()
	tween.tween_property(inner, "scale", Vector3.ONE, maxf(ms, 0.05))
	tween.tween_interval(0.15)
	tween.tween_callback(holder.queue_free)


## 돌진 경고: 우두머리에서 끝 자리까지 붉은 길 (깜빡인다).
func _warn_path(from: Vector3, to: Vector3, w: float, life: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "BossWarnPath"
	mi.add_to_group(&"boss_warn")
	var box: BoxMesh = BoxMesh.new()
	var length: float = Vector2(to.x - from.x, to.z - from.z).length()
	box.size = Vector3(w * 2.0, 0.02, maxf(length, 0.1))
	mi.mesh = box
	mi.material_override = _warn_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.rotation.y = atan2(to.x - from.x, to.z - from.z)
	var tween: Tween = mi.create_tween()
	tween.set_loops(int(ceil(life / 0.3)))
	tween.tween_property(mi, "transparency", 0.6, 0.15)
	tween.tween_property(mi, "transparency", 0.0, 0.15)
	get_tree().create_timer(life).timeout.connect(mi.queue_free)


## 경고 표시가 몇 개인지 (점검용).
func warn_count() -> int:
	return get_tree().get_nodes_in_group(&"boss_warn").size()


func _shake_if_near(at: Vector3, strength: float) -> void:
	if not player_near(at, 12.0):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null and cam.get_parent() is FollowCamera:
		(cam.get_parent() as FollowCamera).shake(strength, 0.4)
	Prefs.vibrate(90, 0.6)


## 독침이 침: 입에서 초록 덩어리가 포물선으로 날아가 맞은 자리에 튄다.
func _spit(id: String, to: int) -> void:
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		return
	var from: Vector3 = a.root.global_position + Vector3(0.0, 1.5, 0.0)
	var target: Node3D = null
	if to == Net.my_id:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	else:
		var replicator: PlayerReplicator = get_tree().get_first_node_in_group(&"player_replicator") as PlayerReplicator
		if replicator != null:
			for r: RemotePlayer in replicator.remote_nodes():
				if r.player_id == to:
					target = r
	if target == null:
		return
	var goal: Vector3 = target.global_position + Vector3(0.0, 1.1, 0.0)
	var blob: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.16
	sphere.radial_segments = 8
	sphere.rings = 4
	blob.mesh = sphere
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color("#9AD040")
	m.emission_enabled = true
	m.emission = Color("#6AA020")
	blob.material_override = m
	add_child(blob)
	blob.global_position = from
	a.lunge = 1.0
	var tween: Tween = blob.create_tween()
	tween.tween_method(func(k: float) -> void:
		if is_instance_valid(blob):
			blob.global_position = from.lerp(goal, k) + Vector3(0.0, sin(k * PI) * 1.2, 0.0), 0.0, 1.0, 0.32)
	tween.tween_callback(func() -> void:
		Puff.burst(self, goal, Color(0.6, 0.85, 0.25, 0.9), 8, 0.4, 0.2, 0.07, 0.4)
		blob.queue_free())
	Audio.play_at("fish_plop", from, -6.0, 1.6)


## 비명이 비명: 머리 위로 퍼지는 고리 · "끼아아악!" · 소리.
func _scream(id: String) -> void:
	var a: Actor = _actors.get(id)
	if a == null or not is_instance_valid(a.root):
		return
	var at: Vector3 = a.root.global_position
	var l: Label3D = Label3D.new()
	l.text = "끼아아악!"
	l.font_size = 64
	l.pixel_size = 0.009
	l.outline_size = 12
	l.modulate = Color("#FF8A7A")
	l.outline_modulate = Color("#2A0A0A")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = at + Vector3(0.0, 2.6, 0.0)
	var tween: Tween = l.create_tween()
	tween.set_parallel(true)
	tween.tween_property(l, "scale", Vector3.ONE * 1.5, 0.8)
	tween.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.5)
	tween.chain().tween_callback(l.queue_free)
	for i: int in 3:
		Puff.burst(self, at + Vector3(0.0, 1.8, 0.0), Color(1.0, 0.6, 0.5, 0.5), 10, 1.6 + i * 0.8, 0.1, 0.1, 0.6)
	Audio.play_at("creature_shriek", at, 3.0, 1.0)
	a.scream = 1.0
