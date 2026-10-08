class_name VehicleDrive
extends RefCounted
## 탈것 주행 (v18): 조이스틱 방향으로 핸들을 꺾고, 미는 만큼 페달 · 스로틀을 준다. 거의 반대로 밀면 브레이크.
## - 자전거: 밟는 만큼 목표 속도로 다가가고(빠를수록 힘이 덜 든다), 놓으면 구름 저항 · 바람 저항으로 천천히 선다.
## - 전기오토바이: 스로틀을 손목으로 감듯 천천히 열고(throttle_rise) 놓으면 빨리 닫힌다(throttle_fall).
##   모터 힘은 출발이 부드럽고(soft start) 최고 속도 가까이에서 줄며, 놓으면 회생 제동이 살짝 걸린다.
##   가속도 자체도 jerk 만큼씩만 바뀌어 덜컥거리지 않는다. 브레이크도 꾹 누르듯 차오른다.
## 몸(차체)은 도는 만큼 안쪽으로 눕고(lean), 가속하면 앞이 들리고 브레이크면 숙인다(pitch).
## 판정이 아니라 내 화면의 움직임이다 — 서버는 그 탈것의 최고 속도까지만 받아 준다.

const GRAVITY: float = 9.8
## 이 각도보다 크게 뒤로 밀면 브레이크 (도).
const BRAKE_ANGLE: float = 125.0

## 진행 방향 (rad, Node3D.rotation.y 와 같다: 정면 = -Z 를 yaw 만큼 돌린 쪽).
var yaw: float = 0.0
## 앞으로 가는 속도 (m/s, 0 이상).
var speed: float = 0.0
var yaw_rate: float = 0.0
var throttle: float = 0.0
var brake: float = 0.0
## 지금 가속도 (m/s²).
var accel: float = 0.0
var lean: float = 0.0
var pitch: float = 0.0
## 핸들 각도 (rad, + = 왼쪽).
var steer: float = 0.0
var kind: String = "bike"
var stats: VehicleCatalog.Stats = VehicleCatalog.Stats.new()
## 종류 규칙 (vehicles.json kinds): turn_speed · throttle_rise · throttle_fall · brake_rise · jerk.
var rules: Dictionary = {}
## 앞뒤 바퀴 사이 (m, 핸들 각도 계산).
var wheelbase: float = 1.0


