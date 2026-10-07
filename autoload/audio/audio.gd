extends Node
## 소리 담당 (전역): 배경음악 두 곡을 엇갈려 바꾸고, 효과음은 미리 만든 플레이어 묶음에서 돌려 쓴다.
## 버스: Music / Sfx / Ambient (Master 아래). 소리 파일 출처는 assets/audio/CREDITS.md
## (대부분 tools/audio/gen_audio.py 로 합성, 발소리와 마을 음악 4곡은 받은 파일).
## 게임 코드는 play_sfx / play_at / play_ui / play_music / set_loop / babble 만 부른다.
## 볼륨 (v0.14.2): 전체 · 음악 · 효과음 · 환경음을 0~100% 로 고르면(설정 앱) 버스 기본 크기에 곱해 적용하고 기억한다.

signal volume_changed

const MUSIC_TITLE: String = "title_theme"
## 마을 음악: 낮 · 밤 · 비 · 이벤트 (SoundDirector 가 고른다).
const MUSIC_VILLAGE: String = "village_theme"
const MUSIC_NIGHT: String = "night_theme"
const MUSIC_RAIN: String = "rain_theme"
const MUSIC_EVENT: String = "event_theme"

const SFX_CONFIRM: String = "ui_confirm"
const SFX_CANCEL: String = "ui_cancel"
const SFX_CLICK: String = "ui_click"
const SFX_OPEN: String = "ui_open"
const SFX_CLOSE: String = "ui_close"

const LOOP_RAIN: String = "rain_loop"
const LOOP_BIRDS: String = "birds_loop"
const LOOP_CRICKETS: String = "crickets_loop"

const SFX_DIR: String = "res://assets/audio/sfx"
const MUSIC_DIR: String = "res://assets/audio/music"
const VOWELS: PackedStringArray = ["a", "e", "i", "o", "u"]

@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_volume_db: float = -9.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var sfx_volume_db: float = -3.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var ambient_volume_db: float = -8.0
## 음악을 바꿀 때 엇갈리는 시간.
@export_range(0.1, 5.0, 0.1, "suffix:s") var music_fade: float = 1.6
## 동시에 날 수 있는 효과음 수.
@export_range(2, 24) var voice_count: int = 10

var _streams: Dictionary[String, AudioStream] = {}
var _music_a: AudioStreamPlayer = null
var _music_b: AudioStreamPlayer = null
var _music_current: String = ""
var _music_tween: Tween = null
var _music_in_tween: Tween = null
## 지금 곡을 내는 플레이어 (_music_a 또는 _music_b).
var _music_active: AudioStreamPlayer = null
var _voices: Array[AudioStreamPlayer] = []
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _next_voice_3d: int = 0
var _loops: Dictionary[String, AudioStreamPlayer] = {}
## 볼륨 (0 ~ 1). 키 = VOLUME_KINDS.
var _volume: Dictionary[String, float] = {"master": 1.0, "music": 1.0, "sfx": 1.0, "ambient": 1.0}

const VOLUME_KINDS: PackedStringArray = ["master", "music", "sfx", "ambient"]
const VOLUME_NAMES: Dictionary[String, String] = {"master": "전체", "music": "배경음악", "sfx": "효과음", "ambient": "환경음"}
const SETTINGS_PATH: String = "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music", music_volume_db)
	_ensure_bus("Sfx", sfx_volume_db)
	_ensure_bus("Ambient", ambient_volume_db)
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for kind: String in VOLUME_KINDS:
			_volume[kind] = clampf(float(cfg.get_value("audio", kind, 1.0)), 0.0, 1.0)
	_apply_volume()
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_music_active = _music_a
	for i: int in voice_count:
		_voices.append(_make_player("Sfx"))
	# 효과음은 처음 날 때 읽느라 프레임이 끊기지 않게 미리 읽어 둔다 (모두 합쳐 1MB 남짓).
	for file: String in ResourceLoader.list_directory(SFX_DIR):
		if file.ends_with(".wav"):
			_sfx(file.get_basename())
	for i: int in 6:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.unit_size = 6.0
		p.max_distance = 30.0
		add_child(p)
		_voices_3d.append(p)


## 볼륨 (0 ~ 1).
func volume(kind: String) -> float:
	return _volume.get(kind, 1.0)


## 볼륨 바꾸기 (0 ~ 1): 바로 적용하고 기억한다.
func set_volume(kind: String, value: float) -> void:
	if not _volume.has(kind):
		return
	_volume[kind] = clampf(value, 0.0, 1.0)
	_apply_volume()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", kind, _volume[kind])
	cfg.save(SETTINGS_PATH)
	volume_changed.emit()


