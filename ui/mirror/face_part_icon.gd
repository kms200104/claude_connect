class_name FacePartIcon
extends Control
## 거울 창의 부품 그림: 눈·코·입은 피부색 동그라미 위에 data 의 도형을 그대로 그리고(FaceShapes),
## 피부·눈동자·머리 색은 색 동그라미, 머리 모양은 미리 찍어 둔 그림(assets/ui/face/hair_<id>.png).

const HAIR_ICON_DIR: String = "res://assets/ui/face"
## 항목별로 보여 줄 얼굴 부분: (가운데 y, 반쪽 너비) — 얼굴 좌표(m).
const VIEW: Dictionary[String, Vector2] = {"eyes": Vector2(0.385, 0.27), "nose": Vector2(0.35, 0.1), "mouth": Vector2(0.215, 0.09)}

var key: String = "eyes"
var part_id: String = ""
var look: CharacterLook = CharacterLook.new()
var _texture: Texture2D = null


func setup(new_key: String, new_part: String, new_look: CharacterLook) -> void:
	key = new_key
	part_id = new_part
	look = new_look
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture = null
	if key == "hair":
		var path: String = "%s/hair_%s.png" % [HAIR_ICON_DIR, part_id]
		if ResourceLoader.exists(path):
			_texture = load(path)
	queue_redraw()


func _draw() -> void:
	var catalog: FaceCatalog = GameData.face
	if catalog == null:
		return
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46
	var part: FaceCatalog.Part = catalog.part(key, part_id)
	match key:
		"skin":
			var skin: Color = part.colors.get("skin", Color.WHITE) if part != null else look.skin
			draw_circle(center, radius, skin)
			for side: float in [-1.0, 1.0]:
				draw_circle(center + Vector2(radius * 0.5 * side, radius * 0.2), radius * 0.17, part.colors.get("cheeks", look.cheeks) if part != null else look.cheeks)
			draw_arc(center, radius, 0.0, TAU, 40, Color(0, 0, 0, 0.15), 3.0, true)
		"eye_color", "hair_color":
			var color: Color = part.colors.get("color", Color.GRAY) if part != null else Color.GRAY
			draw_circle(center, radius, color)
			draw_circle(center + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.22, Color(1, 1, 1, 0.35))
			draw_arc(center, radius, 0.0, TAU, 40, Color(0, 0, 0, 0.18), 3.0, true)
		"hair":
			if _texture != null:
				var side: float = minf(size.x, size.y)
				draw_texture_rect(_texture, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		_:
			if part == null:
				return
			draw_circle(center, radius, look.skin)
			var view: Vector2 = VIEW.get(key, Vector2(0.3, 0.2))
			var scale_px: float = radius * 0.92 / view.y
			var palette: Dictionary[String, Color] = CharacterModel.face_palette(look)
			var anchors: Array[Vector2] = []
			var mirrors: Array[bool] = []
			if key == "eyes":
				var eye: Vector2 = catalog.anchors.get("eye", Vector2(0.17, 0.385))
				anchors = [Vector2(eye.x, eye.y), Vector2(-eye.x, eye.y)]
				mirrors = [false, true]
			else:
				anchors = [catalog.anchors.get(key, Vector2(0.0, view.x))]
				mirrors = [false]
			for i: int in anchors.size():
				for entry: Dictionary in FaceShapes.triangles(part.layers, palette):
					var tris: PackedVector2Array = entry["tris"]
					var color: Color = entry["color"]
					for t: int in range(0, tris.size(), 3):
						var pts: PackedVector2Array = PackedVector2Array()
						for k: int in 3:
							var q: Vector2 = tris[t + k]
							var fx: float = anchors[i].x + (-q.x if mirrors[i] else q.x)
							var fy: float = anchors[i].y + q.y
							# 화면 x 는 캐릭터를 마주 본 모습 (캐릭터 오른쪽 = 화면 왼쪽), y 는 아래로.
							pts.append(center + Vector2(-fx, -(fy - view.x)) * scale_px)
						draw_colored_polygon(pts, color)
					if entry["dome"] != Vector3.ZERO:
						var c: Vector2 = entry["center"]
						var hx: float = anchors[i].x + c.x
						draw_circle(center + Vector2(-hx - 0.006, -(anchors[i].y + c.y + 0.006 - view.x)) * scale_px, scale_px * 0.008, Color(1, 1, 1, 0.55))
