class_name ApartmentKit
extends RefCounted
## 아파트 동 조립 키트 (v0.21 강변도시 · M1): 판상형 동 하나를 상자들로 짓는다 (BoxBatch 두 장 — 점토 · 창).
## 실제 크기: 필로티 PILOTI_HEIGHT, 층 FLOOR_HEIGHT, 앞(+Z 로컬)으로 BALCONY 만큼 나온 발코니.
##   FULL (살 수 있는 리버파크 동): 필로티 돌 기둥 · 유리 공동현관(우편함 · 엘리베이터 문이 비쳐 보임) · 캐노피,
##     층마다 집마다 통창(밤에 빛남) · 발코니 판 · 유리 난간 · 난간 손스침 · 실외기실 루버 · 집 사이 세로 날개벽,
##     뒷면 계단실 · 엘리베이터 코어(층마다 계단참 창) · 뒷창(창살), 옆면 작은 창, 옥상 난간 · 크라운 틀 · 경관조명 · 기계실 · 물탱크 · 피뢰침.
##   SIMPLE (둘레 단지): 몸통 · 층마다 발코니 띠 + 창 띠 · 포인트 세로 띠 · 옥상 크라운 (동 하나 수백 삼각형).

enum Detail { FULL, SIMPLE }

const FLOOR_HEIGHT: float = 2.9
const PILOTI_HEIGHT: float = 5.0
const BALCONY: float = 1.4

const WHITE: Color = Color("#F3F1EC")
const TRIM: Color = Color("#E4E0D8")
const BAND: Color = Color("#CFC9BE")
const CHARCOAL: Color = Color("#3B4046")
const STONE_DARK: Color = Color("#66615B")
const STONE_LIGHT: Color = Color("#D3CEC5")
const RAIL_GLASS: Color = Color("#A9C2CF")
const METAL: Color = Color("#8D959C")
const LOUVER: Color = Color("#B9BDBF")
## 창 머티리얼(building_window)이 유리 색을 정하므로 정점 색은 흰색.
const GLASS: Color = Color("#FFFFFF")
const ELEVATOR: Color = Color("#B7BEC4")
const MAILBOX: Color = Color("#7E8A94")


## 동을 짓는다 (로컬: 가운데 바닥 원점, 앞면 +Z). 지붕 높이(크라운 아래)를 돌려준다.
static func tower(clay: BoxBatch, glass: BoxBatch, w: float, d: float, floors: int, lines: int, detail: Detail,
		sky_lounge: bool = false, wall: Color = WHITE, accent: Color = CHARCOAL) -> float:
	var top: float = PILOTI_HEIGHT + float(floors) * FLOOR_HEIGHT
	var front: float = d * 0.5
	var body_h: float = top - PILOTI_HEIGHT
	if detail == Detail.SIMPLE:
		_simple(clay, glass, w, d, floors, lines, top, wall, accent)
		_crown(clay, glass, w, d, top, accent, false)
		return top
	_piloti(clay, glass, w, d)
	# 몸통 (필로티 위) + 층 띠.
	clay.box(Vector3(0.0, PILOTI_HEIGHT + body_h * 0.5, 0.0), Vector3(w, body_h, d), wall)
	for f: int in range(1, floors):
		clay.box(Vector3(0.0, PILOTI_HEIGHT + f * FLOOR_HEIGHT, 0.0), Vector3(w + 0.06, 0.08, d + 0.06), BAND)
	var uw: float = w / float(lines)
	for f: int in floors:
		var y0: float = PILOTI_HEIGHT + f * FLOOR_HEIGHT
		for line: int in lines:
			var x: float = -w * 0.5 + (float(line) + 0.5) * uw
			_unit_front(clay, glass, x, y0, uw, front)
			_unit_back(clay, glass, x, y0, uw, front)
		# 옆면 작은 창 (방).
		for side: float in [-1.0, 1.0]:
			for k: int in [-1, 1]:
				glass.box(Vector3(side * (w * 0.5 + 0.02), y0 + FLOOR_HEIGHT * 0.55, float(k) * d * 0.22), Vector3(0.05, 1.1, 1.2), GLASS)
	# 집 사이 · 양 끝 세로 날개벽 (짙은 회색, 발코니 끝까지).
	for i: int in lines + 1:
		var fx: float = -w * 0.5 + float(i) * uw
		var thick: float = 0.36 if i == 0 or i == lines else 0.5
		clay.box(Vector3(fx, PILOTI_HEIGHT + body_h * 0.5 + 0.2, front + BALCONY * 0.5), Vector3(thick, body_h + 0.4, BALCONY + 0.1), accent)
	# 뒷면 가운데 계단실 · 엘리베이터 코어 (지붕 위로 기계실까지).
	var core_w: float = minf(5.2, w * 0.26)
	var core_d: float = 2.8
	clay.box(Vector3(0.0, (top + 3.2) * 0.5, -front - core_d * 0.5), Vector3(core_w, top + 3.2, core_d), STONE_LIGHT)
	for f: int in floors:
		var y: float = PILOTI_HEIGHT + f * FLOOR_HEIGHT + FLOOR_HEIGHT * 1.0
		glass.box(Vector3(0.0, y, -front - core_d - 0.02), Vector3(core_w * 0.32, 1.3, 0.05), GLASS)
	clay.box(Vector3(0.0, top + 3.3, -front - core_d * 0.5), Vector3(core_w + 0.3, 0.2, core_d + 0.3), BAND.darkened(0.1))
	_crown(clay, glass, w, d, top, accent, sky_lounge)
	# 옥상: 물탱크 · 실외기 · 피뢰침.
	clay.box(Vector3(w * 0.3, top + 0.9, -d * 0.15), Vector3(2.4, 1.8, 2.0), Color("#C9CED2"))
	for k: int in 4:
		clay.box(Vector3(-w * 0.32 + float(k) * 1.4, top + 0.45, d * 0.2), Vector3(1.0, 0.9, 0.7), Color("#DADDDF"))
	clay.box(Vector3(-w * 0.45, top + 3.0, -d * 0.4), Vector3(0.06, 6.0, 0.06), METAL)
	clay.box(Vector3(w * 0.45, top + 3.0, -d * 0.4), Vector3(0.06, 6.0, 0.06), METAL)
	return top


