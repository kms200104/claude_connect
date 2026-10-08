class_name CharacterRig
extends Node3D
## 캐릭터 시각 부분. AnimationTree 가 idle ↔ walk ↔ run (속도로 블렌드), 낚시 자세(가중치로 블렌드), 도끼질(원샷)을 섞는다.
## 로컬 플레이어·원격 플레이어·주민·가방 창 미리보기가 같은 리그를 쓰고,
## 게임 로직은 set_look / set_move_speed / set_fishing / set_held / play_chop / set_eye_offset / set_outfit,
## 그리고 set_braking(미끄러지며 멈춤) / play_emote(감정표현) / play_plant(심기) / show_off(잡은 물고기 자랑),
## set_cooking(요리 동작 + 칼·팬·국자) / set_sitting(식당 의자에 앉기) / set_riding(자전거·전기오토바이 타기),
## set_uniform(배달 알바 복장) / play_tada(갈아입고 나와 "짜잔") 만 호출한다.
## 몸·팔·다리 메시는 CharacterModel 이 겉모습(CharacterLook)마다 한 번 만들어 공유한다.

@export_group("References")
@export var tree: AnimationTree
## 애니메이션이 흔드는 몸 전체(골반 기준). 다리와 허리 관절이 여기에 붙는다.
@export var visual: Node3D
## 몸통(스웨터) 메시 — 허리 위(upper)에 있다.
@export var body_mesh: MeshInstance3D
## v0.13 관절: 골반(반바지) 메시, 허리(waist → upper: 몸통·팔), 목(neck → head: 머리·눈·표정·모자).
## upper 와 head 는 관절 안에서 Visual 좌표를 되돌려 놓은 자리라, 메시와 붙는 것들은 예전 Visual 좌표를 그대로 쓴다.
@export var hips_mesh: MeshInstance3D
@export var head_mesh: MeshInstance3D
@export var waist: Node3D
@export var upper: Node3D
@export var neck: Node3D
@export var head: Node3D
@export var arm_left: Node3D
@export var arm_right: Node3D
@export var leg_left: Node3D
@export var leg_right: Node3D
## v0.15 팔꿈치 · 무릎 관절 (아래팔·손은 팔꿈치 아래, 정강이·부츠는 무릎 아래). 없으면 예전처럼 팔·다리 한 덩어리.
@export var elbow_left: Node3D
@export var elbow_right: Node3D
@export var knee_left: Node3D
@export var knee_right: Node3D
## 오른손에 쥐는 도구 (ElbowR 아래).
@export var rod: Node3D
@export var axe: Node3D
## 요리 도구(칼·팬·국자)를 쥐는 자리 (ElbowR 아래). 메시는 set_cooking 이 바꿔 끼운다.
@export var tool: Node3D
## 정점 색을 쓰는 흰 툰 머티리얼 (몸·옷·도구 모두).
@export var clay_material: Material

@export_group("Animation")
## 클수록 idle ↔ walk 전환이 빠르다 (지수 감쇠 계수).
@export_range(0.5, 40.0, 0.5) var speed_smoothing: float = 10.0
## 클수록 낚시 자세에 빨리 들어가고 나온다.
@export_range(0.5, 40.0, 0.5) var fishing_blend_speed: float = 6.0
## 브레이크 자세에 들어가고 나오는 빠르기.
@export_range(0.5, 40.0, 0.5) var brake_blend_speed: float = 18.0

@export_group("Eyes")
## 눈동자가 시선 방향으로 움직이는 최대 거리 (x: 좌우, y: 위아래).
@export var eye_travel: Vector2 = Vector2(0.05, 0.035)

