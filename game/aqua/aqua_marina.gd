class_name AquaMarina
extends Node3D
## 성성호수 물놀이 선착장 (v21): 매표소 · 잔교 · 사장님, 바나나 보트(모터보트가 끄는 튜브) · 유람선.
## 놀이배는 서버가 정한 출발 시각(Net.aqua_trips depart)과 노선(AquaRules)으로 모두가 같은 자리에 그린다 — 판정과 상관없는 그림.
## 손님(나 · 친구)은 배의 자리에 붙여 앉힌다. 바나나 보트는 급회전마다 "꽉 잡아!" 단추(HoldPrompt):
##   신호가 뜬 뒤 누를 때까지 걸린 시간(못 누르면 -1)을 서버에 보내고(aqua_hold), 서버가 버팀/빠짐을 정해 모두에게 알린다(aqua_fx).
##   빠진 사람은 물에 첨벙 떨어져 잠깐 둥둥 떠 있다가 다시 튜브로 올라온다.
## 유람선은 안내 자리(stops)를 지날 때 선장님이 말풍선으로 호숫가 이야기를 들려준다.
## 매표소 곁(board_range)에서 상황 버튼 "물놀이" → 표 사는 창 (타기 = aqua_join, 출발 전 내리기 = aqua_leave, 요금 환불).

signal riding_changed(on: bool)

const RIG_SCENE: PackedScene = preload("res://game/player/character_rig.tscn")
const CLAY: Material = preload("res://assets/materials/foliage.tres")
const PIER_TOP: float = 0.16
## 물에 빠져 떠 있는 시간 · 다시 오르는 폴짝 시간 · 탈 때 폴짝 시간.
const FALL_S: float = 2.4
const HOP_S: float = 0.55
## 바나나 보트 · 유람선: 손님 엉덩이 높이 맞춤 (탈 자세의 리그 기준 → 자리).
const MOTO_SEAT: float = 0.45
const MOTO_LIFT: float = 0.12
const SIT_DROP: float = 0.02

@export var player: Player
@export var hud: CanvasLayer
@export var toast_hud: FishingHud
@export var replicator: PlayerReplicator

## 놀이배 하나의 그림.
class Boat:
	var ride: AquaRules.Ride = null
	var root: Node3D = null
	var seats: Array[Node3D] = []
	var driver: CharacterRig = null
	var tug: Node3D = null
	var tug_model: VehicleModel = null
	var rope: MeshInstance3D = null
	var trip_id: String = ""
	var depart: float = 0.0
	var s: float = 0.0
	var speed: float = 0.0
	var next_turn: int = 0
	var next_stop: int = 0
	var bob: float = 0.0
	var swing: float = 0.0

var rules: AquaRules = null
var _boats: Dictionary[String, Boat] = {}
var _operator: CharacterRig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 내가 탄 배 (Net.aqua_trips 의 한 줄) · 자리 · 폴짝.
var _trip: Dictionary = {}
var _seat: int = -1
var _hop_left: float = 0.0
var _hop_from: Vector3 = Vector3.ZERO
var _held_before: String = ""
var _body_rest: float = NAN
## 물에 빠진 사람: id → { until(ms, 내 시계), at(월드) }.
var _falls: Dictionary[int, Dictionary] = {}
## 다시 오르는 폴짝: id → 남은 초 · 오르기 시작하는 물 위 자리.
var _climbs: Dictionary[int, float] = {}
var _climb_from: Dictionary[int, Vector3] = {}

## "꽉 잡아!" 단추 · 지금 기다리는 급회전 · 신호가 뜬 시각(내 시계 ms).
var _prompt: Button = null
var _prompt_turn: int = -1
var _prompt_ms: float = 0.0
var _status: PanelContainer = null
var _status_label: Label = null
var _leave_button: Button = null
var _caption: Label = null
var _caption_left: float = 0.0
var _window: Control = null
var _window_body: VBoxContainer = null
var _note: String = ""


func _ready() -> void:
	rules = GameData.aqua
	_rng.seed = 2117
	if rules == null or rules.rides.is_empty():
		return
	_build_dock()
	for r: AquaRules.Ride in rules.rides:
		_boats[r.id] = _build_boat(r)
	if player != null:
		player.aqua = self
	_build_hud()
	Net.aqua_changed.connect(_on_trips)
	Net.aqua_done.connect(_on_done)
	Net.aqua_fx.connect(_on_fx)
	Net.aqua_ended.connect(_on_ended)
	Net.request_failed.connect(_on_failed)
	_on_trips()