## 필로티 층: 바닥 돌판 · 돌 기둥 · 가운데 유리 공동현관(안에 우편함 벽 · 엘리베이터 문 둘) · 앞 캐노피 · 천장 띠.
static func _piloti(clay: BoxBatch, glass: BoxBatch, w: float, d: float) -> void:
	var front: float = d * 0.5
	clay.box(Vector3(0.0, 0.06, 0.0), Vector3(w + 1.2, 0.12, d + 1.2), STONE_DARK.lightened(0.2))
	var cols: int = maxi(int(w / 4.5), 3)
	for i: int in cols + 1:
		var cx: float = -w * 0.5 + 0.3 + float(i) * (w - 0.6) / float(cols)
		for cz: float in [-front + 0.3, front - 0.3]:
			if cz > 0.0 and absf(cx) < minf(7.0, w * 0.34) * 0.5 + 0.8:
				continue  # 현관 앞은 비운다.
			clay.box(Vector3(cx, PILOTI_HEIGHT * 0.5, cz), Vector3(0.6, PILOTI_HEIGHT, 0.6), STONE_DARK)
	# 공동현관: 뒤쪽 돌 벽 덩어리 + 앞 유리 (안쪽이 비쳐 보이게 앞 유리 뒤에 우편함 · 엘리베이터 문).
	var lw: float = minf(7.0, w * 0.34)
	var ld: float = d * 0.62
	clay.box(Vector3(0.0, PILOTI_HEIGHT * 0.5, -front + ld * 0.5), Vector3(lw, PILOTI_HEIGHT, ld), STONE_LIGHT)
	var face_z: float = -front + ld
	glass.box(Vector3(0.0, 1.7, face_z + 0.03), Vector3(lw - 0.6, 3.1, 0.05), GLASS)
	clay.box(Vector3(0.0, 3.35, face_z + 0.06), Vector3(lw - 0.4, 0.22, 0.12), CHARCOAL)
	for k: int in [-1, 1]:
		clay.box(Vector3(float(k) * (lw * 0.5 - 0.15), 1.7, face_z + 0.06), Vector3(0.14, 3.4, 0.14), CHARCOAL)
	# 유리 너머: 우편함 벽(왼쪽) · 엘리베이터 문 둘(가운데).
	clay.box(Vector3(-lw * 0.32, 1.3, face_z - 0.7), Vector3(lw * 0.28, 1.6, 0.2), MAILBOX)
	for k: int in [-1, 1]:
		clay.box(Vector3(float(k) * 0.75 + lw * 0.1, 1.15, face_z - 1.6), Vector3(1.1, 2.3, 0.1), ELEVATOR)
		clay.box(Vector3(float(k) * 0.75 + lw * 0.1, 2.55, face_z - 1.55), Vector3(0.5, 0.18, 0.05), Color("#FF8A3A"))
	# 캐노피 (현관 앞).
	clay.box(Vector3(0.0, 3.6, face_z + 1.5), Vector3(lw + 1.2, 0.22, 3.0), CHARCOAL)
	for k: int in [-1, 1]:
		clay.box(Vector3(float(k) * (lw * 0.5 + 0.4), 1.8, face_z + 2.8), Vector3(0.14, 3.6, 0.14), METAL)
	# 천장 띠 (돌 마감).
	clay.box(Vector3(0.0, PILOTI_HEIGHT + 0.12, 0.0), Vector3(w + 0.2, 0.36, d + 0.2), STONE_LIGHT)


