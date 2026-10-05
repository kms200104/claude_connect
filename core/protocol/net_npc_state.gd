class_name NetNpcState
extends RefCounted
## 서버가 보내는 주민 한 명의 위치. 주민은 땅 위만 걸으므로 높이는 없다.

var id: String = ""
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
## 대화 중인 플레이어 id (0이면 아무도 아님).
var talking_with: int = 0
## 지금 기분 (happy / calm / sad / grumpy / sleepy / excited). 말투와 머리 위 표정이 바뀐다.
var mood: String = "calm"
## 먼저 말을 걸러 다가가는 플레이어 id (0이면 아무도 아님, v0.11).
var approaching: int = 0


static func from_dict(data: Dictionary) -> NetNpcState:
	var state: NetNpcState = NetNpcState.new()
	state.id = str(data.get("id", ""))
	state.position = Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
	state.yaw = float(data.get("yaw", 0.0))
	state.talking_with = int(data.get("talk", 0))
	state.mood = str(data.get("m", "calm"))
	state.approaching = int(data.get("ap", 0))
	return state
