class_name DishArt
extends RefCounted
## 요리 그림: 접시 모형(recipes.json 의 model → PartMesh)과 아이콘(assets/icons/dishes/<id>.png, tools/render_icons 가 찍는다).

const ICON_DIR: String = "res://assets/icons/dishes"

static var _icons: Dictionary[String, Texture2D] = {}


static func mesh(dish_id: String) -> ArrayMesh:
	var r: RecipeInfo = GameData.econ.recipes.get(dish_id) if GameData.econ != null else null
	return PartMesh.get_mesh("dish_%s" % dish_id, r.model if r != null else [])


## 아이콘 (없으면 null — 화면은 이름 글자로 대신한다).
static func icon(dish_id: String) -> Texture2D:
	if _icons.has(dish_id):
		return _icons[dish_id]
	var path: String = "%s/%s.png" % [ICON_DIR, dish_id]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[dish_id] = tex
	return tex
