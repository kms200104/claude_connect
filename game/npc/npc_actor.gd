class_name NpcActor
extends Node3D
## 주민 한 명의 화면 표시. 위치·방향은 서버가 정하고(10Hz), 여기서는 부드럽게 따라가며 걷기 애니메이션을 맞춘다.
## 머리 위 표시: 내가 받은 부탁이 있으면 "…", 완료할 수 있으면 "!".

@export_group("References")
@export var body: Node3D
@export var rig: CharacterRig
@export var name_label: Label3D
@export var mark: Label3D

@export_group("Motion")
## 클수록 서버 위치에 딱 붙는다 (지수 감쇠 계수).
@export_range(1.0, 40.0, 0.5) var follow_smoothing: float = 8.0
@export_range(1.0, 40.0, 0.5) var turn_smoothing: float = 8.0
## 이 속도(m/s)로 움직이면 walk 애니메이션이 100% 재생된다 (서버 주민 걷기 속도).
@export_range(0.2, 10.0, 0.1, "suffix:m/s") var walk_speed_reference: float = 1.4
## 이보다 멀리 떨어진 서버 위치는 보간하지 않고 바로 옮긴다.
@export_range(1.0, 50.0, 0.5, "suffix:m") var teleport_distance: float = 8.0
## 멈춰 있을 때 이 거리 안에 내 캐릭터가 오면 그쪽을 돌아본다 (v0.11).
@export_range(0.0, 15.0, 0.5, "suffix:m") var look_range: float = 5.0

var info: NpcInfo = null
## 대화 중인 플레이어 id (0 = 없음).
var talking_with: int = 0
## 나에게 다가오는 중인 플레이어 id (0 = 없음).
var approaching: int = 0
## 길목에 멈춰 하는 몸짓 (서버가 정한다, v0.16).
var activity: String = ""
## 돌아볼 대상 (내 캐릭터). NpcCrowd 가 채운다.
var look_target: Node3D = null

var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _shown_speed: float = 0.0
var _has_state: bool = false
var _mark_time: float = 0.0


## 장면에 있는 주민(가게 사람 포함) 가운데 id 가 같은 것 (없으면 null).
static func find(tree: SceneTree, npc_id: String) -> NpcActor:
	for node: Node in tree.get_nodes_in_group(&"npc_actors"):
		var actor: NpcActor = node as NpcActor
		if actor != null and actor.info != null and actor.info.id == npc_id and actor.is_inside_tree():
			return actor
	return null


func setup(npc: NpcInfo) -> void:
	info = npc
	name = "Npc_%s" % npc.id
	# 다른 사람의 대화 말풍선을 이 주민 머리 위에 띄울 때 id 로 찾는다 (find).
	add_to_group(&"npc_actors")
	if name_label != null:
		name_label.text = npc.display_name
	if rig != null:
		rig.set_held("")
		rig.set_look(npc.look)
	global_position = npc.home
	_target_position = npc.home
	set_mark("")
	# 화면 밖에 있는 주민은 애니메이션을 계산하지 않는다.
	var notifier: VisibleOnScreenNotifier3D = VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, 2.6, 1.2))
	notifier.screen_entered.connect(func() -> void: _set_animating(true))
	notifier.screen_exited.connect(func() -> void: _set_animating(false))
	add_child(notifier)


func apply_state(state: NetNpcState) -> void:
	talking_with = state.talking_with
	approaching = state.approaching
	mood = state.mood
	# 그날 기분이 얼굴에 드러난다 (기분 좋음 미소 · 우울하면 처진 눈꺼풀 · 졸리면 반쯤 감긴 눈 …).
	if rig != null:
		rig.set_mood_face(mood)
	_target_yaw = state.yaw
	_set_activity(state.activity)
	if not _has_state or global_position.distance_to(state.position) > teleport_distance:
		global_position = state.position
		if body != null:
			body.rotation.y = state.yaw
	_target_position = state.position
	_has_state = true