## 버스 크기 = 기본 크기 + 고른 볼륨 (0% 는 끔).
func _apply_volume() -> void:
	var base: Dictionary[String, float] = {"Master": 0.0, "Music": music_volume_db, "Sfx": sfx_volume_db, "Ambient": ambient_volume_db}
	var kinds: Dictionary[String, String] = {"Master": "master", "Music": "music", "Sfx": "sfx", "Ambient": "ambient"}
	for bus: String in base:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var v: float = _volume[kinds[bus]]
		AudioServer.set_bus_mute(index, v <= 0.001)
		# 귀에 고르게 들리도록 제곱 곡선 (50% ≈ -12dB).
		AudioServer.set_bus_volume_db(index, base[bus] + linear_to_db(maxf(v * v, 0.0001)))


## 지금 흐르는 배경음악 이름 (없으면 빈 문자열).
func current_music() -> String:
	return _music_current


## 음악 앱 (v16): 지금 곡이 흐른 시간 · 길이 (초, 곡이 없으면 0).
func music_position() -> float:
	return _music_active.get_playback_position() if _music_active != null and _music_active.playing else 0.0


func music_length() -> float:
	return _music_active.stream.get_length() if _music_active != null and _music_active.stream != null and _music_active.playing else 0.0


## 배경음악 바꾸기 (같은 곡이면 그대로). 빈 문자열이면 끈다. fade 가 0 보다 크면 그만큼 엇갈린다 (기본 music_fade).
func play_music(track: String, fade: float = -1.0) -> void:
	if track == _music_current:
		return
	var seconds: float = fade if fade > 0.0 else music_fade
	_music_current = track
	# 지금 곡을 내보내고 다른 플레이어로 새 곡을 들인다. 바꾸는 도중에 또 바뀌면,
	# 아직 사라지는 중이던 곡은 바로 끄고(겹쳐 남지 않게) 들어오던 곡을 내보낸다.
	var outgoing: AudioStreamPlayer = _music_active
	var incoming: AudioStreamPlayer = _music_b if outgoing == _music_a else _music_a
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if _music_in_tween != null and _music_in_tween.is_valid():
		_music_in_tween.kill()
	incoming.stop()
	if outgoing.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(outgoing, "volume_db", -40.0, seconds)
		_music_tween.tween_callback(outgoing.stop)
	_music_active = incoming
	if track.is_empty():
		return
	var stream: AudioStream = _stream("%s/%s.ogg" % [MUSIC_DIR, track])
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	_music_in_tween = create_tween()
	_music_in_tween.tween_property(incoming, "volume_db", 0.0, seconds)


## 내 주변에서 나는 효과음 (위치 없음). pitch_jitter 만큼 음높이를 흔들어 같은 소리가 덜 반복돼 들린다.
func play_sfx(id: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = 0.06) -> void:
	var stream: AudioStream = _sfx(id)
	if stream == null:
		return
	var p: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


## 월드의 한 지점에서 나는 소리 (상대 플레이어 발소리, 주민 말소리, 나무 쓰러짐).
func play_at(id: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = 0.06) -> void:
	var stream: AudioStream = _sfx(id)
	if stream == null:
		return
	var p: AudioStreamPlayer3D = _voices_3d[_next_voice_3d]
	_next_voice_3d = (_next_voice_3d + 1) % _voices_3d.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.global_position = position
	p.play()


## 버튼·창 소리.
func play_ui(id: String) -> void:
	play_sfx(id, -4.0, 1.0, 0.02)


## 계속 도는 환경음 (비, 새, 풀벌레). 0 이면 멈춘다. 크기는 천천히 따라간다.
func set_loop(id: String, amount: float, delta: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null:
		if amount <= 0.001:
			return
		p = _make_player("Ambient")
		var stream: AudioStream = _sfx(id)
		if stream is AudioStreamWAV:
			var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
			stream = wav
		p.stream = stream
		p.volume_db = -60.0
		_loops[id] = p
	var target: float = linear_to_db(maxf(amount, 0.0001))
	p.volume_db = lerpf(p.volume_db, target, 1.0 - exp(-2.0 * delta))
	if amount > 0.001 and not p.playing:
		p.play()
	elif amount <= 0.001 and p.volume_db < -45.0 and p.playing:
		p.stop()


## 주민 말소리: 글자 하나에 '웅/앵' 한 음절. voice 는 주민마다 다른 음높이 (1 = 보통).
func babble(character: String, voice: float, position: Vector3 = Vector3.INF) -> void:
	if character.strip_edges().is_empty() or character in [".", ",", "!", "?", "…", "~"]:
		return
	var vowel: String = VOWELS[character.unicode_at(0) % VOWELS.size()]
	var pitch: float = voice * (1.0 + 0.08 * sin(float(character.unicode_at(0))))
	if position == Vector3.INF:
		play_sfx("voice_%s" % vowel, -6.0, pitch, 0.04)
	else:
		play_at("voice_%s" % vowel, position, -2.0, pitch, 0.04)


func _sfx(id: String) -> AudioStream:
	return _stream("%s/%s.wav" % [SFX_DIR, id])


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[path] = stream
	return stream


func _make_player(bus: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


static func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)