## play_emote 로 할 수 있는 감정표현 (data/emotes/emotes.json 의 id 와 같다).
const EMOTES: PackedStringArray = ["hello", "happy", "laugh", "surprise", "love", "sad", "angry", "think", "clap", "bow", "sleepy"]
## 자랑할 때 손에 든 물건의 자리 (몸통 기준, 턱 아래 앞으로 내민 두 손 위). 머리가 커서 머리 위로 들면 팔이 닿지 않는다.
const SHOW_HOLD_POSITION: Vector3 = Vector3(0.0, 0.0, -0.44)
## set_cooking 으로 할 수 있는 요리 동작 (data/restaurant/recipes.json 의 steps.*.anim).
## 휴대폰을 들고 보는 자세의 오른팔 각도 (gen_character_rig.py PH_AR) · 휴대폰 기울기(위가 앞으로) · 손에서 휴대폰 가운데까지.
const PHONE_ARM: Vector3 = Vector3(1.42, 0.0, -0.66)
const PHONE_TILT: float = -0.55
const PHONE_GRIP: Vector3 = Vector3(0.0, 0.06, 0.04)
## 캐릭터 손에 맞춘 크기 (모형은 17cm).
const PHONE_SCALE: float = 1.75
const COOK_ANIMS: PackedStringArray = ["cook_chop", "cook_stir", "cook_flip", "cook_mix", "cook_plate"]
## set_riding 으로 탈 수 있는 자세 (탈것 데이터 data/vehicles/vehicles.json 의 kind → 애니메이션).
## v0.16 킥보드: kick = 발판 위에서 미끄러져 가기, kick_brake = 뒷발로 흙받이 브레이크 (땅 차기는 play_kick).
## v0.16 주민의 혼잣말 같은 몸짓 (set_activity, 서버 npcs.json activities 의 id → 애니메이션 · 그동안의 표정).
## fish 는 애니메이션 대신 낚싯대를 들고 낚시 자세 (set_fishing).
const ACT_ANIMS: Dictionary[String, String] = {"stretch": "act_stretch", "warmup": "act_warmup", "sun": "act_sun", "sit": "act_sit"}
## 몸짓 · 기분 동안의 얼굴은 face_parts.json expressions 의 emotes 에 "act:<몸짓>" · "mood:<기분>" 으로 적는다.
const RIDE_ANIMS: Dictionary[String, String] = {"bike": "ride_bike", "moto": "ride_moto", "kick": "ride_kick", "kick_brake": "ride_kick_brake"}
## 배달 알바 복장 (v0.15): 시스템이 잠깐 씌우는 파란 헬멧(쓰던 모자 자리를 대신한다)과 "배달의 솔" 가방.
## 머리 · 몸통 좌표는 옷 모형(items.json 의 model)과 같다 (머리 가운데 y 0.4, 앞 = -Z).
const UNIFORM_TEXT: String = "배달의 솔"
const HELMET_BLUE: Color = Color("#2F6FD6")
const HELMET_DARK: Color = Color("#1B4A9A")
## 헬멧은 머리카락(꼭대기 0.95, 옆 0.56, 뒤 0.56)을 덮도록 모자보다 크다. 반구 껍질 · 줄무늬 · 테두리는 _helmet_mesh 가 만든다.
const HELMET_CENTER: Vector3 = Vector3(0.0, 0.6, 0.07)
const HELMET_RADII: Vector3 = Vector3(0.57, 0.4, 0.53)
const HELMET_PARTS: Array = [
	{"s": "sphere", "size": [0.27, 0.03, 0.14], "at": [0, 0.6, -0.5], "c": "#1B4A9A", "rot": [-12, 0, 0]},
	{"s": "sphere", "size": [0.04, 0.022, 0.06], "at": [0.15, 0.968, -0.06], "c": "#1B4A9A", "rot": [25, 0, 0]},
	{"s": "sphere", "size": [0.04, 0.022, 0.06], "at": [-0.15, 0.968, -0.06], "c": "#1B4A9A", "rot": [25, 0, 0]},
	{"s": "sphere", "size": [0.04, 0.022, 0.06], "at": [0.15, 0.957, 0.25], "c": "#1B4A9A", "rot": [-30, 0, 0]},
	{"s": "sphere", "size": [0.04, 0.022, 0.06], "at": [-0.15, 0.957, 0.25], "c": "#1B4A9A", "rot": [-30, 0, 0]},
]
## 가방: 등에 멘 보냉 상자 + 어깨끈. 글씨는 등 쪽(+Z) 면에 붙인다.
const BAG_CENTER: Vector3 = Vector3(0.0, -0.13, 0.37)
const BAG_SIZE: Vector3 = Vector3(0.44, 0.42, 0.26)
const BAG_PARTS: Array = [
	{"s": "rbox", "size": [0.44, 0.42, 0.26], "at": [0, -0.13, 0.37], "c": ["#1E9C98", "#2EC4BF"], "r": 0.18},
	{"s": "rbox", "size": [0.455, 0.06, 0.275], "at": [0, 0.06, 0.37], "c": "#178480", "r": 0.4},
	{"s": "rbox", "size": [0.3, 0.035, 0.03], "at": [0, -0.05, 0.505], "c": "#178480", "r": 0.4},
	{"s": "cap", "size": [0.022], "at": [-0.12, 0.02, 0.25], "to": [-0.125, 0.11, 0.02], "c": "#2B3038"},
	{"s": "cap", "size": [0.022], "at": [-0.125, 0.11, 0.02], "to": [-0.12, -0.2, -0.215], "c": "#2B3038"},
	{"s": "cap", "size": [0.022], "at": [0.12, 0.02, 0.25], "to": [0.125, 0.11, 0.02], "c": "#2B3038"},
	{"s": "cap", "size": [0.022], "at": [0.125, 0.11, 0.02], "to": [0.12, -0.2, -0.215], "c": "#2B3038"},
	{"s": "rbox", "size": [0.2, 0.025, 0.02], "at": [0, -0.1, -0.222], "c": "#2B3038", "r": 0.4},
]

var held_item: String = "rod"
var look: CharacterLook = CharacterLook.for_player(1)

var _move_target: float = 0.0
var _move_value: float = 0.0
var _fishing_target: float = 0.0
var _fishing_value: float = 0.0
var _brake_target: float = 0.0
var _brake_value: float = 0.0
var _show_target: float = 0.0
var _show_value: float = 0.0
var _cook_target: float = 0.0
var _cook_value: float = 0.0
var _sit_target: float = 0.0
var _sit_value: float = 0.0
var _rummage_target: float = 0.0
var _rummage_value: float = 0.0
## 휴대폰을 들고 보는 중 (v0.14).
var _phone_target: float = 0.0
var _phone_value: float = 0.0
var _phone: PhoneProp = null
var _phone_tween: Tween = null
## 탈것에 앉은 자세 (v0.15). 빈 문자열 = 안 탐.
var _ride_kind: String = ""
var _ride_target: float = 0.0
var _ride_value: float = 0.0
var _pedal_rate: float = 0.0
var _tool_id: String = ""
var _tug: float = 0.0
## 자랑할 때 머리 위로 드는 물건 (show_off).
var _hold: Node3D = null
var _held_before_show: String = ""
var _eyes: MeshInstance3D = null
## 감정표현 하는 동안만 보이는 눈썹·눈물·땀방울 (CharacterModel.expression).
var _expression: MeshInstance3D = null
var _expression_id: String = ""
## 감정표현 요청 직후 애니메이션 트리가 아직 원샷을 시작하기 전에 표정을 감추지 않도록 잠깐 기다린다.
var _expression_hold: float = 0.0
var _eye_offset: Vector2 = Vector2.ZERO
var _limbs: Array[MeshInstance3D] = []
## _limbs 와 같은 순서의 마디 이름 (arm · leg · arm_up · arm_low · leg_up · leg_low).
var _limb_parts: PackedStringArray = []
var _outfit: Dictionary[String, MeshInstance3D] = {}
var _outfit_ids: Dictionary[String, String] = {"hat": "", "top": ""}
## 배달 알바 복장을 입은 중.
var _uniform: bool = false
## 지금 하는 몸짓 (빈 문자열 = 없음) · 그 표정.
var _activity: String = ""
var _activity_face: String = ""
## 주민의 그날 기분 얼굴 ("mood:<기분>", 없으면 빈 문자열). 감정표현 · 몸짓 얼굴이 없을 때 보인다.
var _mood_face: String = ""
var _act_target: float = 0.0
var _act_value: float = 0.0
## 탈의소에서 갈아입고 짜잔 하는 동안 손에 든 도구를 감춘다 (OutfitBooth).
var _tools_hidden: bool = false
var _helmet: MeshInstance3D = null
var _bag: Node3D = null
static var _text_material: Material = null
static var _helmet_cache: Dictionary[float, ArrayMesh] = {}


