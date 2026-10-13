class_name AlertLog
extends RefCounted
## 받은 재난문자 기록 (v0.20, 안전알림 앱이 보여 준다): user://alerts.json 에 최근 MAX 개 (새것부터).
## 같은 날 같은 문자(id + 마을 시각)는 한 번만 남긴다 (다시 들어오면 오늘 문자를 또 받으므로).

const PATH: String = "user://alerts.json"
const MAX: int = 40

class Events:
	extends RefCounted
	signal added


static var events: Events = Events.new()
static var _list: Array[Dictionary] = []
static var _loaded: bool = false


static func list() -> Array[Dictionary]:
	_ensure()
	return _list


## 남겼으면 true (이미 있던 문자면 false).
static func add(alert: Dictionary) -> bool:
	_ensure()
	var key: String = "%s@%s" % [str(alert.get("id", "")), str(alert.get("at", 0))]
	for a: Dictionary in _list:
		if str(a.get("key", "")) == key:
			return false
	_list.push_front({"key": key, "id": str(alert.get("id", "")), "level": str(alert.get("level", "safety")), "sender": str(alert.get("sender", "")),
		"text": str(alert.get("text", "")), "time": Time.get_datetime_string_from_system(false, true)})
	while _list.size() > MAX:
		_list.pop_back()
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_list))
	events.added.emit()
	return true


static func clear_for_test() -> void:
	_list.clear()
	_loaded = true


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Array:
		for a: Variant in parsed:
			if a is Dictionary:
				_list.append(a)
