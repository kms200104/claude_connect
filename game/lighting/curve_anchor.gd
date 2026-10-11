class_name CurveAnchor
extends Node3D
## 따로 노는 작은 3D 무대(own_world_3d SubViewport — 탈것 미리보기 · 손님 얼굴)의 뿌리.
## 땅 휘기(world_curve)는 전역 셰이더 값이라 그 무대에도 마을의 기준점(내 캐릭터 자리)으로 걸린다.
## 무대가 원점에 있으면 기준점에서 멀어 통째로 땅 밑으로 가라앉아 안 보이므로, 늘 기준점 바로 위에 따라가 둔다.
## 무대 속 물건 · 카메라는 이 노드의 자식으로 (지역 좌표로) 둔다.


func _ready() -> void:
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	position = Vector3(WorldStyle.curve_origin.x, 0.0, WorldStyle.curve_origin.z)


## 무대 안 카메라를 지역 좌표로 겨눈다 (from 에서 at 을 본다).
static func aim(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