func setup(model: VehicleCatalog.Model, new_stats: VehicleCatalog.Stats, kind_rules: Dictionary, start_yaw: float) -> void:
	kind = model.kind
	stats = new_stats
	rules = kind_rules
	wheelbase = maxf(0.4, absf(model.anchor("axle_r").z - model.anchor("axle_f").z))
	yaw = start_yaw
	speed = 0.0
	yaw_rate = 0.0
	throttle = 0.0
	brake = 0.0
	accel = 0.0
	lean = 0.0
	pitch = 0.0
	steer = 0.0


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## 한 걸음: dir = 가고 싶은 방향 (월드 XZ, 길이 1 또는 0), amount = 조이스틱 세기 0~1, wade = 여울 속도 배율.
## 이번 걸음의 속도 벡터를 돌려준다.
func step(dir: Vector3, amount: float, wade: float, delta: float) -> Vector3:
	if delta <= 0.0:
		return forward() * speed
	var want_throttle: float = 0.0
	var want_brake: float = 0.0
	var want_rate: float = 0.0
	var push: float = clampf(amount, 0.0, 1.0)
	if push > 0.05 and dir != Vector3.ZERO:
		var desired: float = atan2(-dir.x, -dir.z)
		var diff: float = angle_difference(yaw, desired)
		if absf(diff) > deg_to_rad(BRAKE_ANGLE) and speed > 1.0:
			want_brake = push
		else:
			# 빠를수록 핸들을 덜 꺾는다 (최고 속도에서 turn_speed 배). 멈춘 채로도 끌듯이 천천히 돈다.
			var k: float = clampf(speed / maxf(stats.top, 0.1), 0.0, 1.0)
			var rate: float = stats.turn * lerpf(1.0, float(rules.get("turn_speed", 0.5)), k) * (0.65 if speed < 0.6 else 1.0)
			want_rate = clampf(diff / delta, -rate, rate)
			# 크게 꺾는 동안은 덜 밀고, 옆으로만 밀면 거의 안 나간다.
			want_throttle = push * clampf(cos(diff) * 1.3, 0.0, 1.0)
	yaw_rate = lerpf(yaw_rate, want_rate, 1.0 - exp(-10.0 * delta))
	yaw = wrapf(yaw + yaw_rate * delta, -PI, PI)
	var top: float = stats.top * clampf(wade, 0.2, 1.0)
	var a_cmd: float = 0.0
	if kind == "moto":
		var rise: float = float(rules.get("throttle_rise", 1.6))
		var fall: float = float(rules.get("throttle_fall", 3.5))
		throttle = move_toward(throttle, want_throttle, (rise if want_throttle > throttle else fall) * delta)
		brake = move_toward(brake, want_brake, (float(rules.get("brake_rise", 4.0)) if want_brake > brake else 6.0) * delta)
		var ratio: float = clampf(speed / maxf(top, 0.1), 0.0, 1.2)
		# 전기 모터: 출발은 부드럽게(soft start), 최고 속도 가까이에서는 힘이 준다.
		var soft: float = 0.55 + 0.45 * clampf(speed / 2.5, 0.0, 1.0)
		var torque: float = clampf(1.0 - pow(ratio, 3.0), 0.0, 1.0)
		a_cmd = stats.accel * throttle * torque * soft
		var target: float = top * throttle
		if speed > target + 0.2:
			# 스로틀을 덜 열면 회생 제동이 걸린다 (멀리 남을수록 세게).
			a_cmd -= stats.regen * clampf((speed - target) / 3.0, 0.25, 1.0)
		a_cmd -= stats.brake * brake
		a_cmd -= stats.coast + 0.004 * speed * speed
		var jerk: float = float(rules.get("jerk", 7.0))
		accel = lerpf(accel, a_cmd, 1.0 - exp(-jerk * delta))
	else:
		throttle = move_toward(throttle, want_throttle, 4.0 * delta)
		brake = move_toward(brake, want_brake, 8.0 * delta)
		var target_speed: float = top * throttle
		if speed < target_speed:
			# 페달: 목표 속도에 가까울수록 힘이 덜 든다.
			a_cmd = stats.accel * clampf((target_speed - speed) / maxf(top * 0.3, 0.5), 0.15, 1.0)
		a_cmd -= stats.brake * brake
		a_cmd -= stats.coast + 0.01 * speed * speed
		accel = lerpf(accel, a_cmd, 1.0 - exp(-12.0 * delta))
	speed = maxf(0.0, speed + accel * delta)
	if speed == 0.0 and accel < 0.0:
		accel = 0.0
	# 눕기: 원운동에 필요한 기울기 atan(v·ω/g), 오토바이가 조금 더 눕는다.
	var max_lean: float = 0.5 if kind == "moto" else 0.36
	var want_lean: float = clampf(atan(speed * yaw_rate / GRAVITY), -max_lean, max_lean)
	lean = lerpf(lean, want_lean, 1.0 - exp(-6.0 * delta))
	pitch = lerpf(pitch, clampf(accel * 0.012, -0.06, 0.05), 1.0 - exp(-8.0 * delta))
	# 핸들: 자전거 운동학 tan(δ) = L·ω / v (느릴 때는 크게).
	steer = clampf(atan(wheelbase * yaw_rate / maxf(speed, 0.8)), -0.5, 0.5)
	return forward() * speed


## 벽 · 나무에 막혀 실제로 간 만큼으로 속도를 줄인다 (부딪치면 선다).
func after_move(real_velocity: Vector3) -> void:
	var along: float = Vector3(real_velocity.x, 0.0, real_velocity.z).dot(forward())
	if along < speed - 0.05:
		speed = maxf(0.0, along)
		accel = minf(accel, 0.0)