# ---- 상황 버튼 ----

## 매표소 곁인지 (상황 버튼 "물놀이").
func is_near(at: Vector3) -> bool:
	return rules != null and Vector2(at.x, at.z).distance_to(rules.dock) <= rules.board_range - 0.6 and not is_riding()


func is_riding() -> bool:
	return not _trip.is_empty()


func open_window() -> void:
	if _window == null:
		return
	_note = ""
	_fill_window()
	_window.visible = true
	Audio.play_ui(Audio.SFX_OPEN)


func close_window() -> void:
	if _window != null and _window.visible:
		_window.visible = false
		Audio.play_ui(Audio.SFX_CLOSE)


func join(ride_id: String) -> void:
	if player != null and player.is_riding():
		_note = "탈것에서 내린 뒤에 탈 수 있어요 (P 단추)."
		_fill_window()
		return
	Net.request("aqua_join", {"ride": ride_id})


# ---- 놀이배 · 손님 그리기 ----

func _process(delta: float) -> void:
	if rules == null:
		return
	var now: float = Net.server_time_ms()
	for b: Boat in _boats.values():
		_advance(b, now, delta)
	_place_riders(delta)
	_update_prompt()
	_update_status(now)
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0 and _caption != null:
			_caption.visible = false
	if _operator != null and player != null:
		var to: Vector3 = player.global_position - _operator.global_position
		if to.length() < 9.0:
			_operator.rotation.y = lerp_angle(_operator.rotation.y, atan2(to.x, to.z), 1.0 - exp(-3.0 * delta))


func _advance(b: Boat, now: float, delta: float) -> void:
	var tau: float = (now - b.depart) / 1000.0 if not b.trip_id.is_empty() else 0.0
	var s: float = AquaRules.distance_at(b.ride, tau)
	b.speed = lerpf(b.speed, absf(s - b.s) / maxf(delta, 0.001), 1.0 - exp(-5.0 * delta)) if delta > 0.0 else 0.0
	b.s = s
	b.bob += delta
	var p: Vector2 = AquaRules.point_at(b.ride, s)
	var yaw: float = AquaRules.yaw_at(b.ride, s, 2.5)
	var calm: float = 1.0 - clampf(b.speed / 4.0, 0.0, 0.8)
	var level: float = WaterRules.LAKE_LEVEL
	if b.ride.is_banana():
		# 급회전에서 바나나가 바깥으로 휙 쓸려 나가며 기운다 (모터보트보다 크게).
		var turn: float = wrapf(AquaRules.yaw_at(b.ride, s + 3.0, 1.5) - AquaRules.yaw_at(b.ride, s - 3.0, 1.5), -PI, PI)
		b.swing = lerpf(b.swing, clampf(turn * b.speed * 0.14, -0.9, 0.9), 1.0 - exp(-4.0 * delta))
		var side: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		b.root.global_position = Vector3(p.x, level + sin(b.bob * 2.1) * 0.03, p.y) - side * b.swing * 1.1
		b.root.rotation = Vector3(sin(b.bob * 1.7) * 0.02 * calm, yaw, b.swing * 0.35)
		var q: Vector2 = AquaRules.point_at(b.ride, s + b.ride.tow)
		var tug_yaw: float = AquaRules.yaw_at(b.ride, s + b.ride.tow, 2.5)
		b.tug.global_position = Vector3(q.x, level + sin(b.bob * 1.6) * 0.025, q.y)
		b.tug.rotation = Vector3(-clampf(b.speed * 0.012, 0.0, 0.09), tug_yaw, 0.0)
		if b.tug_model != null:
			b.tug_model.animate(b.speed, 0.0, delta)
		_stretch_rope(b)
	else:
		b.root.global_position = Vector3(p.x, level + sin(b.bob * 1.3) * 0.035 * calm, p.y)
		b.root.rotation = Vector3(sin(b.bob * 0.9) * 0.012, yaw, sin(b.bob * 1.1) * 0.02 * calm)
	# 물보라 (달리는 동안).
	if b.speed > 1.5 and Engine.get_process_frames() % 6 == 0 and is_inside_tree():
		var stern: Node3D = b.tug if b.tug != null else b.root
		var back: Vector3 = stern.global_basis * Vector3(0.0, 0.0, 1.6 if b.tug != null else 3.6)
		Puff.burst(self, stern.global_position + back + Vector3(0.0, 0.1, 0.0), Color(0.92, 0.97, 1.0, 0.8), 2, 0.3, 0.35, 0.12, 0.5)
	_narrate(b, now)


