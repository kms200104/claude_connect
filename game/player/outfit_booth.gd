class_name OutfitBooth
extends Node3D
## 간이 탈의소 (v0.15): 옷을 입거나 벗으면 캐릭터 자리에 둥근 레일(링)과 커튼 두 쪽이 화면 좌우에서 스르륵 미끄러져 들어와
## 캐릭터를 감싸고, 커튼 안에서 갈아입은 뒤(커튼이 들썩인다) 커튼이 열리면 한 바퀴 돌며 "짜잔!" 한다.
## 내 캐릭터면 그동안 움직이지 못하고 카메라가 탈의소로 다가가며, 다 보여 준 뒤 움직이는 순간 카메라가 평소로 돌아온다.
## 친구 캐릭터도 옷이 바뀌면 (카메라 · 소리 없이) 같은 탈의소가 보인다.
## 커튼은 매 프레임 주름 진 반원통 메시를 새로 만든다 (보이는 2.4초 동안만, 한 쪽 3천 정점쯤). 머티리얼은 캐릭터의 점토 머티리얼 하나.

## 커튼 반지름 · 높이 (m). 캐릭터(키 1.6m · 머리 너비 0.9m)와 모자가 넉넉히 들어간다.
const RADIUS: float = 0.64
const HEIGHT: float = 2.0
## 단계별 길이 (초): 들어오기 → 닫기 → 갈아입기 → 열기 → 나가기.
const T_SLIDE_IN: float = 0.4
const T_CLOSE: float = 0.45
const T_HOLD: float = 0.75
const T_OPEN: float = 0.4
const T_SLIDE_OUT: float = 0.35
## 짜잔 자세 길이 (character_rig 의 tada 애니메이션)와 그 안에서 한 바퀴 도는 구간.
const T_TADA: float = 1.5
const SPIN_FROM: float = 0.1
const SPIN_TIME: float = 0.5
## 들어오기 전 커튼이 화면 옆으로 떨어져 있는 거리.
const SLIDE_FROM: float = 1.5
## 커튼 주름 수 · 세로 칸 · 가로 칸 (주름 하나에 6칸 = 줄무늬 두 줄).
const FOLDS: int = 8
const ROWS: int = 6
const COLS: int = FOLDS * 6
## 모은 커튼 · 닫은 커튼이 덮는 각도 (rad). 닫으면 두 쪽이 앞뒤에서 조금 겹친다.
const BUNCHED: float = 0.5
const CLOSED: float = PI + 0.22
const STRIPE_A: Color = Color("#F3B9C4")
const STRIPE_B: Color = Color("#FFF5EA")
const RAIL_COLOR: Color = Color("#C9CFD8")
const CANOPY_COLOR: Color = Color("#E98FA2")

## 갈아입기를 내가 요청했는지 (가방 창의 입기 · 벗기). 서버 응답이 이 시간 안에 오면 탈의소를 연다.
static var _local_until_ms: int = 0

var rig: CharacterRig = null
## 내 캐릭터일 때만 (입력 막기 · 카메라).
var player: Player = null
## 커튼이 다 닫혔을 때 부르는 옷 바꾸기.
var apply: Callable
var applied: bool = false

var _character: Node3D = null
var _camera_rig: FollowCamera = null
var _t: float = 0.0
var _halves: Array[Node3D] = []
var _curtains: Array[MeshInstance3D] = []
var _side_dir: Vector3 = Vector3.RIGHT
var _shown_again: bool = false
var _tada_done: bool = false
var _spin: float = 0.0
## 짜잔 뒤 움직이기를 기다리는 중 (카메라를 놓아줄 때).
var _waiting_move: bool = false
var _rest_position: Vector3 = Vector3.ZERO
var _seed: float = 0.0
var _cleaned: bool = false


## 가방 창에서 입기 · 벗기를 눌렀다.
static func expect_local() -> void:
	_local_until_ms = Time.get_ticks_msec() + 4000


## 내가 요청한 갈아입기의 응답인지 (한 번만 참).
static func take_local() -> bool:
	var ok: bool = Time.get_ticks_msec() < _local_until_ms
	_local_until_ms = 0
	return ok


## 이 캐릭터의 탈의소 (없으면 null).
static func find(of_rig: CharacterRig) -> OutfitBooth:
	if of_rig == null or of_rig.get_parent() == null:
		return null
	return of_rig.get_parent().get_node_or_null(^"OutfitBooth") as OutfitBooth


## 아직 옷을 바꾸기 전인 탈의소가 있는지 (그동안 들어온 옷 정보는 apply 가 커튼이 닫힐 때 읽는다).
static func is_pending(of_rig: CharacterRig) -> bool:
	var booth: OutfitBooth = find(of_rig)
	return booth != null and not booth.applied


