class_name HomeSight
extends Node
## 집 안 벽 너머 가리기 (v0.13.6): 3인칭으로 위에서 내려다보면 벽 너머 다른 방까지 다 보이므로,
## 캐릭터 자리에서 벽에 막혀 안 보이는 곳(바닥 · 벽 · 가구 · 창)은 어둡게 덮고, 그 자리에 있는 친구 캐릭터도 감춘다.
## 1인칭에서는 진짜 시야라, 꾸미기(위에서 본 평면도)에서는 집 전체를 봐야 하므로 끈다.
## 집을 지을 때 벽 상자(HomeInterior.wall_boxes)로 "가장 가까운 벽까지 거리" 지도(10cm 칸)를 한 번 만들고,
## 덮개 머티리얼(home_sight.tres · toon_world_see 의 sight_overlay)이 화소마다 캐릭터 쪽으로 그 지도를 따라 걸어가 본다 (GPU).
## 친구 캐릭터는 같은 지도로 CPU 에서 한 줄만 확인한다.

const OVERLAY: Material = preload("res://assets/materials/home_sight.tres")
## 지도 한 칸 (m)과 평면도 둘레 여유 (m).
const CELL: float = 0.1
const PAD: float = 1.0
## 지도에 담는 최대 거리 (m) — R8 한 칸 = 1cm.
const FIELD_MAX: float = 2.55
## 친구 캐릭터를 가리는 벽 거리 (m).
const BLOCK: float = 0.06

var interior: HomeInterior = null
var player: Player = null
var first_person: HomeFirstPerson = null
var editor: HomeEditor = null
var replicator: PlayerReplicator = null

var material: ShaderMaterial = null
var _field: PackedFloat32Array = PackedFloat32Array()
var _w: int = 0
var _h: int = 0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	material = OVERLAY.duplicate() as ShaderMaterial
	material.set_shader_parameter("sight_field_max", FIELD_MAX)
	if interior != null:
		interior.sight_overlay = material
		interior.built.connect(_rebuild)


## 지금 가리는 중인지 (집 안 3인칭).
func active() -> bool:
	return Home.is_inside() and not _field.is_empty() and (first_person == null or not first_person.active) and (editor == null or not editor.active)


func _process(_delta: float) -> void:
	var on: bool = active() and player != null
	material.set_shader_parameter("sight_on", 1.0 if on else 0.0)
	if on:
		material.set_shader_parameter("sight_eye", Vector2(player.global_position.x, player.global_position.z))
	_update_remotes(on)


## 이 자리가 캐릭터 자리에서 보이는지 (셰이더와 같은 식, 친구 캐릭터용).
func can_see(at: Vector3) -> bool:
	if _field.is_empty() or player == null:
		return true
	var p: Vector2 = Vector2(at.x, at.z)
	var eye: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var dist: float = p.distance_to(eye)
	if dist < 0.3:
		return true
	var dir: Vector2 = (eye - p) / dist
	var t: float = 0.2
	while t < dist - 0.1:
		var d: float = field_at(p + dir * t)
		if d < BLOCK:
			return false
		t += maxf(d * 0.9, 0.04)
	return true


## 그 자리(월드 x, z)에서 가장 가까운 벽까지 거리 (m). 지도 밖이면 FIELD_MAX.
func field_at(p: Vector2) -> float:
	var c: Vector2 = (p - _origin) / CELL - Vector2(0.5, 0.5)
	var i: int = clampi(roundi(c.x), 0, _w - 1)
	var j: int = clampi(roundi(c.y), 0, _h - 1)
	if c.x < -1.0 or c.y < -1.0 or c.x > _w or c.y > _h:
		return FIELD_MAX
	return _field[j * _w + i]


func _update_remotes(on: bool) -> void:
	if replicator == null:
		return
	for remote: RemotePlayer in replicator.remote_nodes():
		remote.visible = not on or can_see(remote.global_position)


## 벽 상자들로 거리 지도를 만든다: 벽 칸 = 0, 나머지는 가장 가까운 벽 칸까지 (두 번 훑는 3-4 체임퍼 거리).
func _rebuild() -> void:
	if interior == null or interior.plan == null:
		_field = PackedFloat32Array()
		return
	var size: Vector2 = interior.plan.size + Vector2(PAD, PAD) * 2.0
	_w = ceili(size.x / CELL)
	_h = ceili(size.y / CELL)
	var base: Vector3 = interior.global_position
	_origin = Vector2(base.x - PAD, base.z - PAD)
	var big: int = 1 << 20
	var cost: PackedInt32Array = PackedInt32Array()
	cost.resize(_w * _h)
	cost.fill(big)
	for box: AABB in interior.wall_boxes:
		var i0: int = clampi(floori((box.position.x + PAD) / CELL), 0, _w - 1)
		var i1: int = clampi(floori((box.end.x + PAD) / CELL), 0, _w - 1)
		var j0: int = clampi(floori((box.position.z + PAD) / CELL), 0, _h - 1)
		var j1: int = clampi(floori((box.end.z + PAD) / CELL), 0, _h - 1)
		for j: int in range(j0, j1 + 1):
			for i: int in range(i0, i1 + 1):
				cost[j * _w + i] = 0
	# 앞으로 훑기 (왼쪽 · 위 이웃), 뒤로 훑기 (오른쪽 · 아래 이웃). 곧은 이웃 3, 대각 4 (칸 = 3).
	for j: int in _h:
		for i: int in _w:
			var k: int = j * _w + i
			var v: int = cost[k]
			if v == 0:
				continue
			if i > 0:
				v = mini(v, cost[k - 1] + 3)
			if j > 0:
				v = mini(v, cost[k - _w] + 3)
				if i > 0:
					v = mini(v, cost[k - _w - 1] + 4)
				if i < _w - 1:
					v = mini(v, cost[k - _w + 1] + 4)
			cost[k] = v
	for j: int in range(_h - 1, -1, -1):
		for i: int in range(_w - 1, -1, -1):
			var k: int = j * _w + i
			var v: int = cost[k]
			if v == 0:
				continue
			if i < _w - 1:
				v = mini(v, cost[k + 1] + 3)
			if j < _h - 1:
				v = mini(v, cost[k + _w] + 3)
				if i < _w - 1:
					v = mini(v, cost[k + _w + 1] + 4)
				if i > 0:
					v = mini(v, cost[k + _w - 1] + 4)
			cost[k] = v
	_field.resize(_w * _h)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_w * _h)
	for k: int in _w * _h:
		var meters: float = minf(float(cost[k]) / 3.0 * CELL, FIELD_MAX)
		_field[k] = meters
		bytes[k] = int(round(meters / FIELD_MAX * 255.0))
	var image: Image = Image.create_from_data(_w, _h, false, Image.FORMAT_R8, bytes)
	material.set_shader_parameter("sight_field", ImageTexture.create_from_image(image))
	material.set_shader_parameter("sight_rect", Vector4(_origin.x, _origin.y, _w * CELL, _h * CELL))