## 끄는 줄: 모터보트 고물 → 바나나 코.
func _stretch_rope(b: Boat) -> void:
	var a: Vector3 = b.tug.global_transform * Vector3(0.0, 0.5, 1.3)
	var c: Vector3 = b.root.global_transform * AquaBoats.banana_nose()
	var mid: Vector3 = (a + c) * 0.5 + Vector3(0.0, -0.12, 0.0)
	var length: float = a.distance_to(c)
	if length < 0.01:
		return
	b.rope.global_transform = Transform3D(Basis.looking_at(c - a, Vector3.UP).scaled(Vector3(1.0, 1.0, length)), mid)


## 출발 · 끝 · 안내 방송 · 급회전 신호 차례를 그 배의 놀이 시각에 맞춘다.
func _narrate(b: Boat, now: float) -> void:
	if b.trip_id.is_empty():
		return
	var tau: float = (now - b.depart) / 1000.0
	if not b.ride.is_banana():
		while b.next_stop < b.ride.stops.size() and b.s >= float(b.ride.stops[b.next_stop]["s"]) and tau > 0.0:
			var line: String = str(b.ride.stops[b.next_stop]["line"])
			b.next_stop += 1
			# 탄 손님은 화면 자막으로, 물가에서 보는 사람은 선장님 말풍선으로.
			if _mine(b):
				_show_caption("선장님: " + line)
			elif b.driver != null:
				EmoteBubble.say(b.driver, line, 2.6, 5.0)
		return
	if b.next_turn < b.ride.turns.size():
		var turn: Dictionary = b.ride.turns[b.next_turn]
		var prompt_at: float = AquaRules.time_at(b.ride, float(turn["s"])) - b.ride.prompt_s
		if tau >= prompt_at:
			var k: int = b.next_turn
			b.next_turn += 1
			if b.driver != null:
				EmoteBubble.say(b.driver, "꽉 잡아요! %s으로 꺾어요!" % ("오른쪽" if int(turn["dir"]) > 0 else "왼쪽"), 2.4, 1.4)
			if _mine(b):
				_show_prompt(k)


func _mine(b: Boat) -> bool:
	return not _trip.is_empty() and str(_trip.get("id", "")) == b.trip_id


## 손님 자리의 월드 위치 · 방향 (탈 자세 기준 리그 뿌리).
func _seat_xform(b: Boat, seat: int) -> Transform3D:
	var node: Node3D = b.seats[clampi(seat, 0, b.seats.size() - 1)]
	var xf: Transform3D = node.global_transform
	if b.ride.is_banana():
		xf.origin -= xf.basis.y * MOTO_SEAT
	else:
		xf.origin -= xf.basis.y * SIT_DROP
	return xf


func _place_riders(delta: float) -> void:
	var now_ms: float = Time.get_ticks_msec()
	for trip: Dictionary in Net.aqua_trips:
		var b: Boat = _boats.get(str(trip.get("ride", "")))
		if b == null:
			continue
		for r: Variant in trip.get("riders", []):
			if not r is Dictionary:
				continue
			var id: int = int(r.get("id", -1))
			var xf: Transform3D = _seat_xform(b, int(r.get("seat", 0)))
			var pos: Vector3 = xf.origin
			var falling: bool = false
			if _falls.has(id):
				var f: Dictionary = _falls[id]
				if now_ms >= float(f["until"]):
					_falls.erase(id)
					_climbs[id] = HOP_S
					_splash(f["at"], 4)
				else:
					falling = true
					var bob: float = sin(now_ms / 260.0) * 0.05
					pos = (f["at"] as Vector3) + Vector3(0.0, -0.95 + bob, 0.0)
			if not falling and _climbs.has(id):
				var left: float = maxf(_climbs[id] - delta, 0.0)
				_climbs[id] = left
				var from: Vector3 = _climb_from.get(id, xf.origin)
				var t: float = 1.0 - left / HOP_S
				pos = from.lerp(xf.origin, t) + Vector3(0.0, sin(t * PI) * 0.9, 0.0)
				if left <= 0.0:
					_climbs.erase(id)
			var yaw: float = xf.basis.get_euler().y
			if id == Net.my_id:
				_pin_me(b, pos, yaw, falling, delta)
			else:
				_pin_remote(id, b, pos, yaw, falling)


