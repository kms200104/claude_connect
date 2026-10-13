class_name PerfHud
extends CanvasLayer
## 성능 표시 (v0.21 도시): 화면 왼쪽 위에 프레임 시간(ms) · FPS · 그린 물체(드로우 콜) · 삼각형 수 · 메모리.
## 설정 "성능 표시 켜기"(Prefs.PERF_HUD) 또는 실행 인자 --perf 로 켠다. 0.5초마다 고친다.
## 프레임 시간은 그 사이 가장 느린 프레임도 같이 보여 준다 (16.6ms 를 넘으면 빨강).

const REFRESH: float = 0.5
const BUDGET_MS: float = 16.6

var _label: Label = null
var _box: PanelContainer = null
var _left: float = 0.0
var _worst: float = 0.0
var _sum: float = 0.0
var _frames: int = 0


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = PanelContainer.new()
	_box.name = "PerfBox"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_box.add_theme_stylebox_override("panel", style)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = Vector2(12.0, 150.0)
	add_child(_box)
	_label = Label.new()
	_label.name = "PerfLabel"
	_label.add_theme_font_size_override("font_size", 22)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_label)
	Prefs.events.changed.connect(func(key: String) -> void:
		if key == Prefs.PERF_HUD:
			_apply())
	_apply()


func _apply() -> void:
	visible = Prefs.perf_hud() or "--perf" in OS.get_cmdline_user_args()
	set_process(visible)


func _process(delta: float) -> void:
	_worst = maxf(_worst, delta)
	_sum += delta
	_frames += 1
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH
	_label.text = text_now(_sum / maxf(float(_frames), 1.0), _worst)
	_label.add_theme_color_override("font_color", Color("#FF6B5E") if _worst * 1000.0 > BUDGET_MS * 1.5 else Color.WHITE)
	_worst = 0.0
	_sum = 0.0
	_frames = 0


## 표시 글 (평균 · 가장 느린 프레임 초).
static func text_now(avg: float, worst: float) -> String:
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var vram: float = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0
	return "%.1fms (최대 %.1f) · %d FPS\n그리기 %d · 물체 %d · 삼각형 %s\nVRAM %dMB · 메모리 %dMB" % [
		avg * 1000.0, worst * 1000.0, roundi(Engine.get_frames_per_second()),
		draws, objects, _short(prims), roundi(vram), roundi(float(OS.get_static_memory_usage()) / 1048576.0)]


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.2fM" % (float(n) / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)
