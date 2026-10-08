class_name PlayerReplicator
extends Node
## 내 캐릭터의 위치를 서버로 보내고(요청), 서버가 알려 준 다른 플레이어를 RemotePlayer로 보여 준다.

@export_group("References")
@export var player: Player
@export var remote_scene: PackedScene
@export var remote_parent: Node3D

@export_group("Send")
@export_range(5.0, 60.0, 1.0, "suffix:Hz") var send_rate: float = 20.0
## 이만큼도 안 움직였으면 새 위치를 보내지 않는다.
@export_range(0.0, 0.5, 0.005, "suffix:m") var send_position_epsilon: float = 0.01
## 가만히 있어도 이 간격마다 한 번은 보낸다.
@export_range(0.1, 5.0, 0.1, "suffix:s") var idle_send_interval: float = 1.0

## 상대의 대화 말풍선이 들리는 거리 (m).
const SAY_HEAR_RANGE: float = 28.0

var _remotes: Dictionary[int, RemotePlayer] = {}
var _send_accum: float = 0.0
var _since_last_send: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _last_yaw: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	# v16 휴대폰 지도가 친구 자리를 찾는다.
	add_to_group(&"player_replicator")
	Net.welcomed.connect(_on_welcomed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.face_changed.connect(_on_face_changed)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_status_changed.connect(_on_peer_status_changed)
	Net.snapshot_received.connect(_on_snapshot)
	Net.position_corrected.connect(_on_position_corrected)
	Net.session_lost.connect(_on_session_lost)
	Net.state_changed.connect(_on_state_changed)
	Net.inventory_updated.connect(func(_slots: Array[InventoryItem], _held: int) -> void: _sync_held_item())
	Net.peer_action.connect(_on_peer_action)
	Net.peer_act.connect(_on_peer_act)
	Economy.job_changed.connect(_sync_held_item)
	Net.peer_said.connect(_on_peer_said)
	Net.profile_updated.connect(_sync_outfit)
	_sync_held_item()


func _physics_process(delta: float) -> void:
	if Net.state != Net.State.ONLINE or player == null:
		return
	_send_accum += delta
	_since_last_send += delta
	if _send_accum < 1.0 / send_rate:
		return
	_send_accum = 0.0
	var yaw: float = player.body.rotation.y if player.body != null else 0.0
	var moved: bool = _last_pos == Vector3.INF \
		or player.global_position.distance_to(_last_pos) > send_position_epsilon \
		or absf(angle_difference(_last_yaw, yaw)) > 0.01 \
		or player.velocity.distance_to(_last_velocity) > 0.05
	if not moved and _since_last_send < idle_send_interval:
		return
	_since_last_send = 0.0
	_last_pos = player.global_position
	_last_yaw = yaw
	_last_velocity = player.velocity
	Net.send_move(player.global_position, yaw, player.velocity)


## 상대 플레이어 위치 (없으면 Vector3.INF).
func remote_position(id: int) -> Vector3:
	var remote: RemotePlayer = _remotes.get(id)
	return remote.global_position if remote != null else Vector3.INF


## 상대 플레이어 위치 전부.
func remote_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for remote: RemotePlayer in _remotes.values():
		out.append(remote.global_position)
	return out


## 보이고 있는 다른 플레이어들 (집 안 벽 너머 가리기 HomeSight 가 감추고 보인다).
func remote_nodes() -> Array[RemotePlayer]:
	var out: Array[RemotePlayer] = []
	for remote: RemotePlayer in _remotes.values():
		if is_instance_valid(remote):
			out.append(remote)
	return out


func _teleport_player(position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	_last_pos = Vector3.INF


func _spawn_remote(state: NetPlayerState) -> RemotePlayer:
	var remote: RemotePlayer = _remotes.get(state.id)
	if remote == null:
		remote = remote_scene.instantiate()
		remote_parent.add_child(remote)
		_remotes[state.id] = remote
		remote.setup(state)
	return remote


func _clear_remotes() -> void:
	for remote: RemotePlayer in _remotes.values():
		remote.queue_free()
	_remotes.clear()


func _on_welcomed(self_state: NetPlayerState, others: Array[NetPlayerState], _resumed: bool) -> void:
	# 서버가 알고 있는 내 위치로 맞춘다 (새 방이면 스폰 위치, 재접속이면 마지막 위치).
	_teleport_player(self_state.position)
	# 재접속이면 기존 원격 캐릭터를 그대로 두고(보간 버퍼 유지), 사라진 사람만 정리한다.
	var present: Array[int] = []
	for state: NetPlayerState in others:
		present.append(state.id)
		_spawn_remote(state).set_online(state.online)
	for id: int in _remotes.keys():
		if not present.has(id):
			_on_peer_left(id)


func _on_peer_joined(state: NetPlayerState) -> void:
	_spawn_remote(state)


func _on_peer_left(id: int) -> void:
	var remote: RemotePlayer = _remotes.get(id)
	if remote != null:
		remote.queue_free()
		_remotes.erase(id)


func _on_peer_status_changed(id: int, online: bool) -> void:
	var remote: RemotePlayer = _remotes.get(id)
	if remote != null:
		remote.set_online(online)


func _on_snapshot(server_time_ms: float, states: Array[NetPlayerState]) -> void:
	for state: NetPlayerState in states:
		if state.id == Net.my_id:
			continue
		var remote: RemotePlayer = _spawn_remote(state)
		remote.push_sample(server_time_ms, state.position, state.yaw, state.velocity, state.fishing, state.held)
		remote.set_phone(state.phone)
		remote.set_outfit(state.hat, state.top)
		remote.set_uniform(state.job)


## 손에 든 도구를 서버가 알려 준 퀵슬롯에 맞춘다.
func _sync_held_item() -> void:
	if player != null and Net.state == Net.State.ONLINE:
		var carry: String = Economy.carry_item()
		player.set_held_item(carry if not carry.is_empty() else Net.held_item_id())


## 내 옷을 서버가 알려 준 대로 입힌다. 가방 창에서 입기 · 벗기를 눌러 바뀐 것이면 탈의소에서 갈아입는다 (v0.15).
func _sync_outfit() -> void:
	if player != null and player.rig != null:
		player.rig.set_look(Net.look_of(Net.my_id))
		var rig: CharacterRig = player.rig
		var changed: bool = rig.outfit_item("hat") != Net.outfit_hat or rig.outfit_item("top") != Net.outfit_top
		# 갈아입는 중이면 커튼이 닫힐 때 그때의 옷을 입힌다.
		if OutfitBooth.is_pending(rig):
			return
		if changed and OutfitBooth.take_local() and player.is_inside_tree() and player.body.visible:
			OutfitBooth.play(rig, OutfitBooth.apply_local.bind(rig), player)
			return
		rig.set_outfit(Net.outfit_hat, Net.outfit_top)


## 거울에서 얼굴을 바꿨다 (나 또는 상대).
func _on_face_changed(id: int, _face: Dictionary) -> void:
	if id == Net.my_id:
		_sync_outfit()
		return
	var remote: RemotePlayer = _remotes.get(id)
	if remote != null and remote.rig != null:
		remote.rig.set_look(Net.look_of(id))


## v12: 추가 값이 있는 상대 동작 (낚시 장면).
func _on_peer_act(id: int, kind: String, msg: Dictionary) -> void:
	var remote: RemotePlayer = _remotes.get(id)
	if remote != null and kind == "fish":
		remote.fish_event(msg)


## v12: 상대가 대화하며 띄운 대사 → 그 주민(또는 상대) 머리 위 말풍선. 내 화면 밖이거나 멀면 띄우지 않는다.
func _on_peer_said(id: int, npc_id: String, text: String) -> void:
	var remote: RemotePlayer = _remotes.get(id)
	if remote == null or text.is_empty():
		return
	var speaker: Node3D = remote
	if not npc_id.is_empty():
		var actor: NpcActor = NpcActor.find(get_tree(), npc_id)
		if actor == null:
			return
		speaker = actor
	if player != null and speaker.global_position.distance_to(player.global_position) > SAY_HEAR_RANGE:
		return
	EmoteBubble.say(speaker, text, 2.95, clampf(1.6 + float(text.length()) * 0.06, 2.0, 4.5))


func _on_peer_action(id: int, kind: String, target: String) -> void:
	var remote: RemotePlayer = _remotes.get(id)
	if remote == null:
		return
	if kind == "emote":
		remote.play_emote(target)
	else:
		remote.play_action(kind, target)


## 다른 사람 캐릭터 (없으면 null).
func remote(id: int) -> RemotePlayer:
	return _remotes.get(id)


func _on_position_corrected(position: Vector3) -> void:
	_teleport_player(position)


func _on_session_lost(_reason: String) -> void:
	_clear_remotes()


func _on_state_changed(new_state: int) -> void:
	if new_state == Net.State.DISCONNECTED:
		_clear_remotes()