func _pin_me(b: Boat, pos: Vector3, yaw: float, falling: bool, delta: float) -> void:
	if player == null or _trip.is_empty():
		return
	if _hop_left > 0.0:
		_hop_left = maxf(_hop_left - delta, 0.0)
		var t: float = 1.0 - _hop_left / HOP_S
		pos = _hop_from.lerp(pos, t) + Vector3(0.0, sin(t * PI) * 1.1, 0.0)
	player.global_position = pos
	# 걷지는 않지만 배의 빠르기를 넘겨 둔다 (카메라가 내다보는 만큼 앞을 비춘다 — 0 이면 달리는 배를 뒤따라오기만 한다).
	var ahead: Vector3 = -b.root.global_basis.z if b.tug == null else -b.tug.global_basis.z
	player.velocity = Vector3.ZERO if falling else Vector3(ahead.x, 0.0, ahead.z).normalized() * b.speed
	_pose(player.rig, b, falling)
	if player.body != null:
		if is_nan(_body_rest):
			_body_rest = player.body_rest_height()
		var lift: float = MOTO_LIFT if b.ride.is_banana() and not falling else 0.0
		player.body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, _body_rest + lift, 0.0))


func _pin_remote(id: int, b: Boat, pos: Vector3, yaw: float, falling: bool) -> void:
	if replicator == null:
		return
	for rp: RemotePlayer in replicator.remote_nodes():
		if rp.player_id == id:
			rp.pin(pos, yaw, MOTO_LIFT if b.ride.is_banana() and not falling else 0.0)
			_pose(rp.rig, b, falling)
			return


func _pose(rig: CharacterRig, b: Boat, falling: bool) -> void:
	if rig == null:
		return
	if falling:
		rig.set_riding("")
		rig.set_sitting(false)
	elif b.ride.is_banana():
		rig.set_sitting(false)
		rig.set_riding("moto")
	else:
		rig.set_riding("")
		rig.set_sitting(true)


## Player 가 걷기 대신 부른다 (타는 동안). 자리 · 빠르기는 _place_riders 가 정한다.
func drive_player(_delta: float) -> void:
	pass


func _splash(at: Vector3, n: int) -> void:
	if is_inside_tree():
		Puff.burst(self, Vector3(at.x, WaterRules.LAKE_LEVEL + 0.15, at.z), Color(0.9, 0.96, 1.0, 0.85), n, 0.5, 0.8, 0.13, 0.6)


# ---- 서버 소식 ----

func _on_trips() -> void:
	var mine: Dictionary = Net.my_aqua_trip()
	for b: Boat in _boats.values():
		var trip: Dictionary = {}
		for t: Dictionary in Net.aqua_trips:
			if str(t.get("ride", "")) == b.ride.id:
				trip = t
		var id: String = str(trip.get("id", ""))
		if id != b.trip_id:
			b.trip_id = id
			b.depart = float(trip.get("depart", 0.0))
			b.next_turn = 0
			b.next_stop = 0
	# 내린 친구는 다시 걷는 모습으로.
	if replicator != null:
		for rp: RemotePlayer in replicator.remote_nodes():
			if rp.is_pinned() and Net.aqua_trip_of(rp.player_id).is_empty():
				rp.unpin()
				if rp.rig != null:
					rp.rig.set_riding("")
					rp.rig.set_sitting(false)
	if mine.is_empty() and not _trip.is_empty():
		_leave_boat()
	elif not mine.is_empty() and _trip.is_empty():
		_board(mine)
	elif not mine.is_empty():
		_trip = mine
	if _window != null and _window.visible:
		_fill_window()


func _board(trip: Dictionary) -> void:
	_trip = trip
	for r: Variant in trip.get("riders", []):
		if r is Dictionary and int(r.get("id", -1)) == Net.my_id:
			_seat = int(r.get("seat", 0))
	_hop_left = HOP_S
	if player != null:
		_hop_from = player.global_position
		player.set_input_lock(&"aqua", true)
		if player.rig != null:
			_held_before = player.rig.held_item
			player.rig.set_held("")
	close_window()
	_prompt_turn = -1
	riding_changed.emit(true)


func _leave_boat() -> void:
	_trip = {}
	_seat = -1
	_hide_prompt()
	_falls.erase(Net.my_id)
	_climbs.erase(Net.my_id)
	if player == null:
		return
	player.set_input_lock(&"aqua", false)
	if player.rig != null:
		player.rig.set_riding("")
		player.rig.set_sitting(false)
		player.rig.set_held(_held_before)
	if player.body != null and not is_nan(_body_rest):
		player.body.transform = Transform3D(Basis(Vector3.UP, player.body.rotation.y), Vector3(0.0, _body_rest, 0.0))
	player.global_position = Vector3(rules.land.x, player.global_position.y if player.global_position.y > 0.0 else 0.1, rules.land.y)
	player.velocity = Vector3.ZERO
	riding_changed.emit(false)


