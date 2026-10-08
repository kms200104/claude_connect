class_name HomeView
extends Node
## 창밖 풍경 (v0.12): 마을의 그 집 자리(아파트 동 · 층 · 호)에서 여섯 방향을 한 번씩 찍는다.
## 집 안 창유리(window_view.gdshader)가 "카메라 → 유리" 방향으로 그 사진을 읽어, 진짜 창처럼 바깥이 보인다.
## 같은 월드를 함께 쓰는 작은 SubViewport 하나로 여섯 장을 차례로 찍고(프레임마다 한 장), 다 찍으면 지운다.
## 찍는 동안은 땅 휘기(world_curve)를 끈다 — 아니면 멀리 있는 마을이 지평선 아래로 휘어 하늘만 찍힌다 (집 안은 바로 곁이라 차이가 거의 없다).
## 사진은 큐브맵 대신 텍스처 배열 + 면마다 찍은 카메라 축(dirs · rights · ups)으로 넘긴다 (큐브맵 면 방향 규칙에 기대지 않는다).

## 한 면의 크기 (픽셀). 창은 화면의 일부라 512 면 충분하다.
const FACE_SIZE: int = 512
## 여섯 방향과 그때 카메라의 위쪽.
const DIRS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const UPS: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.UP]


## 찍은 풍경: 사진 여섯 장과 각 사진의 카메라 축 (window_view.gdshader 의 uniform 과 같다).
class View:
	var faces: Texture2DArray = null
	var dirs: PackedVector3Array = PackedVector3Array()
	var rights: PackedVector3Array = PackedVector3Array()
	var ups: PackedVector3Array = PackedVector3Array()


## 창밖 카메라의 시야 (v0.13.9): 섬(±100m) 안만 보고, 그 너머(남쪽 바다 위에 놓인 상점 · 집 안 세트)는 그리지 않는다.
## 끝을 칼같이 자르면 티가 나므로 하늘빛 안개로 서서히 흐린다. 1인칭 실시간 창밖(HomeFirstPerson)도 같은 값을 쓴다.
const VIEW_FAR: float = 140.0
const FOG_BEGIN: float = 55.0
const FOG_END: float = 135.0

var _busy: bool = false


## 마을의 환경 (WorldEnvironment 노드의 것 — World3D.environment 는 비어 있을 수 있다).
static func world_environment(from: Node) -> Environment:
	var world: World3D = from.get_viewport().world_3d if from.is_inside_tree() else null
	if world != null and world.environment != null:
		return world.environment
	for n: Node in from.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we != null and we.environment != null:
			return we.environment
	return null


## 창밖 카메라 전용 환경: 마을 환경(하늘빛 · 밝기)을 그대로 따르고, 거리 안개만 더한다 (메인 화면의 안개는 그대로).
static func view_environment(source: Environment) -> Environment:
	var env: Environment = source.duplicate() if source != null else Environment.new()
	sync_view_environment(env, source)
	return env


## 하늘빛 · 밝기는 시간 · 날씨에 따라 바뀌므로 실시간 창밖은 매 프레임 맞춘다.
static func sync_view_environment(env: Environment, source: Environment) -> void:
	if source != null:
		env.background_mode = source.background_mode
		env.background_color = source.background_color
		env.ambient_light_source = source.ambient_light_source
		env.ambient_light_color = source.ambient_light_color
		env.ambient_light_energy = source.ambient_light_energy
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 1.0
	# 안개색 = 하늘빛이라 하늘에 덮여도 같은 색 (0 으로 두면 이 렌더러에서 하늘이 더 진하게 그려진다).
	env.fog_sky_affect = 1.0
	env.fog_light_color = env.background_color
	env.fog_light_energy = 1.0


## at(월드 좌표)에서 여섯 방향을 찍는다 (찍는 중이거나 실패하면 null). await 로 기다린다 (여섯 프레임쯤).
func capture(at: Vector3) -> View:
	if _busy or not is_inside_tree():
		return null
	_busy = true
	WorldStyle.curve_paused = true
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(FACE_SIZE, FACE_SIZE)
	vp.world_3d = get_viewport().world_3d
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam: Camera3D = Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.2
	cam.far = VIEW_FAR
	cam.environment = view_environment(world_environment(self))
	vp.add_child(cam)
	add_child(vp)
	# 땅 휘기를 끈 것이 다음 프레임(WorldStyle._process)에 반영된 뒤 찍기 시작한다.
	await get_tree().process_frame
	var view: View = View.new()
	var images: Array[Image] = []
	for i: int in DIRS.size():
		var basis: Basis = Basis.looking_at(DIRS[i], UPS[i])
		cam.global_transform = Transform3D(basis, at)
		view.dirs.append(-basis.z)
		view.rights.append(basis.x)
		view.ups.append(basis.y)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			WorldStyle.curve_paused = false
			return null
		var img: Image = vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
	WorldStyle.curve_paused = false
	vp.queue_free()
	view.faces = Texture2DArray.new()
	view.faces.create_from_images(images)
	_busy = false
	return view
