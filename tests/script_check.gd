extends Node
## 모든 GDScript 를 불러 문법·타입 오류가 없는지 본다 (오토로드가 있는 상태에서). 실패하면 종료 코드 1.
## 사용: godot --headless --path . res://tests/script_check.tscn

const ROOTS: PackedStringArray = ["res://autoload", "res://core", "res://game", "res://ui", "res://tools", "res://tests"]


func _ready() -> void:
	var failed: PackedStringArray = []
	var count: int = 0
	for root: String in ROOTS:
		for path: String in _scripts(root):
			count += 1
			var script: Script = load(path)
			if script == null or not script.can_instantiate() and not (script as GDScript).is_abstract():
				failed.append(path)
	if failed.is_empty():
		print("[script_check] OK %d scripts" % count)
		get_tree().quit(0)
	else:
		print("[script_check] FAIL %s" % ", ".join(failed))
		get_tree().quit(1)


func _scripts(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d: String in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(d)))
	return out