func _on_done(result: Dictionary) -> void:
	match str(result.get("kind", "")):
		"join":
			var r: AquaRules.Ride = rules.ride(str(result.get("ride", "")))
			_toast("%s 탑승! %s 뒤 출발해요." % [r.name if r != null else "놀이배", _secs(float(result.get("depart", 0.0)) - Net.server_time_ms())], true)
			Audio.play_ui(Audio.SFX_CONFIRM)
		"leave":
			_toast("내렸어요. 요금을 돌려받았어요.", true)


func _on_fx(trip_id: String, id: int, _turn: int, fell: bool) -> void:
	var b: Boat = null
	for x: Boat in _boats.values():
		if x.trip_id == trip_id:
			b = x
	if b == null:
		return
	var node: Node3D = _rider_node(id)
	if not fell:
		if node != null:
			EmoteBubble.pop(node, "happy", 2.2, 0.9)
		if id == Net.my_id:
			Audio.play_sfx("emote_up", -6.0)
		return
	var seat: int = 0
	var trip: Dictionary = Net.aqua_trip_of(id)
	for r: Variant in trip.get("riders", []):
		if r is Dictionary and int(r.get("id", -1)) == id:
			seat = int(r.get("seat", 0))
	var xf: Transform3D = _seat_xform(b, seat)
	# 튜브 바깥쪽(기우는 쪽)으로 날아가 떨어진다.
	var out: Vector3 = xf.basis * Vector3(signf(b.swing) if absf(b.swing) > 0.05 else 1.0, 0.0, 0.0)
	var at: Vector3 = xf.origin + out * 1.4
	_falls[id] = {"until": Time.get_ticks_msec() + FALL_S * 1000.0, "at": at}
	_climb_from[id] = at + Vector3(0.0, -0.9, 0.0)
	_splash(at, 7)
	Audio.play_sfx("fish_plop", -2.0, 0.8)
	if node != null:
		EmoteBubble.pop(node, "surprise", 1.6, 1.2)
	if b.driver != null:
		EmoteBubble.say(b.driver, "어이쿠, 첨벙! 다시 올라와요~", 2.4, 1.8)
	if id == Net.my_id:
		Prefs.vibrate(120, 0.8)
		_toast("첨벙! 물에 빠졌어요 — 다시 올라가요.", false)


func _on_ended(result: Dictionary) -> void:
	var ride: AquaRules.Ride = rules.ride(str(result.get("ride", "")))
	if ride == null:
		return
	if ride.is_banana():
		var held: int = int(result.get("held", 0))
		var turns: int = int(result.get("turns", 0))
		var line: String = "바나나 보트: 급회전 %d번 중 %d번 버텼어요!" % [turns, held]
		if held >= turns and turns > 0:
			line += " 한 번도 안 빠졌어요 👏"
		_toast(line, held * 2 >= turns)
	else:
		_toast("유람선 한 바퀴 끝! 즐거우셨나요?", true)
	Audio.play_sfx("fanfare_small", -8.0)
	if not _trip.is_empty():
		_leave_boat()


func _on_failed(kind: String, code: String) -> void:
	if not kind.begins_with("aqua_"):
		return
	match code:
		NetProtocol.ERR_NOT_NEAR_DOCK:
			_note = "매표소 곁에서 탈 수 있어요."
		NetProtocol.ERR_AQUA_BUSY:
			_note = "지금은 그 배가 돌고 있거나 자리가 다 찼어요. 조금 뒤에 다시 와요."
		NetProtocol.ERR_NOT_ENOUGH_SOL:
			_note = "솔이 모자라요."
		NetProtocol.ERR_CANT_RIDE:
			_note = "지금은 탈 수 없어요 (탈것 · 낚시 · 실내)."
		_:
			_note = "탈 수 없어요 (%s)." % code
	if _window != null and _window.visible:
		_fill_window()
	else:
		_toast(_note, false)


func _rider_node(id: int) -> Node3D:
	if id == Net.my_id:
		return player
	if replicator != null:
		for rp: RemotePlayer in replicator.remote_nodes():
			if rp.player_id == id:
				return rp
	return null


func _toast(text: String, good: bool) -> void:
	if toast_hud != null:
		toast_hud.show_toast(text, good)


static func _secs(ms: float) -> String:
	return "%d초" % maxi(0, ceili(ms / 1000.0))


# ---- "꽉 잡아!" ----

