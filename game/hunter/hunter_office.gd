class_name HunterOffice
extends Node3D
## v0.28 헌터 협회 솔바람 출장소 (그림 · 충돌만, 판정은 서버 hunter.js): 동사무소 대피소 앞 남색 컨테이너 사무소.
## 앞면 창구(유리창 · 선반 · 접수 종) · 지붕 위 간판 "헌터 협회" (밤에 빛남) · 협회 깃발 · 모래주머니 · 투광등.
## 원점 = 바닥 가운데, 앞 = +Z (창구 쪽, HunterRules.counter_position).

const CLAY: Material = preload("res://assets/materials/foliage.tres")
const GLOW: Material = preload("res://assets/materials/window_glow.tres")
const SIZE: Vector3 = Vector3(6.0, 2.6, 2.5)
const NAVY: Color = Color("#2A3A5A")
const NAVY_DARK: Color = Color("#1E2A42")
const GOLD: Color = Color("#E8C23A")
const STEEL: Color = Color("#8A9096")
const SAND: Color = Color("#B8A070")


func _ready() -> void:
	name = "HunterOffice"
	var rules: HunterRules = GameData.hunter
	position = rules.office_position
	rotation.y = rules.office_yaw
	_build()


func _build() -> void:
	var b: BoxBatch = BoxBatch.new()
	var s: Vector3 = SIZE
	# 컨테이너 몸통 · 골판 무늬 · 아래 받침.
	b.box(Vector3(0.0, s.y * 0.5 + 0.1, 0.0), s, NAVY)
	for i: int in 13:
		var x: float = -s.x * 0.5 + 0.25 + float(i) * (s.x - 0.5) / 12.0
		b.box(Vector3(x, s.y * 0.5 + 0.1, -s.z * 0.5 - 0.02), Vector3(0.12, s.y - 0.2, 0.04), NAVY_DARK)
	b.box(Vector3(0.0, 0.05, 0.0), Vector3(s.x + 0.2, 0.1, s.z + 0.2), Color("#3A3E44"))
	# 금색 띠 · 협회 표식 (금테 판 안에 마석 모양 마름모 둘).
	var diamond: Basis = Basis(Vector3.BACK, PI * 0.25)
	b.box(Vector3(0.0, 2.2, s.z * 0.5 + 0.02), Vector3(s.x, 0.12, 0.04), GOLD)
	b.box(Vector3(-2.2, 1.35, s.z * 0.5 + 0.03), Vector3(0.8, 0.8, 0.04), GOLD)
	b.box(Vector3(-2.2, 1.35, s.z * 0.5 + 0.05), Vector3(0.66, 0.66, 0.04), NAVY_DARK)
	b.box(Vector3(-2.2, 1.35, s.z * 0.5 + 0.07), Vector3(0.36, 0.36, 0.03), GOLD, diamond)
	b.box(Vector3(-2.2, 1.35, s.z * 0.5 + 0.09), Vector3(0.18, 0.18, 0.03), Color("#5AD8F0"), diamond)
	# 창구: 창틀 · 선반 · 접수 종 · 문.
	b.box(Vector3(0.6, 1.45, s.z * 0.5 + 0.03), Vector3(2.4, 1.1, 0.06), STEEL)
	b.box(Vector3(0.6, 0.95, s.z * 0.5 + 0.22), Vector3(2.5, 0.08, 0.4), Color("#C9A57A"))
	b.box(Vector3(0.6, 0.6, s.z * 0.5 + 0.08), Vector3(2.4, 0.7, 0.06), NAVY_DARK)
	b.box(Vector3(1.2, 1.03, s.z * 0.5 + 0.3), Vector3(0.14, 0.08, 0.14), GOLD)
	b.box(Vector3(2.45, 1.05, s.z * 0.5 + 0.03), Vector3(0.9, 1.9, 0.06), Color("#3A4A6A"))
	b.box(Vector3(2.15, 1.05, s.z * 0.5 + 0.08), Vector3(0.06, 0.2, 0.06), STEEL)
	# 지붕 간판틀 · 깃대.
	b.box(Vector3(0.0, s.y + 0.5, s.z * 0.5 - 0.2), Vector3(4.2, 0.8, 0.12), NAVY_DARK)
	b.box(Vector3(0.0, s.y + 0.5, s.z * 0.5 - 0.13), Vector3(4.0, 0.62, 0.04), Color("#F4F0E8"))
	b.box(Vector3(-s.x * 0.5 - 0.4, 2.2, s.z * 0.5), Vector3(0.08, 4.4, 0.08), STEEL)
	b.box(Vector3(-s.x * 0.5 - 0.4 + 0.45, 3.9, s.z * 0.5), Vector3(0.9, 0.6, 0.03), NAVY)
	b.box(Vector3(-s.x * 0.5 - 0.4 + 0.45, 3.9, s.z * 0.5 + 0.02), Vector3(0.24, 0.24, 0.02), GOLD, Basis(Vector3.BACK, PI * 0.25))
	# 모래주머니 (앞 양쪽).
	for side: float in [-1.0, 1.0]:
		for i: int in 3:
			for j: int in 2 - (i % 2):
				b.box(Vector3(side * (s.x * 0.5 + 0.55) + float(j) * 0.0, 0.18 + float(i) * 0.3, s.z * 0.5 + 0.3 - float(j) * 0.55 - 0.2), Vector3(0.7, 0.28, 0.45), SAND.darkened(0.05 * float(i)))
	# 투광등 기둥.
	b.box(Vector3(s.x * 0.5 + 0.6, 1.6, -0.6), Vector3(0.1, 3.2, 0.1), STEEL)
	b.box(Vector3(s.x * 0.5 + 0.6, 3.2, -0.45), Vector3(0.4, 0.26, 0.3), Color("#3A3E44"))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = b.commit()
	mi.material_override = CLAY
	add_child(mi)
	# 창구 유리 · 투광등 빛 (밤에 빛나는 창 머티리얼).
	var gb: BoxBatch = BoxBatch.new()
	gb.box(Vector3(0.6, 1.5, s.z * 0.5 + 0.065), Vector3(2.2, 0.9, 0.02), Color("#FFE8B0"))
	gb.box(Vector3(s.x * 0.5 + 0.6, 3.07, -0.32), Vector3(0.32, 0.02, 0.22), Color("#FFF4D0"))
	var glass: MeshInstance3D = MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = gb.commit()
	glass.material_override = GLOW
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	# 간판 글자.
	var sign_label: Label3D = Label3D.new()
	sign_label.name = "Sign"
	sign_label.text = "헌터 협회  솔바람 출장소"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.006
	sign_label.modulate = Color("#1E2A42")
	sign_label.outline_size = 0
	sign_label.position = Vector3(0.0, s.y + 0.5, s.z * 0.5 - 0.1)
	sign_label.double_sided = false
	add_child(sign_label)
	var counter: Label3D = Label3D.new()
	counter.name = "CounterLabel"
	counter.text = "마석 매입 · 등급 심사"
	counter.font_size = 40
	counter.pixel_size = 0.005
	counter.modulate = GOLD
	counter.outline_size = 6
	counter.outline_modulate = Color("#1E2A42")
	counter.position = Vector3(0.6, 2.05, s.z * 0.5 + 0.06)
	add_child(counter)
	# 밤 불빛.
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "Floodlight"
	light.light_color = Color("#FFE8B0")
	light.omni_range = 8.0
	light.light_energy = 1.2
	light.shadow_enabled = false
	light.position = Vector3(s.x * 0.5 + 0.3, 2.8, 1.2)
	add_child(light)
	# 몸통 충돌.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(s.x + 1.6, s.y, s.z)
	shape.shape = box
	shape.position = Vector3(0.0, s.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)


func _process(_delta: float) -> void:
	var light: OmniLight3D = get_node_or_null("Floodlight") as OmniLight3D
	if light != null:
		light.visible = GameData.survival.is_night(Net.game_hour()) if Net.state == Net.State.ONLINE else false