## 집 앞면 한 층: 통창(밤에 빛남) · 발코니 판 · 유리 난간 · 손스침 · 끝에 실외기실 루버.
static func _unit_front(clay: BoxBatch, glass: BoxBatch, x: float, y0: float, uw: float, front: float) -> void:
	var span: float = uw - 0.5
	glass.box(Vector3(x - 0.5, y0 + FLOOR_HEIGHT * 0.5, front + 0.03), Vector3(span - 1.8, FLOOR_HEIGHT * 0.7, 0.05), GLASS)
	clay.box(Vector3(x, y0 + 0.1, front + BALCONY * 0.5), Vector3(span, 0.2, BALCONY), TRIM)
	clay.box(Vector3(x, y0 + 0.2 + 0.55, front + BALCONY - 0.04), Vector3(span, 1.1, 0.04), RAIL_GLASS)
	clay.box(Vector3(x, y0 + 0.2 + 1.12, front + BALCONY - 0.04), Vector3(span, 0.06, 0.1), METAL)
	# 실외기실 (집 오른쪽 끝, 가로 루버).
	var ax: float = x + span * 0.5 - 0.75
	clay.box(Vector3(ax, y0 + FLOOR_HEIGHT * 0.45, front + BALCONY * 0.5), Vector3(1.3, FLOOR_HEIGHT * 0.8, BALCONY - 0.1), LOUVER.darkened(0.25))
	for k: int in 5:
		clay.box(Vector3(ax, y0 + 0.4 + float(k) * 0.42, front + BALCONY - 0.02), Vector3(1.3, 0.08, 0.06), LOUVER)


## 집 뒷면 한 층: 부엌 · 방 창 둘 (창살 · 창턱). 계단실 코어 자리는 비운다.
static func _unit_back(clay: BoxBatch, glass: BoxBatch, x: float, y0: float, uw: float, front: float) -> void:
	for k: int in [-1, 1]:
		var wx: float = x + float(k) * uw * 0.24
		# 가운데 코어에 가까운 창은 건너뛴다.
		if absf(wx) < 3.2:
			continue
		glass.box(Vector3(wx, y0 + FLOOR_HEIGHT * 0.55, -front - 0.03), Vector3(1.6, 1.2, 0.05), GLASS)
		clay.box(Vector3(wx, y0 + FLOOR_HEIGHT * 0.55 - 0.66, -front - 0.08), Vector3(1.8, 0.1, 0.16), TRIM)
		for g: int in 3:
			clay.box(Vector3(wx - 0.5 + float(g) * 0.5, y0 + FLOOR_HEIGHT * 0.55, -front - 0.09), Vector3(0.04, 1.2, 0.04), METAL)


## 옥상 크라운: 난간 턱 + 열린 틀(네 기둥 · 위 테두리) + 앞면 세로 루버 + 밤에 빛나는 경관조명 띠 (+ 스카이라운지 유리 상자).
static func _crown(clay: BoxBatch, glass: BoxBatch, w: float, d: float, top: float, accent: Color, sky_lounge: bool) -> void:
	clay.box(Vector3(0.0, top + 0.5, d * 0.5 - 0.1), Vector3(w + 0.1, 1.0, 0.2), STONE_LIGHT)
	clay.box(Vector3(0.0, top + 0.5, -d * 0.5 + 0.1), Vector3(w + 0.1, 1.0, 0.2), STONE_LIGHT)
	for s: float in [-1.0, 1.0]:
		clay.box(Vector3(s * (w * 0.5 - 0.1), top + 0.5, 0.0), Vector3(0.2, 1.0, d), STONE_LIGHT)
	var crown_h: float = FLOOR_HEIGHT * 1.6
	var cw: float = w * 0.84
	var cd: float = d * 0.8
	for cx: float in [-cw * 0.5, cw * 0.5]:
		for cz: float in [-cd * 0.5, cd * 0.5]:
			clay.box(Vector3(cx, top + crown_h * 0.5, cz), Vector3(0.3, crown_h, 0.3), accent)
	for cz: float in [-cd * 0.5, cd * 0.5]:
		clay.box(Vector3(0.0, top + crown_h, cz), Vector3(cw + 0.3, 0.3, 0.3), accent)
	for cx: float in [-cw * 0.5, cw * 0.5]:
		clay.box(Vector3(cx, top + crown_h, 0.0), Vector3(0.3, 0.3, cd), accent)
	for i: int in 9:
		var lx: float = lerpf(-cw * 0.42, cw * 0.42, float(i) / 8.0)
		clay.box(Vector3(lx, top + crown_h * 0.6, cd * 0.5), Vector3(0.1, crown_h * 0.7, 0.1), accent)
	glass.box(Vector3(0.0, top + crown_h - 0.22, cd * 0.5 + 0.18), Vector3(cw, 0.1, 0.06), Color.WHITE)
	if sky_lounge:
		glass.box(Vector3(0.0, top + (crown_h - 0.6) * 0.5 + 0.3, 0.0), Vector3(cw - 0.8, crown_h - 0.6, d * 0.6), GLASS)