func _show_prompt(turn: int) -> void:
	if _prompt == null:
		return
	if _prompt_turn >= 0:
		_send_hold(-1.0)
	_prompt_turn = turn
	_prompt_ms = Time.get_ticks_msec()
	_prompt.visible = true
	_prompt.scale = Vector2(0.6, 0.6)
	var tw: Tween = _prompt.create_tween()
	tw.tween_property(_prompt, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Prefs.vibrate(30, 0.5)
	Audio.play_sfx("emote_hey", -4.0)


func _update_prompt() -> void:
	if _prompt == null or _prompt_turn < 0:
		return
	var b: Boat = _boats.get(str(_trip.get("ride", "")))
	var window: float = float(b.ride.window_ms) if b != null else 1500.0
	if Time.get_ticks_msec() - _prompt_ms > window:
		_send_hold(-1.0)
	_prompt.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _prompt_turn >= 0 and event.is_action_pressed(&"ui_accept"):
		_press_hold()
		get_viewport().set_input_as_handled()


func _press_hold() -> void:
	if _prompt_turn < 0:
		return
	_send_hold(Time.get_ticks_msec() - _prompt_ms)


func _send_hold(ms: float) -> void:
	if _prompt_turn < 0:
		return
	Net.request("aqua_hold", {"trip": str(_trip.get("id", "")), "turn": _prompt_turn, "ms": roundi(ms) if ms >= 0.0 else -1})
	_hide_prompt()


func _hide_prompt() -> void:
	_prompt_turn = -1
	if _prompt != null:
		_prompt.visible = false


func _draw_prompt() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, _prompt.size)
	var c: Vector2 = r.get_center()
	var rad: float = minf(r.size.x, r.size.y) * 0.5
	_prompt.draw_circle(c, rad, Color(1.0, 0.84, 0.25, 0.95))
	_prompt.draw_arc(c, rad - 3.0, 0.0, TAU, 48, Color(0.42, 0.26, 0.1), 6.0, true)
	var b: Boat = _boats.get(str(_trip.get("ride", "")))
	var window: float = float(b.ride.window_ms) if b != null else 1500.0
	var left: float = clampf(1.0 - (Time.get_ticks_msec() - _prompt_ms) / window, 0.0, 1.0)
	_prompt.draw_arc(c, rad + 12.0, -PI * 0.5, -PI * 0.5 + TAU * left, 48, Color(1.0, 1.0, 1.0, 0.9), 12.0, true)
	var font: Font = _prompt.get_theme_default_font()
	for row: Array in [["꽉 잡아!", 46, -6.0], ["누르세요", 26, 34.0]]:
		var w: float = font.get_string_size(str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(row[1])).x
		_prompt.draw_string(font, c + Vector2(-w * 0.5, float(row[2])), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(row[1]), Color(0.36, 0.2, 0.08))


# ---- HUD ----

func _build_hud() -> void:
	if hud == null:
		return
	_prompt = Button.new()
	_prompt.name = "AquaHold"
	_prompt.flat = true
	_prompt.focus_mode = Control.FOCUS_NONE
	_prompt.add_to_group(&"blocks_joystick")
	_prompt.custom_minimum_size = Vector2(300, 300)
	_prompt.size = Vector2(300, 300)
	_prompt.pivot_offset = Vector2(150, 150)
	# 상황 버튼 자리 (오른손 엄지) 위에 크게.
	_prompt.anchor_left = 1.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -390.0
	_prompt.offset_right = -90.0
	_prompt.offset_top = -640.0
	_prompt.offset_bottom = -340.0
	_prompt.visible = false
	_prompt.button_down.connect(_press_hold)
	_prompt.draw.connect(_draw_prompt)
	hud.add_child.call_deferred(_prompt)
	_status = PanelContainer.new()
	_status.name = "AquaStatus"
	_status.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.98, 0.92, 0.94), Color(0.36, 0.3, 0.28), 26, 4, 14))
	_status.visible = false
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_status.add_child(row)
	_status_label = _label("", 28, Color(0.32, 0.2, 0.12))
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_label)
	_leave_button = _button("내리기", func() -> void: Net.request("aqua_leave"))
	_leave_button.name = "AquaLeave"
	row.add_child(_leave_button)
	HudLayout.center_top(_status, 640.0, 290.0)
	hud.add_child.call_deferred(_status)
	_caption = _label("", 30, Color.WHITE)
	_caption.name = "AquaCaption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_outline_color", Color(0.15, 0.12, 0.1))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.visible = false
	HudLayout.center_top(_caption, 900.0, 400.0)
	hud.add_child.call_deferred(_caption)
	_build_window()


