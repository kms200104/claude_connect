extends Node
## 박자 맞추기 검사: 늘 80ms 늦게 누르면 몸풀기 뒤 16번을 재서 +80ms 쯤으로 보정하고, 적용하면 리듬 요리 보정 값이 된다.
## 사용: godot --headless --path . res://tests/beat_calibration_check.tscn

const LATE_MS: float = 80.0

var _failed: int = 0


func _ready() -> void:
	Prefs.set_value(Prefs.BEAT_OFFSET, 0.0)
	var cal: BeatCalibration = BeatCalibration.open(get_tree())
	await get_tree().process_frame
	var started: float = float(Time.get_ticks_msec())
	var next_beat: int = 1
	while cal.result() == INF and float(Time.get_ticks_msec()) - started < 30000.0:
		var t: float = cal.song_time()
		if t >= float(next_beat) * BeatCalibration.INTERVAL + LATE_MS / 1000.0:
			cal.tap()
			next_beat += 1
			if next_beat == 12:
				await _shot("beatcal_playing")
		await get_tree().process_frame
	_check(cal.result() != INF, "몸풀기 %d번 + %d번 누르면 결과가 나온다 (누른 박자 %d)" % [BeatCalibration.WARMUP, BeatCalibration.NEED, next_beat - 1])
	_check(absf(cal.result() - LATE_MS) < 30.0, "늘 %dms 늦게 누르면 보정 %.0fms" % [roundi(LATE_MS), cal.result()])
	await _shot("beatcal_result")
	var apply: Button = cal.find_child("ApplyButton", true, false) as Button
	_check(apply != null, "결과 창에 '적용하기'")
	if apply != null:
		apply.pressed.emit()
	await get_tree().process_frame
	_check(absf(float(Prefs.get_value(Prefs.BEAT_OFFSET)) - cal.result()) < 1.5 if is_instance_valid(cal) else absf(float(Prefs.get_value(Prefs.BEAT_OFFSET)) - LATE_MS) < 30.0, "적용하면 리듬 요리 보정 값이 된다 (%s)" % str(Prefs.get_value(Prefs.BEAT_OFFSET)))
	_check(get_tree().root.get_node_or_null("BeatCalibrationLayer") == null or get_tree().root.get_node("BeatCalibrationLayer").is_queued_for_deletion(), "적용하면 닫힌다")
	Prefs.set_value(Prefs.BEAT_OFFSET, 0.0)
	print("BEATCAL %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


## --shots=폴더 (화면이 있을 때) 장면을 PNG 로.
func _shot(shot_name: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots=") and DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.15).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [arg.trim_prefix("--shots="), shot_name])


func _check(ok: bool, what: String) -> void:
	print("[beatcal] %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1