## 둘레 단지 동 (가벼운 모양): 필로티 대신 1층 띠, 층마다 발코니 띠 + 창 띠, 가운데 포인트 세로 띠, 뒷면 계단실.
static func _simple(clay: BoxBatch, glass: BoxBatch, w: float, d: float, floors: int, lines: int, top: float, wall: Color, accent: Color) -> void:
	var front: float = d * 0.5
	clay.box(Vector3(0.0, 0.1, 0.0), Vector3(w + 1.0, 0.2, d + 1.0), STONE_LIGHT.darkened(0.1))
	clay.box(Vector3(0.0, PILOTI_HEIGHT * 0.5, 0.0), Vector3(w - 0.4, PILOTI_HEIGHT, d - 0.4), STONE_DARK.lightened(0.15))
	clay.box(Vector3(0.0, PILOTI_HEIGHT + (top - PILOTI_HEIGHT) * 0.5, 0.0), Vector3(w, top - PILOTI_HEIGHT, d), wall)
	var uw: float = w / float(lines)
	for f: int in floors:
		var y0: float = PILOTI_HEIGHT + f * FLOOR_HEIGHT
		clay.box(Vector3(0.0, y0 + 0.1, front + 0.6), Vector3(w - 0.3, 0.2, 1.2), TRIM)
		clay.box(Vector3(0.0, y0 + 0.65, front + 1.18), Vector3(w - 0.3, 0.9, 0.04), RAIL_GLASS)
		glass.box(Vector3(0.0, y0 + FLOOR_HEIGHT * 0.52, front + 0.03), Vector3(w * 0.9, FLOOR_HEIGHT * 0.62, 0.05), GLASS)
		glass.box(Vector3(0.0, y0 + FLOOR_HEIGHT * 0.55, -front - 0.03), Vector3(w * 0.7, 1.0, 0.05), GLASS)
	for i: int in lines + 1:
		clay.box(Vector3(-w * 0.5 + float(i) * uw, PILOTI_HEIGHT + (top - PILOTI_HEIGHT) * 0.5, front + 0.6), Vector3(0.4, top - PILOTI_HEIGHT, 1.3), accent if i == lines / 2 else TRIM.darkened(0.08))
	clay.box(Vector3(0.0, (top + 2.6) * 0.5, -front - 1.2), Vector3(minf(4.6, w * 0.3), top + 2.6, 2.4), STONE_LIGHT)


## 걸어 들어가지 못하는 덩어리 (충돌): 필로티 층의 공동현관 · 뒤 계단실. [가운데, 크기] 목록 (로컬).
static func solid_boxes(w: float, d: float) -> Array[Array]:
	var front: float = d * 0.5
	var lw: float = minf(7.0, w * 0.34)
	var ld: float = d * 0.62
	var out: Array[Array] = []
	out.append([Vector3(0.0, 2.5, -front + ld * 0.5), Vector3(lw, 5.0, ld)])
	out.append([Vector3(0.0, 2.5, -front - 1.4), Vector3(minf(5.2, w * 0.26), 5.0, 2.8)])
	# 기둥 줄 (앞 · 뒤): 기둥 사이로는 지나다닌다 — 기둥마다 작은 상자.
	var cols: int = maxi(int(w / 4.5), 3)
	for i: int in cols + 1:
		var cx: float = -w * 0.5 + 0.3 + float(i) * (w - 0.6) / float(cols)
		for cz: float in [-front + 0.3, front - 0.3]:
			if cz > 0.0 and absf(cx) < lw * 0.5 + 0.8:
				continue
			out.append([Vector3(cx, 2.5, cz), Vector3(0.6, 5.0, 0.6)])
	return out
