class_name NetPlayerState
extends RefCounted
## 서버가 보내는 플레이어 한 명의 상태 (위치는 발바닥 기준).

var id: int = 0
var online: bool = true
var fishing: bool = false
## 손에 든 아이템 id (없으면 빈 문자열).
var held: String = ""
## 입은 모자·상의 아이템 id (없으면 빈 문자열).
var hat: String = ""
var top: String = ""
## 거울에서 고른 얼굴 (FaceCatalog id 사전, 입장·참가 때만 온다 — 스냅샷에는 없다).
var face: Dictionary = {}
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var velocity: Vector3 = Vector3.ZERO


static func from_dict(data: Dictionary) -> NetPlayerState:
	var state: NetPlayerState = NetPlayerState.new()
	state.id = int(data.get("id", 0))
	state.online = bool(data.get("online", true))
	state.fishing = bool(data.get("fishing", false))
	state.held = str(data.get("held", ""))
	state.hat = str(data.get("hat", ""))
	state.top = str(data.get("top", ""))
	var f: Variant = data.get("face", {})
	if f is Dictionary:
		state.face = f
	state.position = Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
	state.yaw = float(data.get("yaw", 0.0))
	state.velocity = Vector3(float(data.get("vx", 0.0)), 0.0, float(data.get("vz", 0.0)))
	return state