## 머리 위 표시 ("" = 숨김).
func set_mark(text: String) -> void:
	if mark == null:
		return
	mark.visible = not text.is_empty()
	mark.text = text


## 지금 기분 (서버가 알려 준다). 가끔 혼자서 기분대로 몸짓을 한다 (NpcCrowd).
var mood: String = "calm"


## 감정표현 (몸짓 + 머리 위 말풍선 + 말소리). line 이 있으면 머리 위에 짧은 대사도 띄운다.
func play_emote(emote_id: String, line: String = "") -> void:
	if rig != null:
		rig.play_emote(emote_id)
	EmoteBubble.pop(self, emote_id, 2.25)
	var voice: float = info.voice if info != null else 1.0
	var sample: String = line if not line.is_empty() else "웅"
	for i: int in mini(sample.length(), 3):
		Audio.babble(sample[i], voice, global_position + Vector3(0.0, 1.5, 0.0))
	if not line.is_empty():
		EmoteBubble.say(self, line)


## 서버가 방향을 알려 주기 전에 먼저 상대를 돌아본다 (대화 시작 반응).
func face_toward(position: Vector3) -> void:
	var d: Vector3 = position - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_target_yaw = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	var before: Vector3 = global_position
	global_position = global_position.lerp(_target_position, weight)
	if body != null:
		body.rotation.y = lerp_angle(body.rotation.y, _look_yaw(), 1.0 - exp(-turn_smoothing * delta))
	if rig != null and delta > 0.0:
		var moved: float = Vector3(global_position.x - before.x, 0.0, global_position.z - before.z).length() / delta
		_shown_speed = lerpf(_shown_speed, moved, 1.0 - exp(-10.0 * delta))
		rig.set_move_speed(_shown_speed / walk_speed_reference)
	if mark != null and mark.visible:
		_mark_time += delta
		mark.position.y = 2.45 + sin(_mark_time * 4.0) * 0.06


## 몸짓 바꾸기: 리그 자세 · 표정 · 낚싯대. 해 바라보기는 지금 해가 있는 쪽으로 돌아선다.
func _set_activity(activity_id: String) -> void:
	if activity_id == activity:
		return
	activity = activity_id
	if rig != null:
		rig.set_activity(activity_id)


## 해가 있는 쪽 (SkyController 의 해 방향과 같은 식).
static func sun_yaw() -> float:
	var hour: float = Net.game_hour() if Net.state == Net.State.ONLINE else 13.0
	var light: Vector3 = Basis.from_euler(SkyController._sun_rotation(hour, true)) * Vector3.FORWARD
	# 빛이 오는 쪽(해)을 바라본다 (모델 정면은 -Z).
	return atan2(light.x, light.z)


## 서 있을 때 가까이 온 내 캐릭터를 돌아본다 (대화 중이 아니고, 걷는 중이 아닐 때). 아니면 서버가 정한 방향.
## 몸짓 중에는 돌아보지 않는다 (낚시는 물 쪽, 해 바라보기는 해 쪽).
func _look_yaw() -> float:
	if activity == "sun":
		return sun_yaw()
	if not activity.is_empty():
		return _target_yaw
	if look_target == null or talking_with != 0 or _shown_speed > 0.25 or not look_target.is_inside_tree():
		return _target_yaw
	var d: Vector3 = look_target.global_position - global_position
	var dist: float = Vector2(d.x, d.z).length()
	if dist > look_range or dist < 0.05:
		return _target_yaw
	return atan2(-d.x, -d.z)


## 지금 나를 바라보고 있는가 (서버 방향이든 돌아봄이든).
func is_looking_at(position: Vector3, tolerance: float = 0.5) -> bool:
	if body == null:
		return false
	var d: Vector3 = position - global_position
	return absf(angle_difference(body.rotation.y, atan2(-d.x, -d.z))) < tolerance


func _set_animating(on: bool) -> void:
	if rig != null and rig.tree != null:
		rig.tree.active = on
