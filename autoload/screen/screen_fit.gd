extends Node
## 화면 방향 (v0.13.4): 휴대폰을 가로로 돌리면 가로 화면으로 논다 (project: handheld orientation = sensor).
## UI 는 세로 기준(1080 × 1920)으로 만들었다. 가로일 때는 논리 높이를 LANDSCAPE_HEIGHT 로 두고 옆으로 넓혀서
## (stretch aspect = expand) 글자 크기가 세로일 때와 비슷하게 보이게 한다. 창들은 changed 를 듣고 자리를 다시 잡는다.

signal changed(landscape: bool)

## 세로 화면의 논리 크기 (project.godot 의 viewport_width/height).
const PORTRAIT_BASE: Vector2i = Vector2i(1080, 1920)
## 가로 화면의 논리 높이 (정사각형 바탕을 옆으로 넓힌다 → 20:9 휴대폰이면 2667 × 1200).
const LANDSCAPE_HEIGHT: int = 1200

var landscape: bool = false


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var root: Window = get_tree().root
	var size: Vector2i = root.size
	var wide: bool = size.x > size.y
	root.content_scale_size = Vector2i(LANDSCAPE_HEIGHT, LANDSCAPE_HEIGHT) if wide else PORTRAIT_BASE
	if wide != landscape:
		landscape = wide
		# 크기가 바뀐 뒤(다음 프레임)에 HUD 자리를 다시 잡는다.
		HudLayout.relayout.call_deferred(get_tree())
		changed.emit(landscape)


## 지금 화면의 논리 크기 (UI 좌표).
func logical_size() -> Vector2:
	return get_tree().root.get_visible_rect().size