func _ready() -> void:
	# 화질을 바꾸면 Quality 가 이 무리의 리그를 새 촘촘함으로 다시 빚는다.
	add_to_group(&"character_rigs")
	if tree != null:
		tree.active = true
	_build_static_parts()
	_apply_look()
	set_held(held_item)


## 겉모습 바꾸기 (플레이어 자리·주민마다 다르다).
func set_look(new_look: CharacterLook) -> void:
	look = new_look
	if is_node_ready():
		_apply_look()


## 0 = 서 있음, 1 = 걷기, 2 = 달리기 (0~2로 잘라 쓴다). speed_to_blend 로 속도를 바꿔 넣는다.
func set_move_speed(normalized: float) -> void:
	_move_target = clampf(normalized, 0.0, 2.0)


## 실제 속도(m/s) → 이동 애니메이션 값. 걷기 속도까지 0~1, 거기서 달리기 속도까지 1~2.
static func speed_to_blend(speed: float, walk_speed: float, run_speed: float) -> float:
	if speed <= walk_speed:
		return speed / maxf(walk_speed, 0.01)
	return 1.0 + (speed - walk_speed) / maxf(run_speed - walk_speed, 0.01)


## 입은 옷 (아이템 id, 빈 문자열 = 벗음). 윗옷은 스웨터 색을 바꾸고(tint), 무늬·장식은 아이템 데이터의 모양으로 덧붙인다.
func set_outfit(hat_id: String, top_id: String) -> void:
	var changed: bool = _outfit_ids.get("top", "") != top_id
	_set_outfit_part("hat", hat_id)
	_set_outfit_part("top", top_id)
	if changed and is_node_ready():
		_apply_look()


func outfit_item(part: String) -> String:
	return _outfit_ids.get(part, "")


## 배달 알바 복장 (일거리를 받는 동안). 쓰던 모자는 감추고 그 자리에 파란 헬멧, 등에는 "배달의 솔" 가방.
func set_uniform(on: bool) -> void:
	if _uniform == on or visual == null:
		return
	_uniform = on
	if on and _helmet == null:
		_build_uniform()
	if _helmet != null:
		_helmet.visible = on
		_bag.visible = on
	var hat: MeshInstance3D = _outfit.get("hat")
	if hat != null:
		hat.visible = not on and hat.mesh != null


func is_uniformed() -> bool:
	return _uniform


## 손에 든 도구(낚싯대 · 도끼 · 삽 · 요리 도구 · 들고 가는 물건)를 잠깐 감추거나 되돌린다.
func set_tools_hidden(on: bool) -> void:
	if _tools_hidden == on:
		return
	_tools_hidden = on
	if on:
		_hide_tools()
	else:
		set_held(held_item)


func _hide_tools() -> void:
	for holder: Node3D in [rod, axe, tool]:
		if holder != null:
			holder.visible = false


