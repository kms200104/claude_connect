class_name EmoteInfo
extends RefCounted
## data/emotes/emotes.json 의 감정표현 하나. 아이콘은 assets/ui/emotes/<id>.png (tools/art/gen_emote_icons.py).

const ICON_DIR: String = "res://assets/ui/emotes"

var id: String = ""
var display_name: String = ""
## 할 때 나는 소리 (assets/audio/sfx).
var sound: String = "emote_pop"


static func from_dict(data: Dictionary) -> EmoteInfo:
	var info: EmoteInfo = EmoteInfo.new()
	info.id = str(data.get("id", ""))
	info.display_name = str(data.get("name", info.id))
	info.sound = str(data.get("sound", info.sound))
	return info


static func icon(emote_id: String) -> Texture2D:
	var path: String = "%s/%s.png" % [ICON_DIR, emote_id]
	return load(path) if ResourceLoader.exists(path) else null
