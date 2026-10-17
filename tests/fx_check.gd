extends Node3D
## v0.28.8 전투 효과 검사: 무기마다 휘두르기 · 맞히기 (WeaponFx) 와 직업 기술 그림 (Fx 고리 · 빛줄기 · 반짝이) 을 어두운 바닥 위에 터뜨려 본다.
## 오류 없이 만들어지고, 다 살면 스스로 사라지는지 (남는 노드 0) 확인한다. SHOTS=<폴더> 이면 장면마다 사진을 남긴다 (렌더러 필요).
## 사용: godot --headless --path . res://tests/fx_check.tscn  (사진: SHOTS=dir godot --path . res://tests/fx_check.tscn)

const WEAPONS: PackedStringArray = ["hands", "iron_pipe", "nail_bat", "fire_axe", "axe", "pipe_spear", "torch", "crossbow", "wooden_club", "whirl", "pierce"]
var _shots: String = ""
var _failed: int = 0
var _cam: Camera3D = null


func _ready() -> void:
	_shots = OS.get_environment("SHOTS")
	_stage()
	_run.call_deferred()


func _stage() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_color = Color(0.3, 0.32, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.17, 0.15)
	ground.material_override = gm
	add_child(ground)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 4.2, 5.2), Vector3(0, 0.9, 0), Vector3.UP)
	_cam.current = true


func _check(ok: bool, what: String) -> void:
	print("[fx] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _shot(name: String) -> void:
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_shots, name])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	var dummy: Node3D = Node3D.new()
	add_child(dummy)
	var body: Node3D = Node3D.new()
	dummy.add_child(body)
	dummy.position = Vector3(-0.8, 0, 0.6)
	body.rotation.y = -PI * 0.25
	var target: Vector3 = Vector3(0.6, 1.1, -0.6)
	for wid: String in WEAPONS:
		var s: WeaponFx.Style = WeaponFx.style(wid)
		WeaponFx.swing(self, dummy, body, wid)
		await _wait(0.06)
		WeaponFx.impact(self, target, (target - dummy.position).normalized() * Vector3(1, 0, 1), s, wid == "nail_bat")
		await _wait(0.05)
		await _shot("fx_%s" % wid)
		await _wait(0.25)
	# 직업 기술 그림.
	Fx.slash(self, Vector3.ZERO, 0.0, Color("#E0603A"), 2.4, 360.0, 0.9, 0.34, 0.6)
	Fx.ring_wave(self, Vector3.ZERO, Color("#E0603A"), 2.8, 0.45)
	await _wait(0.12)
	await _shot("fx_skill_whirl")
	Fx.beam(self, Vector3(-2, 1.2, 1), Vector3(3, 1.2, -4), Color("#3AA0E0"), 0.5, 0.4)
	await _wait(0.06)
	await _shot("fx_skill_pierce")
	Fx.ring_wave(self, Vector3.ZERO, Color("#4ABA6A"), 4.0, 0.8, 0.6)
	Fx.sparkle_column(self, Vector3.ZERO, Color("#4ABA6A"), 0.6)
	await _wait(0.35)
	await _shot("fx_skill_mend")
	Fx.dust_ring(self, Vector3.ZERO, 1.4, Color("#8A7A66"))
	Fx.embers(self, Vector3(0, 1, 0), 16)
	await _wait(0.2)
	await _shot("fx_dust_embers")
	# 다 살고 나면 남는 효과가 없다.
	await _wait(2.0)
	var left: int = 0
	for c: Node in get_children():
		if c is CPUParticles3D or (c is MeshInstance3D and c != get_child(1)):
			left += 1
	_check(left == 0, "효과가 다 사라졌다 (남은 %d)" % left)
	_check(WeaponFx.style("nail_bat").hit_sfx == "hit_nails" and WeaponFx.style("fire_axe").word != WeaponFx.style("iron_pipe").word, "무기마다 다른 소리 · 글자")
	for wid: String in WEAPONS:
		var st: WeaponFx.Style = WeaponFx.style(wid)
		for sfx: String in [st.swing_sfx, st.hit_sfx]:
			if not sfx.is_empty():
				_check(ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % sfx), "%s 소리 %s" % [wid, sfx])
	print("FX %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)