## 갈아입고 나와 "짜잔!" 하는 자세 (한 바퀴 도는 것은 OutfitBooth 가 함께 맞춘다).
func play_tada() -> void:
	if tree == null:
		return
	tree.set("parameters/EmoteSwitch/transition_request", "tada")
	tree.set("parameters/EmoteShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_show_expression("happy")
	EmoteFx.play(_head_root(), "happy", 1.5)


func set_fishing(active: bool) -> void:
	_fishing_target = 1.0 if active else 0.0


## 손에 든 아이템 (rod, axe, 그 밖은 빈손으로 보인다).
## 손에 든 도구 가운데 Tool 자리(손에 고정)에 끼우는 것. 요리 중이면 요리 도구가 먼저다.
const HAND_TOOLS: PackedStringArray = ["parcel", "lunchbox", "envelope"]
## 휘둘러 쓰는 도구 — 도끼 자리(Axe)에 끼워, 사용 동작이 손목(Axe 트랙)을 돌리는 대로 따라간다
## (뜰채: 도끼질 chop 으로 떠 올리기, 삽: dig 가 날을 뒤집어 꽂고 퍼 올린다). 들고 다닐 땐 도끼처럼 위·앞으로 세운다.
const SWING_TOOLS: PackedStringArray = ["fishing_net", "shovel"]
## Tripo 모형이 있는 도구 (텍스처 머티리얼 이름, tools/blender/import_tripo.py).
const TOOL_MODELS: Dictionary[String, String] = {"knife": "tool_knife", "pan": "tool_pan", "ladle": "tool_ladle"}
## Tool 자리 도구를 쥐는 각도 (도): x = 팔 끝에서 앞(-Z)으로 숙이는 각도, y = 자루를 축으로 돌리는 각도.
## 도구 메시는 손에서 +Y 로 뻗으니 180° + x 만큼 X 축으로 돌려 팔이 뻗은 방향(-Y)으로 잇는다.
## 사용 동작에서 팔은 앞으로 0.8~1.3 rad 들리므로, x 를 더하면 칼·팬은 거의 수평(날·바닥이 아래), 국자는 냄비 쪽 아래를 향한다.
## 팔을 내린 대기·걷기에서는 같은 각도라 몸 앞쪽 아래로 든다 (예전엔 126° 고정이라 몸 뒤로 뻗었다).
const TOOL_GRIPS: Dictionary[String, Vector2] = {
	"knife": Vector2(50.0, 0.0), "pan": Vector2(30.0, 0.0), "ladle": Vector2(15.0, 0.0),
	"parcel": Vector2(-10.0, 0.0), "lunchbox": Vector2(-10.0, 0.0), "envelope": Vector2(-10.0, 90.0),
}
## 도끼 자리 도구의 각도 (도): x = 앞뒤로 숙임, y = 자루를 축으로 돌림 (뜰채 입구가 휘두르는 쪽을 보게),
## z = 바깥(캐릭터 오른쪽)으로 눕힘 — 1m 가까운 뜰채·삽을 세워 들면 망·날이 얼굴을 가린다.
const SWING_GRIPS: Dictionary[String, Vector3] = {"fishing_net": Vector3(0.0, 180.0, -25.0), "shovel": Vector3(0.0, 0.0, -25.0)}


func set_held(item_id: String) -> void:
	held_item = item_id
	if _show_target > 0.5:
		_held_before_show = item_id
		return
	var free: bool = _cook_target < 0.5 and _rummage_target < 0.5 and _phone_target < 0.5 and _ride_target < 0.5
	if rod != null:
		rod.visible = item_id == "rod" and free
	if axe != null:
		axe.visible = (item_id == "axe" or item_id in SWING_TOOLS) and free
	_set_swing(item_id if item_id in SWING_TOOLS else "")
	if free:
		_set_tool(item_id if item_id in HAND_TOOLS else "")


func play_chop() -> void:
	if tree != null:
		tree.set("parameters/ChopShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 낚싯대를 휙 던지는 동작 (한 번).
func play_cast() -> void:
	if tree != null:
		tree.set("parameters/CastShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 감정표현 한 번 (EMOTES 중 하나). 모르는 id 는 무시.
func play_emote(emote_id: String) -> void:
	if tree == null or not emote_id in EMOTES:
		return
	tree.set("parameters/EmoteSwitch/transition_request", emote_id)
	tree.set("parameters/EmoteShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_show_expression(emote_id)
	# 머리 둘레 효과 (눈물 · Zzz · 하트 …) — 감정표현 동작 길이만큼.
	var anims: AnimationPlayer = get_node_or_null("AnimationPlayer")
	var length: float = anims.get_animation(emote_id).length if anims != null and anims.has_animation(emote_id) else 1.5
	EmoteFx.play(_head_root(), emote_id, length)


func is_emoting() -> bool:
	return tree != null and bool(tree.get("parameters/EmoteShot/active"))


## 삽질 한 번 (삽을 땅에 꽂고 흙을 퍼 올린다).
func play_dig() -> void:
	if tree != null:
		tree.set("parameters/DigShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 쪼그려 앉아 흙을 토닥이는 동작 (씨앗 심기).
func play_plant() -> void:
	if tree != null:
		tree.set("parameters/PlantShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## 달리다 방향을 확 틀 때: 몸을 젖히고 앞발로 버티는 자세.
func set_braking(active: bool) -> void:
	_brake_target = 1.0 if active else 0.0


func is_braking() -> bool:
	return _brake_target > 0.5


## 요리 동작 (COOK_ANIMS 중 하나, 빈 문자열 = 그만). tool_id = "knife" | "pan" | "ladle" | "" (빈손).
## 요리하는 동안 낚싯대·도끼는 숨긴다.
func set_cooking(anim: String, tool_id: String = "") -> void:
	var active: bool = anim in COOK_ANIMS
	_cook_target = 1.0 if active else 0.0
	if active and tree != null:
		tree.set("parameters/CookSwitch/transition_request", anim)
	_set_tool(tool_id if active else (held_item if held_item in HAND_TOOLS else ""))
	if rod != null:
		rod.visible = not active and held_item == "rod" and _show_target < 0.5 and _phone_target < 0.5
	if axe != null:
		axe.visible = not active and (held_item == "axe" or held_item in SWING_TOOLS) and _show_target < 0.5 and _phone_target < 0.5


func is_cooking() -> bool:
	return _cook_target > 0.5


## 식당 의자에 앉기 (다리를 앞으로 뻗고 몸을 살짝 흔든다).
func set_sitting(active: bool) -> void:
	_sit_target = 1.0 if active else 0.0


## 가방을 여는 동안 주머니를 뒤진다 (고개를 숙여 주머니를 내려다본다). 손에 든 도구는 잠깐 숨긴다.
func set_rummaging(active: bool) -> void:
	_rummage_target = 1.0 if active else 0.0
	var hide: bool = active or _cook_target > 0.5 or _show_target > 0.5 or _phone_target > 0.5
	if rod != null:
		rod.visible = not hide and held_item == "rod"
	if axe != null:
		axe.visible = not hide and (held_item == "axe" or held_item in SWING_TOOLS)
	if tool != null and active:
		tool.visible = false
	elif not active and _cook_target < 0.5 and _phone_target < 0.5:
		_set_tool(held_item if held_item in HAND_TOOLS else "")


func is_rummaging() -> bool:
	return _rummage_target > 0.5


## 탈것에 올라타기 (RIDE_ANIMS 의 kind, 빈 문자열 = 내림). 타는 동안 손에 든 도구는 숨기고 두 손은 핸들을 잡는다.
func set_riding(kind: String) -> void:
	var active: bool = RIDE_ANIMS.has(kind)
	if active == (_ride_target > 0.5) and (not active or kind == _ride_kind):
		return
	_ride_kind = kind if active else ""
	_ride_target = 1.0 if active else 0.0
	if active and tree != null:
		tree.set("parameters/RideSwitch/transition_request", RIDE_ANIMS[kind])
	if active:
		for n: Node3D in [rod, axe, tool]:
			if n != null:
				n.visible = false
	else:
		set_held(held_item)


## 주민 몸짓 (ACT_ANIMS 의 키 또는 "fish", 빈 문자열 = 그만). 천천히 섞여 들어가고 나온다.
func set_activity(activity_id: String) -> void:
	if activity_id == _activity:
		return
	var was_fishing: bool = _activity == "fish"
	_activity = activity_id
	_activity_face = _face_if_any("act:" + activity_id) if not activity_id.is_empty() else ""
	if ACT_ANIMS.has(activity_id) and tree != null:
		tree.set("parameters/ActSwitch/transition_request", ACT_ANIMS[activity_id])
	_act_target = 1.0 if ACT_ANIMS.has(activity_id) else 0.0
	if activity_id == "fish":
		set_held("rod")
		set_fishing(true)
		play_cast()
	elif was_fishing:
		set_fishing(false)
		set_held("")
	if not is_emoting():
		_show_expression(_base_face())


func activity() -> String:
	return _activity


## 기분 얼굴 (주민의 그날 기분: happy · excited · sad · grumpy · sleepy · calm). 표정 데이터가 없는 기분이면 평소 얼굴.
func set_mood_face(mood: String) -> void:
	var face: String = _face_if_any("mood:" + mood) if not mood.is_empty() else ""
	if face == _mood_face:
		return
	_mood_face = face
	if not is_emoting() and (_expression_id.is_empty() or _expression_id.begins_with("mood:")):
		_show_expression(_base_face())


## 감정표현이 없을 때의 얼굴: 몸짓 얼굴 > 기분 얼굴.
func _base_face() -> String:
	return _activity_face if not _activity_face.is_empty() else _mood_face


static func _face_if_any(face_id: String) -> String:
	return face_id if CharacterModel.has_expression(face_id) else ""


func riding_kind() -> String:
	return _ride_kind


## 킥보드: 뒷발로 땅을 한 번 찬다 (kick 애니메이션 0.62초). 타고 있지 않으면 무시.
func play_kick() -> void:
	if tree != null and _ride_kind.begins_with("kick"):
		tree.set("parameters/KickShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_kicking() -> bool:
	return tree != null and bool(tree.get("parameters/KickShot/active"))


## 페달 밟는 빠르기 (초당 바퀴 수). 자전거 바퀴 속도에 맞춰 ride_bike 한 바퀴(1초)를 빠르게·느리게 돌린다. 0 = 멈춤.
func set_pedal_rate(rev_per_sec: float) -> void:
	_pedal_rate = maxf(rev_per_sec, 0.0)


## 휴대폰 꺼내 보기 (v0.14): 손에 든 물건을 주머니에 쏙 넣고(작아지며 사라짐) 휴대폰을 꺼내 오른손에 들고 내려다본다.
## 끄면 휴대폰을 넣고 들고 있던 물건을 다시 꺼낸다.
func set_phone(active: bool) -> void:
	if (_phone_target > 0.5) == active:
		return
	_phone_target = 1.0 if active else 0.0
	var phone: PhoneProp = phone_prop()
	var items: Array[Node3D] = []
	for n: Node3D in [rod, axe, tool]:
		if n != null and n.visible:
			items.append(n)
	if _phone_tween != null:
		_phone_tween.kill()
	_phone_tween = create_tween()
	if active:
		# 들고 있던 것을 넣고 → 휴대폰을 꺼낸다.
		for n: Node3D in items:
			_phone_tween.parallel().tween_property(n, "scale", Vector3.ONE * 0.01, 0.14).set_ease(Tween.EASE_IN)
		_phone_tween.tween_callback(func() -> void:
			for n: Node3D in [rod, axe, tool]:
				if n != null:
					n.visible = false
					n.scale = Vector3.ONE
			if phone != null:
				phone.scale = Vector3.ONE * 0.01
				phone.visible = true
				phone.set_app(-1))
		if phone != null:
			_phone_tween.tween_property(phone, "scale", Vector3.ONE, 0.26).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if phone != null and phone.visible:
			_phone_tween.tween_property(phone, "scale", Vector3.ONE * 0.01, 0.14).set_ease(Tween.EASE_IN)
		_phone_tween.tween_callback(func() -> void:
			if phone != null:
				phone.visible = false
				phone.scale = Vector3.ONE
			set_held(held_item)
			for n: Node3D in [rod, axe, tool]:
				if n != null and n.visible:
					n.scale = Vector3.ONE * 0.01
					create_tween().tween_property(n, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func is_holding_phone() -> bool:
	return _phone_target > 0.5


## 화면을 톡: 왼손으로 누르고 휴대폰 든 손이 살짝 떨린다. 화면도 잠깐 밝아진다.
func phone_tap() -> void:
	if _phone_target < 0.5:
		return
	if tree != null:
		tree.set("parameters/PhoneTapShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if _phone != null:
		_phone.flash()


## 손에 드는 휴대폰 (처음 부를 때 오른손에 만든다).
func phone_prop() -> PhoneProp:
	if _phone != null or arm_right == null:
		return _phone
	# 손은 팔꿈치 아래에 달린다 (휴대폰 자세에서 팔꿈치는 펴져 있어 방향은 어깨와 같다).
	var hand_parent: Node3D = elbow_right if elbow_right != null else arm_right
	var hand_at: Vector3 = CharacterModel.HAND_OFFSET - (elbow_right.position if elbow_right != null else Vector3.ZERO)
	# 손잡이 자리 (자세에 맞춘 방향 · 크기) 안에 휴대폰을 둔다 — 꺼내고 넣을 때는 휴대폰만 커졌다 작아진다.
	var grip: Node3D = Node3D.new()
	grip.name = "PhoneGrip"
	hand_parent.add_child(grip)
	# 들고 보는 자세(phone 애니메이션)의 오른팔 각도에서, 화면이 얼굴 쪽(위 · 뒤)을 보도록 손 기준으로 되돌려 놓는다.
	var hand: Basis = Basis.from_euler(PHONE_ARM)
	var want: Basis = Basis(Vector3.UP, 0.22) * Basis(Vector3.RIGHT, PHONE_TILT)
	var local: Basis = hand.inverse() * want
	grip.basis = local.scaled(Vector3.ONE * PHONE_SCALE)
	# 손바닥이 휴대폰 아래쪽 뒷면을 받친다.
	grip.position = hand_at + local * PHONE_GRIP
	_phone = PhoneProp.new(clay_material)
	_phone.visible = false
	grip.add_child(_phone)
	return _phone


func _set_tool(tool_id: String) -> void:
	if tool == null:
		return
	if tool_id == _tool_id:
		tool.visible = tool.get_node_or_null("Mesh") != null and (tool.get_node("Mesh") as MeshInstance3D).mesh != null and _show_target < 0.5
		return
	_tool_id = tool_id
	var mi: MeshInstance3D = tool.get_node_or_null("Mesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Mesh"
		mi.material_override = clay_material
		tool.add_child(mi)
	var mesh: ArrayMesh = null
	mi.material_override = PartMesh.material_for(TOOL_MODELS.get(tool_id, ""), clay_material)
	match tool_id:
		"knife":
			mesh = CharacterModel.knife()
		"pan":
			mesh = CharacterModel.pan()
		"ladle":
			mesh = CharacterModel.ladle()
		"fishing_net":
			mesh = CharacterModel.landing_net()
		"shovel":
			mesh = CharacterModel.shovel()
		"parcel", "lunchbox", "envelope":
			mesh = CharacterModel.carry_prop(tool_id)
	mi.mesh = mesh
	var grip: Vector2 = TOOL_GRIPS.get(tool_id, Vector2.ZERO)
	mi.basis = Basis(Vector3.RIGHT, deg_to_rad(180.0 + grip.x)) * Basis(Vector3.UP, deg_to_rad(grip.y))
	tool.visible = mesh != null and _show_target < 0.5


## 도끼 자리에 끼우는 휘두르는 도구 (빈 문자열 = 없음). 그동안 도끼 메시는 숨긴다.
func _set_swing(tool_id: String) -> void:
	if axe == null:
		return
	var axe_mesh: MeshInstance3D = axe.get_node_or_null("Mesh")
	if axe_mesh != null:
		axe_mesh.visible = tool_id.is_empty()
	var swing: MeshInstance3D = axe.get_node_or_null("Swing")
	if swing == null:
		swing = MeshInstance3D.new()
		swing.name = "Swing"
		swing.material_override = clay_material
		axe.add_child(swing)
	match tool_id:
		"fishing_net":
			swing.mesh = CharacterModel.landing_net()
		"shovel":
			swing.mesh = CharacterModel.shovel()
		_:
			swing.mesh = null
	var grip: Vector3 = SWING_GRIPS.get(tool_id, Vector3.ZERO)
	swing.basis = Basis(Vector3.BACK, deg_to_rad(grip.z)) * Basis(Vector3.RIGHT, deg_to_rad(grip.x)) * Basis(Vector3.UP, deg_to_rad(grip.y))


## 잡은 물건을 두 손으로 앞으로 쭉 내밀어 들고 자랑한다. mesh 가 null 이면 내려놓는다. 드는 동안 도구는 숨긴다.
func show_off(mesh: Mesh, mesh_scale: float = 1.0, material: Material = null) -> void:
	if visual == null:
		return
	if _hold == null:
		_hold = Node3D.new()
		_hold.name = "ShowHold"
		_upper_root().add_child(_hold)
		_hold.position = SHOW_HOLD_POSITION
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Mesh"
		_hold.add_child(mi)
	var holder: MeshInstance3D = _hold.get_node("Mesh")
	if mesh == null:
		_show_target = 0.0
		_hold.visible = false
		holder.mesh = null
		set_held(_held_before_show)
		return
	if _show_target < 0.5:
		_held_before_show = held_item
	holder.mesh = mesh
	holder.material_override = material if material != null else clay_material
	holder.scale = Vector3.ONE * mesh_scale
	# 물고기 모형은 옆모습이 XY 평면이라 그대로 들면 몸 앞뒤로 옆모습이 보인다 (머리는 캐릭터 오른쪽).
	holder.rotation = Vector3.ZERO
	_hold.visible = true
	_show_target = 1.0
	if rod != null:
		rod.visible = false
	if axe != null:
		axe.visible = false
	if tool != null:
		tool.visible = false


func is_showing_off() -> bool:
	return _show_target > 0.5


func is_chopping() -> bool:
	return tree != null and bool(tree.get("parameters/ChopShot/active"))


## 눈동자 위치 (-1~1). x 양수 = 캐릭터 기준 오른쪽(+X), y 양수 = 위.
## 눈은 머리 겉면에 붙어 있어서, 옮기지 않고 머리 중심을 축으로 굴린다 (얼굴 앞면 기준 eye_travel 만큼 움직인다).
func set_eye_offset(offset: Vector2) -> void:
	if _eyes == null:
		return
	_eye_offset = offset.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	var yaw: float = -_eye_offset.x * eye_travel.x / CharacterModel.HEAD_RADII.z
	var pitch: float = _eye_offset.y * eye_travel.y / CharacterModel.HEAD_RADII.z
	_eyes.rotation = Vector3(pitch, yaw, 0.0)


## 낚싯대를 홱 끌어당기는 작은 반동 (끌어올리기 연타 한 번마다). 애니메이션과 따로 몸 전체를 뒤로 젖힌다.
func reel_tug() -> void:
	_tug = minf(_tug + 0.11, 0.2)


func get_eye_offset() -> Vector2:
	return _eye_offset


func _process(delta: float) -> void:
	if tree == null:
		return
	# 휴대폰 넣기 · 가방 닫기처럼 도구를 다시 꺼내는 동작이 그사이 와도 감춘 채로.
	if _tools_hidden:
		_hide_tools()
	if _expression != null and not _expression_id.is_empty() and _expression_id != _base_face():
		_expression_hold -= delta
		if _expression_hold <= 0.0 and not is_emoting():
			_show_expression(_base_face())
	_move_value = lerpf(_move_value, _move_target, 1.0 - exp(-speed_smoothing * delta))
	_fishing_value = lerpf(_fishing_value, _fishing_target, 1.0 - exp(-fishing_blend_speed * delta))
	tree.set("parameters/Locomotion/blend_position", _move_value)
	tree.set("parameters/FishBlend/blend_amount", _fishing_value)
	_brake_value = move_toward(_brake_value, _brake_target, brake_blend_speed * delta)
	tree.set("parameters/BrakeBlend/blend_amount", _brake_value)
	_ride_value = move_toward(_ride_value, _ride_target, 5.0 * delta)
	tree.set("parameters/RideBlend/blend_amount", _ride_value)
	tree.set("parameters/RideScale/scale", _pedal_rate if _ride_kind == "bike" else 1.0)
	_show_value = lerpf(_show_value, _show_target, 1.0 - exp(-10.0 * delta))
	tree.set("parameters/ShowBlend/blend_amount", _show_value)
	_cook_value = move_toward(_cook_value, _cook_target, 8.0 * delta)
	tree.set("parameters/CookBlend/blend_amount", _cook_value)
	_sit_value = move_toward(_sit_value, _sit_target, 6.0 * delta)
	_act_value = move_toward(_act_value, _act_target, 2.5 * delta)
	tree.set("parameters/ActBlend/blend_amount", _act_value)
	tree.set("parameters/SitBlend/blend_amount", _sit_value)
	_rummage_value = move_toward(_rummage_value, _rummage_target, 5.0 * delta)
	tree.set("parameters/RummageBlend/blend_amount", _rummage_value)
	_phone_value = move_toward(_phone_value, _phone_target, 4.0 * delta)
	tree.set("parameters/PhoneBlend/blend_amount", _phone_value)
	if _phone_value > 0.0:
		# 휴대폰 화면을 내려다본다.
		set_eye_offset(_eye_offset.lerp(Vector2(0.05, -0.85) * _phone_value, 1.0 - exp(-8.0 * delta)))
	if _rummage_value > 0.0:
		# 주머니를 내려다본다 (눈동자를 아래 오른쪽으로).
		set_eye_offset(_eye_offset.lerp(Vector2(0.35, -0.8) * _rummage_value, 1.0 - exp(-8.0 * delta)))
	if _tug > 0.0 or rotation.x != 0.0:
		_tug = move_toward(_tug, 0.0, 0.9 * delta)
		rotation.x = lerpf(rotation.x, _tug, 1.0 - exp(-30.0 * delta))
		if _tug == 0.0 and absf(rotation.x) < 0.002:
			rotation.x = 0.0


## 허리 위 (없으면 Visual — 옛 리그).
func _upper_root() -> Node3D:
	return upper if upper != null else visual


## 목 위 (없으면 Visual — 옛 리그).
func _head_root() -> Node3D:
	return head if head != null else visual


## 겉모습과 상관없는 부분: 눈, 도구, 팔다리 메시 자리.
func _build_static_parts() -> void:
	if visual == null:
		return
	_eyes = MeshInstance3D.new()
	_eyes.name = "Eyes"
	_eyes.mesh = CharacterModel.eyes(look)
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes.material_override = clay_material
	_head_root().add_child(_eyes)
	_eyes.position = CharacterModel.HEAD_CENTER
	_expression = MeshInstance3D.new()
	_expression.name = "Expression"
	_expression.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_expression.material_override = clay_material
	_expression.visible = false
	_head_root().add_child(_expression)
	_add_tool_mesh(rod, CharacterModel.rod())
	_add_tool_mesh(axe, CharacterModel.axe())
	# 관절이 있으면 위 · 아래 마디를 따로, 없으면(옛 리그) 한 덩어리.
	var arms_split: bool = elbow_left != null and elbow_right != null
	var legs_split: bool = knee_left != null and knee_right != null
	for pair: Array in [[arm_left, "arm_up" if arms_split else "arm"], [arm_right, "arm_up" if arms_split else "arm"],
			[leg_left, "leg_up" if legs_split else "leg"], [leg_right, "leg_up" if legs_split else "leg"],
			[elbow_left if arms_split else null, "arm_low"], [elbow_right if arms_split else null, "arm_low"],
			[knee_left if legs_split else null, "leg_low"], [knee_right if legs_split else null, "leg_low"]]:
		var limb: Node3D = pair[0]
		if limb == null:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Mesh"
		mi.material_override = clay_material
		limb.add_child(mi)
		_limbs.append(mi)
		_limb_parts.append(pair[1])


## 감정표현의 표정 (빈 문자열 = 감춘다). 표정이 없는 감정표현도 감춘다.
func _show_expression(emote_id: String) -> void:
	if _expression == null:
		return
	_expression_id = emote_id
	_expression_hold = 0.3
	var mesh: ArrayMesh = CharacterModel.expression(look, emote_id) if not emote_id.is_empty() else null
	_expression.mesh = mesh
	_expression.visible = mesh != null
	# 두 눈을 바꿔 그리는 표정이면 원래 눈을 감춘다.
	if _eyes != null:
		_eyes.visible = mesh == null or not CharacterModel.expression_hides_eyes(emote_id)


func _add_tool_mesh(holder: Node3D, mesh: Mesh) -> void:
	if holder == null:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = clay_material
	holder.add_child(mi)


func _apply_look() -> void:
	var worn: CharacterLook = look
	var top_id: String = _outfit_ids.get("top", "")
	var top: ItemInfo = GameData.item(top_id) if not top_id.is_empty() else null
	if top != null and top.tint.a > 0.0:
		worn = look.duplicate_look()
		worn.top = top.tint
	if _eyes != null:
		_eyes.mesh = CharacterModel.eyes(worn)
	if _expression != null and _expression.visible:
		_expression.mesh = CharacterModel.expression(worn, _expression_id)
	if body_mesh != null:
		body_mesh.mesh = CharacterModel.body(worn)
		body_mesh.material_override = clay_material
	if hips_mesh != null:
		hips_mesh.mesh = CharacterModel.hips(worn)
		hips_mesh.material_override = clay_material
	if head_mesh != null:
		head_mesh.mesh = CharacterModel.head(worn)
		head_mesh.material_override = clay_material
	for i: int in _limbs.size():
		_limbs[i].mesh = CharacterModel.limb(worn, _limb_parts[i])
	# 화질이 바뀌면 손에 든 도구도 그 화질의 모형으로 다시 끼운다.
	if not _tool_id.is_empty():
		var held_tool: String = _tool_id
		_tool_id = ""
		_set_tool(held_tool)


func _set_outfit_part(part: String, item_id: String) -> void:
	if _outfit_ids.get(part, "") == item_id or visual == null:
		return
	_outfit_ids[part] = item_id
	var mi: MeshInstance3D = _outfit.get(part)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Outfit_%s" % part
		mi.material_override = clay_material
		# 모자는 머리(목 관절)를, 상의는 몸통(허리 관절)을 따라 움직인다.
		(_head_root() if part == "hat" else _upper_root()).add_child(mi)
		_outfit[part] = mi
	var info: ItemInfo = GameData.item(item_id) if not item_id.is_empty() else null
	mi.visible = info != null and not info.model.is_empty()
	mi.mesh = PartMesh.get_mesh(item_id, info.model) if mi.visible else null
	# 배달 헬멧을 쓰는 동안은 모자를 감춘다 (헬멧이 그 자리를 대신한다).
	if part == "hat" and _uniform:
		mi.visible = false


func _build_uniform() -> void:
	_helmet = MeshInstance3D.new()
	_helmet.name = "UniformHelmet"
	_helmet.mesh = _helmet_mesh()
	_helmet.material_override = clay_material
	_head_root().add_child(_helmet)
	_bag = Node3D.new()
	_bag.name = "UniformBag"
	_upper_root().add_child(_bag)
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = PartMesh.get_mesh("uniform_bag", BAG_PARTS)
	box.material_override = clay_material
	_bag.add_child(box)
	# 등 쪽 면에 붙인 글씨 (점토 머티리얼을 흰색으로 — 몸처럼 빛·그늘을 받는다).
	var text: TextMesh = TextMesh.new()
	text.text = UNIFORM_TEXT
	text.font_size = 64
	text.depth = 0.008
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: Font = ThemeDB.fallback_font
	var px: Vector2 = font.get_string_size(UNIFORM_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, text.font_size) if font != null else Vector2(320, 64)
	text.pixel_size = minf((BAG_SIZE.x - 0.08) / maxf(px.x, 1.0), 0.1 / maxf(px.y, 1.0))
	var label: MeshInstance3D = MeshInstance3D.new()
	label.name = "Text"
	label.mesh = text
	label.material_override = _uniform_text_material(clay_material)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = BAG_CENTER + Vector3(0.0, 0.025, BAG_SIZE.z * 0.5 + 0.006)
	_bag.add_child(label)


## 헬멧: 머리 · 머리카락을 덮는 반구 껍질 + 흰 줄무늬 (반구라서 얼굴을 가리지 않는다) + 챙 · 테두리 · 숨구멍.
static func _helmet_mesh() -> ArrayMesh:
	if _helmet_cache.has(PartMesh.detail):
		return _helmet_cache[PartMesh.detail]
	var st: SurfaceTool = ClayMesh.begin()
	# 반지름 1 반구 윤곽 (적도 → 꼭대기).
	var dome: PackedVector2Array = PackedVector2Array()
	var rings: int = roundi(8.0 * PartMesh.detail)
	for i: int in rings + 1:
		var a: float = PI * 0.5 * float(i) / float(rings)
		dome.append(Vector2(cos(a), sin(a)))
	var segments: int = roundi(28.0 * PartMesh.detail)
	var shell: Transform3D = Transform3D(Basis.from_scale(HELMET_RADII), HELMET_CENTER)
	ClayMesh.add_lathe(st, dome, segments, shell, HELMET_BLUE)
	ClayMesh.add_lathe(st, dome, segments, Transform3D(Basis.from_scale(Vector3(0.08, HELMET_RADII.y + 0.008, HELMET_RADII.z + 0.008)), HELMET_CENTER), Color("#F4F6FA"))
	# 테두리: 껍질 밑단을 두르는 도톰한 띠 (둘레 방향만 늘린다 — 두께는 m 그대로).
	var rim: PackedVector2Array = PackedVector2Array([Vector2(0.97, -0.035), Vector2(1.035, -0.02), Vector2(1.035, 0.02), Vector2(0.97, 0.035)])
	ClayMesh.add_lathe(st, rim, segments, Transform3D(Basis.from_scale(Vector3(HELMET_RADII.x, 1.0, HELMET_RADII.z)), HELMET_CENTER), HELMET_DARK)
	PartMesh.append(st, HELMET_PARTS)
	var mesh: ArrayMesh = ClayMesh.commit(st)
	_helmet_cache[PartMesh.detail] = mesh
	return mesh


static func _uniform_text_material(clay: Material) -> Material:
	if _text_material == null:
		_text_material = clay.duplicate() if clay != null else StandardMaterial3D.new()
		if _text_material is ShaderMaterial:
			(_text_material as ShaderMaterial).set_shader_parameter("albedo", Color("#FFFFFF"))
	return _text_material
