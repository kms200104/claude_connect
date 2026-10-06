class_name CourierField
extends Node3D
## 식재료 배달 알바 (v13). 서버가 정한 위치(couriers)를 주민처럼 부드럽게 따라 그린다.
## 상자를 들고 상점 문 앞에서 출발해 주문한 사람에게 뛰어가고(walk), 닿으면 꾸벅 인사하며 건네고(hand),
## 빈손으로 상점에 돌아간다(back). 주문이 받아지면 화면 위에 짧게 알린다 (받은 알림은 마을톡이 띄운다).

@export var actor_scene: PackedScene
@export var toast_hud: FishingHud
## 내 캐릭터 (곁에 오면 돌아본다).
@export var player: Node3D

## 서버 걷기 속도(m/s) → 달리기 애니메이션 (배달 알바는 뛰어온다).
const RUN_REFERENCE: float = 1.7

var _actors: Dictionary[String, NpcActor] = {}


func _ready() -> void:
	Net.couriers_updated.connect(_sync)
	Net.welcomed.connect(func(_s: NetPlayerState, _o: Array[NetPlayerState], _r: bool) -> void: _sync(Net.couriers))
	Net.delivery_ordered.connect(_on_ordered)
	Net.delivery_done.connect(_on_done)


func actor(id: String) -> NpcActor:
	return _actors.get(id)


func count() -> int:
	return _actors.size()


func _sync(list: Array[Dictionary]) -> void:
	var seen: Dictionary[String, bool] = {}
	for c: Dictionary in list:
		var id: String = str(c.get("id", ""))
		seen[id] = true
		var a: NpcActor = _actors.get(id)
		if a == null:
			a = _spawn(id)
			if a == null:
				continue
		var state: NetNpcState = NetNpcState.new()
		state.id = "courier"
		state.position = Vector3(float(c.get("x", 0.0)), 0.0, float(c.get("z", 0.0)))
		state.yaw = float(c.get("yaw", 0.0))
		state.mood = "happy"
		a.apply_state(state)
		var ph: String = str(c.get("ph", "walk"))
		if ph != str(a.get_meta("ph", "")):
			_enter_phase(a, ph, int(c.get("to", 0)))
	for id: String in _actors.keys():
		if not seen.has(id):
			var gone: NpcActor = _actors[id]
			_actors.erase(id)
			var t: Tween = gone.create_tween()
			t.tween_property(gone, "scale", Vector3.ONE * 0.01, 0.25)
			t.tween_callback(gone.queue_free)


func _spawn(id: String) -> NpcActor:
	if actor_scene == null or GameData.shop == null or GameData.shop.courier == null:
		return null
	var a: NpcActor = actor_scene.instantiate()
	add_child(a)
	a.setup(GameData.shop.courier)
	a.name = "Courier_%s" % id
	a.walk_speed_reference = RUN_REFERENCE
	a.teleport_distance = 12.0
	a.look_target = player
	if a.name_label != null:
		a.name_label.text = "%s (배달)" % GameData.shop.courier.display_name
	_actors[id] = a
	return a


func _enter_phase(a: NpcActor, ph: String, to: int) -> void:
	a.set_meta("ph", ph)
	match ph:
		"walk":
			a.rig.set_held("parcel")
		"hand":
			# 꾸벅 인사하며 상자를 건넨다.
			a.rig.set_held("")
			a.play_emote("bow", "배달 왔습니다~" if to == Net.my_id else "")
		"back":
			a.rig.set_held("")


func _on_ordered(item_id: String, count: int, eta_s: int, amount: int) -> void:
	if toast_hud != null:
		toast_hud.show_toast("%s %d개 주문 완료 (%s) · 약 %d초 뒤 출발해요" % [GameData.item_name(item_id), count, Money.short(amount), eta_s], true)


func _on_done(_item_id: String, _count: int, _where: String) -> void:
	# 받았다는 알림은 마을톡("배달 완료!" · "식당 창고에 넣어 두었어요")이 띄운다 — 겹치지 않게 여기서는 소리만.
	Audio.play_ui(Audio.SFX_CONFIRM)
