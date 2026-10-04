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

var _remotes: Dictionary[int, RemotePlayer] = {}
var _send_accum: float = 0.0
var _since_last_send: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _last_yaw: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	Net.welcomed.connect(_on_welcomed)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_status_changed.connect(_on_peer_status_changed)
	Net.snapshot_received.connect(_on_snapshot)
	Net.position_corrected.connect(_on_position_corrected)
	Net.session_lost.connect(_on_session_lost)
	Net.state_changed.connect(_on_state_changed)


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
		_spawn_remote(state).push_sample(server_time_ms, state.position, state.yaw, state.velocity, state.fishing)


func _on_position_corrected(position: Vector3) -> void:
	_teleport_player(position)


func _on_session_lost(_reason: String) -> void:
	_clear_remotes()


func _on_state_changed(new_state: int) -> void:
	if new_state == Net.State.DISCONNECTED:
		_clear_remotes()