## 탈의소를 연다. 커튼이 닫히면 change 를 부른다. 갈아입는 중이면 그 탈의소가 새 change 를 쓴다.
static func play(of_rig: CharacterRig, change: Callable, local_player: Player = null) -> OutfitBooth:
	var old: OutfitBooth = find(of_rig)
	if old != null and not old.applied:
		old.apply = change
		return old
	if old != null:
		old.finish()
	var booth: OutfitBooth = OutfitBooth.new()
	booth.name = "OutfitBooth"
	booth.rig = of_rig
	booth.player = local_player
	booth.apply = change
	of_rig.get_parent().add_child(booth)
	return booth


func _ready() -> void:
	# 애니메이션 트리가 Visual 을 움직인 뒤에 한 바퀴 돌린 각도를 더한다.
	process_priority = 100
	top_level = true
	_character = rig.get_parent() as Node3D
	_rest_position = _character.global_position
	global_position = _rest_position
	_seed = randf() * TAU
	# 화면 좌우에서 들어오도록 카메라 오른쪽을 기준으로 놓는다.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		var right: Vector3 = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)
		if right.length() > 0.01:
			_side_dir = right.normalized()
	global_basis = Basis(Vector3.UP, atan2(-_side_dir.z, _side_dir.x))
	for side: float in [1.0, -1.0]:
		var half: Node3D = Node3D.new()
		half.name = "Right" if side > 0.0 else "Left"
		half.rotation.y = 0.0 if side > 0.0 else PI
		add_child(half)
		var frame: MeshInstance3D = MeshInstance3D.new()
		frame.name = "Rail"
		frame.mesh = _rail_mesh()
		frame.material_override = rig.clay_material
		half.add_child(frame)
		var curtain: MeshInstance3D = MeshInstance3D.new()
		curtain.name = "Curtain"
		curtain.mesh = ArrayMesh.new()
		curtain.material_override = rig.clay_material
		half.add_child(curtain)
		_halves.append(half)
		_curtains.append(curtain)
	if player != null:
		player.set_input_lock(&"booth", true)
		player.clear_look_direction()
		if cam != null:
			_camera_rig = cam.get_parent() as FollowCamera
		if _camera_rig != null:
			_camera_rig.set_booth_view(true, 0.7)
		Audio.play_sfx("line_zip", -8.0, 1.5)
	_update(0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(rig) or not is_instance_valid(_character):
		queue_free()
		return
	_t += delta
	_update(delta)


func _update(_delta: float) -> void:
	var closed_at: float = T_SLIDE_IN + T_CLOSE
	var open_at: float = closed_at + T_HOLD
	var gone_at: float = open_at + T_OPEN + T_SLIDE_OUT
	if _waiting_move:
		_wait_for_move()
		return
	# 친구 캐릭터는 그 자리를 따라간다 (내 캐릭터는 움직이지 못한다).
	global_position = _character.global_position
	if not applied and _t >= closed_at:
		_close_in()
	if applied and not _shown_again and _t >= open_at:
		_show_again()
	# 한 바퀴: 짜잔 동작의 콩 뛰는 구간에 맞춰 Visual 을 돌린다 (트리가 매 프레임 Visual 각도를 다시 쓰므로 더하기만 한다).
	var spin_t: float = (_t - open_at - SPIN_FROM) / SPIN_TIME
	if _shown_again and spin_t > 0.0 and spin_t < 1.0 and rig.visual != null:
		rig.visual.rotation.y += TAU * _ease_in_out(spin_t)
	if _shown_again and not _tada_done and _t >= open_at + T_TADA:
		_tada_done = true
		if player != null:
			player.set_input_lock(&"booth", false)
	# 커튼: 넓이(모음 ↔ 닫힘)와 옆으로 미끄러진 거리.
	var spread: float = 0.0
	var slide: float = 0.0
	if _t < T_SLIDE_IN:
		slide = 1.0 - _ease_out_back(_t / T_SLIDE_IN)
	elif _t < closed_at:
		spread = _ease_in_out((_t - T_SLIDE_IN) / T_CLOSE)
	elif _t < open_at:
		spread = 1.0
	elif _t < open_at + T_OPEN:
		spread = 1.0 - _ease_in_out((_t - open_at) / T_OPEN)
	else:
		slide = _ease_in_out(minf((_t - open_at - T_OPEN) / T_SLIDE_OUT, 1.0))
	var shown: bool = _t < gone_at
	for i: int in _halves.size():
		var half: Node3D = _halves[i]
		half.visible = shown
		if not shown:
			continue
		half.position = Vector3(SLIDE_FROM * slide * (1.0 if i == 0 else -1.0), 0.0, 0.0)
		var s: float = lerpf(1.0, 0.55, slide)
		half.scale = Vector3(s, lerpf(1.0, 0.8, slide), s)
		_build_curtain(_curtains[i].mesh as ArrayMesh, lerpf(BUNCHED, CLOSED, spread), spread, i)
	if not shown and _tada_done:
		if player != null and _camera_rig != null:
			_waiting_move = true
			for half: Node3D in _halves:
				half.queue_free()
			_halves.clear()
			_curtains.clear()
		else:
			queue_free()


## 커튼이 다 닫혔다: 캐릭터를 감추고 옷을 바꾼다. 내 캐릭터면 나올 때 카메라를 보도록 돌려 둔다.
func _close_in() -> void:
	applied = true
	rig.visible = false
	if apply.is_valid():
		apply.call()
	if player != null:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			player.look_toward(cam.global_position - player.global_position)
		Audio.play_sfx("emote_pop", -10.0, 0.8)


func _show_again() -> void:
	_shown_again = true
	rig.visible = true
	rig.play_tada()
	if player != null:
		Audio.play_sfx("line_zip", -8.0, 1.25)
		get_tree().create_timer(0.55).timeout.connect(func() -> void: Audio.play_sfx("emote_up", -4.0))


## 짜잔 뒤: 움직이는 순간(또는 다른 창 · 동작이 입력을 막거나 순간이동하면) 카메라를 평소로.
func _wait_for_move() -> void:
	var moved: bool = Vector2(player.velocity.x, player.velocity.z).length() > 0.25 or player.move_intent.length() > 0.05
	var away: bool = _character.global_position.distance_to(_rest_position) > 0.6
	if moved or away or player.is_input_locked() or not _camera_rig.is_physics_processing():
		queue_free()


## 바로 끝낸다 (새 탈의소가 열릴 때). 새 탈의소가 카메라를 다시 잡기 전에 정리한다.
func finish() -> void:
	name = "OutfitBoothOld"
	_cleanup()
	queue_free()


func _exit_tree() -> void:
	_cleanup()


func _cleanup() -> void:
	if _cleaned:
		return
	_cleaned = true
	if is_instance_valid(rig):
		rig.visible = true
	if not applied and apply.is_valid():
		applied = true
		apply.call()
	if player != null and is_instance_valid(player):
		player.set_input_lock(&"booth", false)
		if not _tada_done:
			player.clear_look_direction()
	if _camera_rig != null and is_instance_valid(_camera_rig):
		_camera_rig.set_booth_view(false, 0.6)


## 한 쪽 커튼: 이 쪽(+X) 가운데에서 앞뒤로 width 만큼 펼친 주름 반원통. 안팎 두 겹 (위에서 내려다보면 안쪽이 보인다).
func _build_curtain(mesh: ArrayMesh, width: float, spread: float, index: int) -> void:
	var t: float = _t
	# 모일수록 주름이 깊다. 닫혀 있는 동안은 안에서 갈아입느라 커튼이 들썩인다.
	var depth: float = lerpf(0.07, 0.022, spread)
	var closed_at: float = T_SLIDE_IN + T_CLOSE
	var rustle: float = 0.0
	if t > closed_at and t < closed_at + T_HOLD:
		rustle = sin((t - closed_at) / T_HOLD * PI)
	var bump_at: float = sin(t * 5.3 + _seed + float(index) * 2.1) * 0.9
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var grid: Array[PackedVector3Array] = []
	var grid_n: Array[PackedVector3Array] = []
	for r: int in ROWS + 1:
		var v: float = float(r) / float(ROWS)
		var y: float = lerpf(0.05, HEIGHT - 0.03, v)
		# 아래 단이 살랑 (모여 있을 때 더).
		var sway: float = (1.0 - v) * (0.05 * (1.0 - spread) + 0.03 * rustle) * sin(t * 6.0 + float(index) * 1.7)
		var row: PackedVector3Array = PackedVector3Array()
		var row_n: PackedVector3Array = PackedVector3Array()
		for c: int in COLS + 1:
			var u: float = float(c) / float(COLS)
			var phi: float = (u - 0.5) * width + sway
			var wave: float = sin(u * TAU * FOLDS)
			var bulge: float = rustle * 0.09 * exp(-pow((phi - bump_at) / 0.4, 2.0)) * sin(v * PI) * (0.6 + 0.4 * sin(t * 13.0 + _seed))
			var rad: float = RADIUS + depth * wave + bulge
			row.append(Vector3(cos(phi) * rad, y, sin(phi) * rad))
			# 주름 기울기만큼 바깥 방향을 옆으로 눕힌다.
			var slope: float = depth * cos(u * TAU * FOLDS) * TAU * FOLDS / maxf(width, 0.01)
			var radial: Vector3 = Vector3(cos(phi), 0.0, sin(phi))
			var tangent: Vector3 = Vector3(-sin(phi), 0.0, cos(phi))
			row_n.append((radial - tangent * slope / rad).normalized())
		grid.append(row)
		grid_n.append(row_n)
	for r: int in ROWS:
		for c: int in COLS:
			# 줄무늬: 주름 반 개마다 색이 바뀐다 (칸마다 정점을 따로 둬 경계가 또렷하다).
			var stripe: Color = STRIPE_A if (c / 3) % 2 == 0 else STRIPE_B
			var shade: float = lerpf(0.86, 1.0, float(r) / float(ROWS))
			var outside: Color = stripe * Color(shade, shade, shade)
			var inside: Color = stripe.darkened(0.25)
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var cc: Vector3 = grid[r + 1][c + 1]
			var d: Vector3 = grid[r + 1][c]
			var na: Vector3 = grid_n[r][c]
			var nb: Vector3 = grid_n[r][c + 1]
			var nc: Vector3 = grid_n[r + 1][c + 1]
			var nd: Vector3 = grid_n[r + 1][c]
			# 바깥 면과 안쪽 면 (정점 순서를 뒤집어 반대쪽에서 보이게).
			for p: Array in [[a, na], [cc, nc], [d, nd], [a, na], [b, nb], [cc, nc]]:
				verts.append(p[0])
				normals.append(p[1])
				colors.append(outside)
			for p: Array in [[a, na], [d, nd], [cc, nc], [a, na], [cc, nc], [b, nb]]:
				verts.append(p[0])
				normals.append(-(p[1] as Vector3))
				colors.append(inside)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## 한 쪽의 레일(반원 링)과 그 위를 덮는 반원 지붕 천, 링에 달린 고리들. 쪽마다 같아서 한 번만 만든다.
static var _rail_cache: ArrayMesh = null


static func _rail_mesh() -> ArrayMesh:
	if _rail_cache != null:
		return _rail_cache
	var st: SurfaceTool = ClayMesh.begin()
	var steps: int = 24
	var tube: float = 0.03
	# 레일: 반원 고리 (가로 반원 × 단면 원).
	for i: int in steps:
		for j: int in 8:
			var quad: Array[Vector3] = []
			var quad_n: Array[Vector3] = []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var phi: float = -PI * 0.5 + PI * float(i + k.x) / float(steps)
				var th: float = TAU * float(j + k.y) / 8.0
				var radial: Vector3 = Vector3(cos(phi), 0.0, sin(phi))
				var n: Vector3 = radial * cos(th) + Vector3.UP * sin(th)
				quad.append(radial * RADIUS + Vector3(0.0, HEIGHT, 0.0) + n * tube)
				quad_n.append(n)
			for idx: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(RAIL_COLOR)
				st.set_normal(quad_n[idx])
				st.add_vertex(quad[idx])
	# 지붕 천: 가운데가 살짝 솟은 반원 (가장자리는 레일 위).
	var rings: int = 5
	for i: int in steps:
		for r: int in rings:
			var pts: Array[Vector3] = []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var phi: float = -PI * 0.5 + PI * float(i + k.x) / float(steps)
				var f: float = float(r + k.y) / float(rings)
				var rad: float = (RADIUS + 0.02) * (1.0 - f)
				pts.append(Vector3(cos(phi) * rad, HEIGHT + 0.02 + 0.16 * (1.0 - pow(1.0 - f, 2.0)), sin(phi) * rad))
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(CANOPY_COLOR if i % 2 == 0 else CANOPY_COLOR.lightened(0.25))
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[idx])
	# 고리: 레일에 걸린 작은 고리 (주름마다 하나).
	for i: int in FOLDS + 1:
		var phi: float = -PI * 0.5 + PI * float(i) / float(FOLDS)
		var at: Vector3 = Vector3(cos(phi) * RADIUS, HEIGHT - 0.035, sin(phi) * RADIUS)
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.022
		ring.outer_radius = 0.036
		ring.rings = 8
		ring.ring_segments = 4
		# 고리 축(Y)을 레일 방향(접선)으로: Z 축으로 90° 눕혀(Y → -X) 그 자리 방향만큼 돌린다.
		ClayMesh.add_primitive(st, ring, Transform3D(Basis(Vector3.UP, PI * 0.5 - phi) * Basis(Vector3.BACK, PI * 0.5), at), RAIL_COLOR.darkened(0.15))
	_rail_cache = ClayMesh.commit(st)
	return _rail_cache


static func _ease_in_out(x: float) -> float:
	var k: float = clampf(x, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


static func _ease_out_back(x: float) -> float:
	var k: float = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + 2.2 * k * k * k + 1.2 * k * k