func _update_status(now: float) -> void:
	if _status == null:
		return
	if _trip.is_empty():
		_status.visible = false
		return
	var r: AquaRules.Ride = rules.ride(str(_trip.get("ride", "")))
	if r == null:
		return
	var depart: float = float(_trip.get("depart", 0.0))
	_status.visible = true
	if now < depart:
		_status_label.text = "%s · 곧 출발 (%s)" % [r.name, _secs(depart - now)]
		_leave_button.visible = true
	else:
		var left: float = depart + AquaRules.duration(r) * 1000.0 - now
		var b: Boat = _boats.get(r.id)
		if r.is_banana() and b != null:
			_status_label.text = "%s · 급회전 %d / %d · %s 남음" % [r.name, mini(b.next_turn, r.turns.size()), r.turns.size(), _secs(left)]
		else:
			_status_label.text = "%s · %s 남음" % [r.name, _secs(left)]
		_leave_button.visible = false


func _show_caption(text: String) -> void:
	if _caption == null:
		return
	_caption.text = text
	_caption.visible = true
	_caption_left = 5.5


func _build_window() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.name = "AquaWindow"
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close_window())
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 0.98, 0.93), Color(0.36, 0.3, 0.28), 36, 5, 26))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -470.0
	panel.offset_right = 470.0
	panel.offset_top = -560.0
	panel.offset_bottom = 560.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(panel)
	_window_body = VBoxContainer.new()
	_window_body.add_theme_constant_override("separation", 18)
	panel.add_child(_window_body)
	_window = dim
	hud.add_child.call_deferred(dim)


func _fill_window() -> void:
	if _window_body == null:
		return
	for c: Node in _window_body.get_children():
		c.queue_free()
	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = _label("성성호 물놀이 선착장", 40, Color(0.32, 0.2, 0.12))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close: Button = _button("닫기", close_window)
	close.name = "AquaClose"
	head.add_child(close)
	_window_body.add_child(head)
	_window_body.add_child(_label("사장님: 호수에서 신나게 놀아 봐요! 친구랑 같이 타면 더 재밌어요. 출발 전에는 언제든 내릴 수 있어요.", 24, Color(0.52, 0.42, 0.32)))
	if not _note.is_empty():
		_window_body.add_child(_label(_note, 26, Color("#E8604A")))
	var now: float = Net.server_time_ms()
	for r: AquaRules.Ride in rules.rides:
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", EventHud._box(Color(1.0, 1.0, 1.0, 0.9), Color(0.8, 0.7, 0.58), 26, 3, 18))
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		card.add_child(col)
		col.add_child(_label(r.name, 34, Color(0.32, 0.2, 0.12)))
		col.add_child(_label(r.desc, 24, Color(0.52, 0.42, 0.32)))
		col.add_child(_label("요금 %s · %d명까지 · 한 바퀴 약 %s" % [Money.sol(r.fee), r.seats, _secs(AquaRules.duration(r) * 1000.0)], 24, Color(0.36, 0.3, 0.28)))
		var trip: Dictionary = {}
		for t: Dictionary in Net.aqua_trips:
			if str(t.get("ride", "")) == r.id:
				trip = t
		var can: bool = true
		var state: String = "선착장에서 쉬는 중 — 타면 %s 뒤 출발해요." % _secs(float(rules.board_ms))
		if not trip.is_empty():
			var depart: float = float(trip.get("depart", 0.0))
			var n: int = (trip.get("riders", []) as Array).size()
			if now < depart and n < r.seats:
				state = "손님 받는 중 %d/%d · %s 뒤 출발" % [n, r.seats, _secs(depart - now)]
			else:
				can = false
				state = "운항 중 · 약 %s 뒤 돌아와요" % _secs(depart + AquaRules.duration(r) * 1000.0 - now)
		col.add_child(_label(state, 24, Color("#5AAE5A") if can else Color("#E8604A")))
		var go: Button = _button("타기 (%s)" % Money.sol(r.fee), func() -> void: join(r.id))
		go.name = "AquaJoin_%s" % r.id
		go.disabled = not can or Net.sol < r.fee
		col.add_child(go)
		_window_body.add_child(card)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_stylebox_override("normal", EventHud._box(Color("#FFD27A"), Color(0.36, 0.3, 0.28), 24, 4, 12))
	b.add_theme_stylebox_override("hover", EventHud._box(Color("#FFE0A0"), Color(0.36, 0.3, 0.28), 24, 4, 12))
	b.add_theme_stylebox_override("pressed", EventHud._box(Color("#F2B85A"), Color(0.36, 0.3, 0.28), 24, 4, 12))
	b.add_theme_stylebox_override("disabled", EventHud._box(Color(0.85, 0.82, 0.78), Color(0.6, 0.55, 0.5), 24, 4, 12))
	b.add_theme_color_override("font_color", Color(0.32, 0.2, 0.12))
	b.pressed.connect(func() -> void:
		Audio.play_ui(Audio.SFX_CLICK)
		on_press.call())
	return b


