class_name AlertSounds
extends RefCounted
## 재난문자 · 민방위 소리 (v0.20, 실행할 때 합성): 긴급재난문자의 날카로운 두 음 경보, 안전안내문자의 짧은 알림음,
## 민방위 사이렌(높아졌다 낮아지는 파상음, 이음매 없이 돈다). 파일을 늘리지 않으려고 코드로 빚는다.

const RATE: int = 22050

static var _cache: Dictionary[String, AudioStreamWAV] = {}


static func get_stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s: AudioStreamWAV = null
	match kind:
		"emergency":
			s = _emergency()
		"siren":
			s = _siren()
		_:
			s = _chime()
	_cache[kind] = s
	return s


## 긴급재난문자: 853 Hz · 960 Hz 두 음을 0.25초씩 번갈아 (3초).
static func _emergency() -> AudioStreamWAV:
	var n: int = RATE * 3
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var f: float = 853.0 if int(t / 0.25) % 2 == 0 else 960.0
		phase += TAU * f / float(RATE)
		var tone: float = sin(phase) + 0.3 * sin(phase * 3.0)
		var env: float = minf(1.0, t * 40.0) * minf(1.0, (3.0 - t) * 10.0)
		data[i] = tone * env * 0.5
	return _wav(data, false)


## 안전안내문자: 띵-동-띵 짧은 알림 (1.2초).
static func _chime() -> AudioStreamWAV:
	var n: int = int(RATE * 1.2)
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var notes: Array[Array] = [[0.0, 1046.5], [0.18, 1318.5], [0.36, 1568.0]]
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.0
		for nt: Array in notes:
			var u: float = t - float(nt[0])
			if u >= 0.0:
				v += sin(TAU * float(nt[1]) * u) * exp(-u * 5.0)
		data[i] = v * 0.3
	return _wav(data, false)


## 민방위 사이렌: 6초에 한 번 450 → 900 Hz 로 오르내리는 파상음 (돈다).
static func _siren() -> AudioStreamWAV:
	var n: int = RATE * 6
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(n)
	var phase: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var f: float = 675.0 - 225.0 * cos(TAU * t / 6.0)
		phase += TAU * f / float(RATE)
		data[i] = (sin(phase) + 0.25 * sin(phase * 2.0) + 0.12 * sin(phase * 3.0)) * 0.45
	return _wav(data, true)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
