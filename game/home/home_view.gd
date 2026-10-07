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


var _busy: bool = false


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
	cam.far = 500.0
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
