class_name Waypoint
extends RefCounted
## 지도에 찍은 웨이포인트 하나 (이 기기에만, 판정과 상관없다): 휴대폰 지도 앱에서 빈 곳을 누르면 놓이고,
## 마을에는 빛기둥 · HUD 방향 화살표 · 작은 지도 깃발로 보인다 (WaypointMarker · MiniMap). 가까이 가면 저절로 지워진다.

## 놓인 자리 (월드 x, z — 없으면 Vector2.INF) · 바뀔 때마다 오르는 번호 (그리는 쪽이 지켜본다).
static var at: Vector2 = Vector2.INF
static var version: int = 0
## 도착으로 치는 거리 (m).
const ARRIVE: float = 4.0


static func is_set() -> bool:
	return at != Vector2.INF


static func place(world: Vector2) -> void:
	at = world
	version += 1


static func clear() -> void:
	if at == Vector2.INF:
		return
	at = Vector2.INF
	version += 1
