class_name LakeDecor
extends MultiMeshInstance3D
## 수면 위 연잎. 수역 데이터(spots.json) 안쪽에 시드로 흩뿌린다 (매번 같은 자리). MultiMesh 하나 = 드로우콜 1.

@export var spot_id: String = "lake"
@export_range(0, 200) var count: int = 18
@export var seed_value: int = 7


func _ready() -> void:
	var info: SpotInfo = GameData.spots.get(spot_id)
	if info == null:
		return
	var pad: CylinderMesh = CylinderMesh.new()
	pad.top_radius = 0.45
	pad.bottom_radius = 0.45
	pad.height = 0.02
	pad.radial_segments = 10
	pad.rings = 1
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pad
	mm.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for i: int in count:
		# 가장자리 쪽에 모이게 (가운데는 찌를 던질 자리).
		var edge: float = rng.randf_range(0.55, 0.92)
		var angle: float = rng.randf() * TAU
		var local: Vector3 = Vector3(cos(angle) * info.half_extent.x * edge, 0.05, sin(angle) * info.half_extent.y * edge)
		if info.has_outline():
			# 윤곽 호수: 물가에서 0.8~2.5m 안쪽 자리를 뽑는다 (바깥 사각형 안에서 시드로 다시 뽑아 물 안쪽만 취함).
			for attempt: int in 30:
				var cand: Vector2 = info.center + Vector2(rng.randf_range(-1.0, 1.0) * info.half_extent.x, rng.randf_range(-1.0, 1.0) * info.half_extent.y)
				var depth: float = -info.signed_distance(cand)
				if depth > 0.8 and depth < 2.5:
					local = Vector3(cand.x - info.center.x, 0.05, cand.y - info.center.y)
					break
		var s: float = rng.randf_range(0.6, 1.2)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), local))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = Vector3(info.center.x, 0.0, info.center.y)