# ---- 짓기 ----

func _build_dock() -> void:
	var pier: MeshInstance3D = MeshInstance3D.new()
	pier.name = "AquaPier"
	pier.mesh = AquaBoats.pier_mesh(rules.pier_root, rules.pier_tip, rules.pier_width, PIER_TOP, _rng)
	pier.material_override = CLAY
	pier.visibility_range_end = 80.0
	add_child(pier)
	var booth: MeshInstance3D = MeshInstance3D.new()
	booth.name = "AquaBooth"
	booth.mesh = AquaBoats.booth_mesh()
	booth.material_override = CLAY
	booth.visibility_range_end = 80.0
	add_child(booth)
	var face: Vector2 = rules.pier_root - rules.booth
	booth.position = Vector3(rules.booth.x, 0.0, rules.booth.y)
	booth.rotation.y = atan2(-face.x, -face.y)
	var sign_label: Label3D = Label3D.new()
	sign_label.text = "성성호 물놀이"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.0035
	sign_label.modulate = Color(0.2, 0.32, 0.55)
	sign_label.outline_size = 0
	sign_label.position = Vector3(0.0, 2.3, -0.06)
	sign_label.rotation.y = PI
	booth.add_child(sign_label)
	var info: NpcInfo = GameData.npcs.get(rules.operator)
	_operator = RIG_SCENE.instantiate()
	_operator.name = "AquaOperator"
	add_child(_operator)
	_operator.position = Vector3(rules.operator_at.x, 0.0, rules.operator_at.y)
	if info != null:
		_operator.set_look(info.look)
	_operator.set_held("")


func _build_boat(r: AquaRules.Ride) -> Boat:
	var b: Boat = Boat.new()
	b.ride = r
	b.root = Node3D.new()
	b.root.name = "Aqua_%s" % r.id
	add_child(b.root)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = AquaBoats.banana_mesh() if r.is_banana() else AquaBoats.cruise_mesh()
	mi.material_override = CLAY
	b.root.add_child(mi)
	var seats: Array[Dictionary] = AquaBoats.banana_seats() if r.is_banana() else AquaBoats.cruise_seats()
	for i: int in seats.size():
		var seat: Node3D = Node3D.new()
		seat.name = "Seat%d" % i
		seat.position = seats[i]["at"]
		seat.rotation.y = float(seats[i]["yaw"])
		b.root.add_child(seat)
		b.seats.append(seat)
	var info: NpcInfo = GameData.npcs.get(r.driver)
	b.driver = RIG_SCENE.instantiate()
	b.driver.name = "Driver"
	if info != null:
		b.driver.set_look(info.look)
	b.driver.set_held("")
	if r.is_banana():
		# 끄는 모터보트 (차고의 모터보트 모형) + 운전하는 주민 + 줄.
		b.tug = Node3D.new()
		b.tug.name = "Aqua_tug"
		add_child(b.tug)
		b.tug_model = VehicleModel.new()
		b.tug_model.build("boat_motor", {})
		b.tug_model.lights_on = false
		b.tug.add_child(b.tug_model)
		var tug_info: VehicleCatalog.Model = GameData.garage.model("boat_motor")
		b.tug.add_child(b.driver)
		b.driver.set_riding(tug_info.pose if tug_info != null else "boat")
		b.driver.position = Vector3(0.0, (tug_info.lift if tug_info != null else 0.09), 0.0)
		b.rope = MeshInstance3D.new()
		b.rope.name = "Rope"
		var rope_mesh: BoxMesh = BoxMesh.new()
		rope_mesh.size = Vector3(0.035, 0.035, 1.0)
		b.rope.mesh = rope_mesh
		b.rope.material_override = CLAY
		add_child(b.rope)
	else:
		# 선장님은 조타실 안 (창 너머로 보인다).
		b.root.add_child(b.driver)
		b.driver.position = Vector3(0.0, AquaBoats.DECK_Y, -2.45)
	return b
