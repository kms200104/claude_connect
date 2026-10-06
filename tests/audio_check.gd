extends Node
## 소리 연결 검사 (렌더러·서버 없이): 발소리 재질(풀·흙·돌·나무·금속·물)과 비 오는 날 물웅덩이, 달리기 소리,
## 마을 음악 고르기(이벤트 > 비 > 밤 > 낮), 음악을 연달아 바꿔도 한 곡만 남는지, 소리 파일이 다 있는지.
## 사용: godot --headless --path . res://tests/audio_check.tscn

var _failed: int = 0


func _ready() -> void:
	# 소리 파일
	for material: String in Footsteps.VARIANTS:
		for i: int in Footsteps.VARIANTS[material]:
			var path: String = "res://assets/audio/sfx/step_%s_%d.wav" % [material, i + 1]
			_check(ResourceLoader.exists(path), "발소리 파일 %s" % path.get_file())
	for track: String in [Audio.MUSIC_VILLAGE, Audio.MUSIC_NIGHT, Audio.MUSIC_RAIN, Audio.MUSIC_EVENT, Audio.MUSIC_TITLE]:
		var music: String = "res://assets/audio/music/%s.ogg" % track
		_check(ResourceLoader.exists(music) and load(music) is AudioStreamOggVorbis, "음악 %s" % music.get_file())

	# 발밑 재질
	Net.weather = NetProtocol.WEATHER_CLEAR
	var dock: Vector2 = GameData.layout.dock_center
	var runway: Dictionary = GameData.airport.extra["runway"]
	var plaza: Vector3 = Vector3(GameData.layout.plaza_center.x, 0.0, GameData.layout.plaza_center.y)
	var museum_plaza: Vector3 = GameData.layout.plazas[0]
	# 흙길: 박물관–동사무소 길 가운데, 풀밭: 그 길 바로 남쪽 빈 땅.
	var dirt: Vector3 = Vector3(-42.0, 0.0, 68.2)
	var grass: Vector3 = Vector3(-43.0, 0.0, 64.0)
	var cases: Array[Array] = [
		[plaza, "stone", "광장 가운데"],
		[Vector3(museum_plaza.x, 0.0, museum_plaza.y), "stone", "박물관 앞 광장"],
		[dirt, "dirt", "흙길"],
		[Vector3(dock.x, 0.0, dock.y), "wood", "선착장"],
		[GameData.shop.inside_spawn, "wood", "상점 안"],
		[Vector3((float(runway.x0) + float(runway.x1)) * 0.5, 0.0, float(runway.z)), "metal", "공항 활주로"],
		[Vector3(0.0, 0.0, 94.0), "dirt", "모래사장"],
		[Vector3(0.0, 0.0, 98.4), "water", "바닷가 젖은 모래"],
		[grass, "grass", "풀밭"],
	]
	for c: Array in cases:
		var got: String = Footsteps.surface_of(c[0])
		_check(got == c[1], "%s → %s (%s)" % [c[2], c[1], got])
	_check(Footsteps.surface_sound(grass, true) == "step_run", "풀밭에서 달리면 달리기 소리")
	_check(Footsteps.surface_sound(plaza, true) == "step_stone", "돌 광장은 달려도 돌 소리")
	Net.weather = NetProtocol.WEATHER_RAIN
	_check(Footsteps.surface_sound(plaza, false) == "step_water", "비 오는 날 광장은 물웅덩이")
	_check(Footsteps.surface_sound(dirt, true) == "step_water", "비 오는 날 흙길은 달려도 철벅")
	_check(Footsteps.surface_sound(grass, false) == "step_grass", "비 와도 풀밭은 풀")
	_check(Footsteps.surface_sound(GameData.shop.inside_spawn, false) == "step_wood", "비 와도 상점 안은 나무")
	Net.weather = NetProtocol.WEATHER_CLEAR

	# 음악 고르기
	_check(SoundDirector.pick_music(12.0, "clear", false) == Audio.MUSIC_VILLAGE, "한낮 맑음 → 낮 곡")
	_check(SoundDirector.pick_music(21.0, "cloudy", false) == Audio.MUSIC_NIGHT, "밤 9시 → 밤 곡")
	_check(SoundDirector.pick_music(3.0, "clear", false) == Audio.MUSIC_NIGHT, "새벽 3시 → 밤 곡")
	_check(SoundDirector.pick_music(6.0, "clear", false) == Audio.MUSIC_VILLAGE, "아침 6시 → 낮 곡")
	_check(SoundDirector.pick_music(12.0, "rain", false) == Audio.MUSIC_RAIN and SoundDirector.pick_music(23.0, "thunder", false) == Audio.MUSIC_RAIN, "비·뇌우 → 비 곡 (밤에도)")
	_check(SoundDirector.pick_music(23.0, "rain", true) == Audio.MUSIC_EVENT, "이벤트가 열려 있으면 이벤트 곡이 먼저")

	# 연달아 바꿔도 한 곡만 남는다
	Audio.play_music(Audio.MUSIC_VILLAGE, 0.3)
	await get_tree().create_timer(0.1).timeout
	Audio.play_music(Audio.MUSIC_NIGHT, 0.3)
	await get_tree().create_timer(0.1).timeout
	Audio.play_music(Audio.MUSIC_RAIN, 0.3)
	await get_tree().create_timer(0.1).timeout
	Audio.play_music(Audio.MUSIC_EVENT, 0.3)
	await get_tree().create_timer(0.8).timeout
	var playing: Array[String] = []
	for p: AudioStreamPlayer in [Audio._music_a, Audio._music_b]:
		if p.playing:
			playing.append(p.stream.resource_path.get_file())
	_check(playing == ["event_theme.ogg"], "빠르게 네 번 바꿔도 마지막 곡 하나만 (%s)" % str(playing))
	_check(Audio.current_music() == Audio.MUSIC_EVENT, "지금 곡 = 이벤트 곡")
	print("AUDIO %s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(0 if _failed == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("[audio] %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failed += 1
