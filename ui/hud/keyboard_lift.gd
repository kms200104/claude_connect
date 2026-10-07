class_name KeyboardLift
extends RefCounted
## 화면 글자판 (v0.14.3): 휴대폰에서 글자 칸을 누르면 글자판이 화면 아래를 덮는다. 창이 글자 칸을 가리지 않게
## 얼마나 올려야 하는지 계산한다 (창마다 _process 에서 lift_for 를 불러 그만큼 올린다).
## 글자판 높이는 DisplayServer.virtual_keyboard_get_height() (기기 픽셀)를 UI 좌표로 바꾼 것.
## 시험·캡처에서는 simulate_height 로 글자판을 흉내 낸다.

## 0 이상이면 이 높이(UI 좌표)의 글자판이 떠 있는 것으로 본다 (테스트용, 기본 -1 = 기기 값).
static var simulate_height: float = -1.0


## 지금 떠 있는 글자판 높이 (UI 좌표, 없으면 0).
static func keyboard_height(viewport: Viewport) -> float:
	if simulate_height >= 0.0:
		return simulate_height
	var kb: float = float(DisplayServer.virtual_keyboard_get_height())
	var window_h: float = float(DisplayServer.window_get_size().y)
	if kb <= 0.0 or window_h <= 0.0:
		return 0.0
	return kb * viewport.get_visible_rect().size.y / window_h


## root 안의 글자 칸에 포커스가 있을 때, 그 칸이 글자판 위(margin 만큼 띄워)에 보이려면 root 를 얼마나 올려야 하는지.
## current = 지금 이미 올려 둔 만큼 (올린 자리에서 재므로 되돌려 계산한다). 포커스가 없거나 글자판이 없으면 0.
static func lift_for(root: Control, current: float, margin: float = 28.0) -> float:
	if root == null or not root.is_inside_tree():
		return 0.0
	var viewport: Viewport = root.get_viewport()
	var focus: Control = viewport.gui_get_focus_owner()
	if focus == null or not (focus is LineEdit or focus is TextEdit) or not focus.is_visible_in_tree():
		return 0.0
	if focus != root and not root.is_ancestor_of(focus):
		return 0.0
	var kb: float = keyboard_height(viewport)
	if kb <= 0.0:
		return 0.0
	var bottom: float = focus.get_global_rect().end.y + current
	var keyboard_top: float = viewport.get_visible_rect().size.y - kb
	return maxf(0.0, bottom + margin - keyboard_top)
