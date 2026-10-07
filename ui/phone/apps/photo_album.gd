class_name PhotoAlbum
extends RefCounted
## 휴대폰 앨범 (v16): 카메라로 찍은 사진 · 마을톡에서 저장한 사진을 이 기기(user://album)에 JPEG 로 둔다.
## 서버에는 올리지 않는다 (친구에게 보낼 때만 그 한 장을 보낸다). 최근 MAX 장까지, 넘치면 오래된 것부터 지운다.

const DIR: String = "user://album"
const MAX: int = 120
## 찍는 크기 (가로 × 세로, 4:5). 보낼 때도 이 크기 그대로 (JPEG 약 30~60KB).
const SIZE: Vector2i = Vector2i(480, 600)
const QUALITY: float = 0.8

static var _thumbs: Dictionary[String, Texture2D] = {}


## 사진 이름들 (최근 것 먼저).
static func list() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".jpg"):
			out.append(f.get_basename())
	out.sort()
	out.reverse()
	return out


## 저장하고 이름을 돌려준다 (실패하면 빈 문자열).
static func save(image: Image) -> String:
	return save_jpeg(image.save_jpg_to_buffer(QUALITY))


static func save_jpeg(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	# 시각 + 차례 (같은 초에 여러 장).
	var stamp: String = Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var name: String = stamp
	var n: int = 1
	while FileAccess.file_exists(path_of(name)):
		n += 1
		name = "%s_%d" % [stamp, n]
	var f: FileAccess = FileAccess.open(path_of(name), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	_trim()
	return name


static func path_of(name: String) -> String:
	return "%s/%s.jpg" % [DIR, name]


static func bytes_of(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path_of(name)) if FileAccess.file_exists(path_of(name)) else PackedByteArray()


static func texture(name: String) -> Texture2D:
	var img: Image = Image.new()
	if img.load_jpg_from_buffer(bytes_of(name)) != OK:
		return null
	return ImageTexture.create_from_image(img)


## 작은 그림 (앨범 칸, 기억해 둔다).
static func thumb(name: String) -> Texture2D:
	if _thumbs.has(name):
		return _thumbs[name]
	var img: Image = Image.new()
	if img.load_jpg_from_buffer(bytes_of(name)) != OK:
		return null
	img.resize(160, 200, Image.INTERPOLATE_BILINEAR)
	var tex: Texture2D = ImageTexture.create_from_image(img)
	_thumbs[name] = tex
	return tex


static func delete(name: String) -> void:
	_thumbs.erase(name)
	DirAccess.remove_absolute(path_of(name))


## "2026년 10월 6일 오후 3:05" (이름의 시각으로).
static func taken_text(name: String) -> String:
	var s: String = name.left(15)
	if s.length() < 15 or not s.substr(0, 8).is_valid_int():
		return name
	var h: int = int(s.substr(9, 2))
	return "%d년 %d월 %d일 %s %d:%s" % [int(s.substr(0, 4)), int(s.substr(4, 2)), int(s.substr(6, 2)), "오전" if h < 12 else "오후", (h + 11) % 12 + 1, s.substr(11, 2)]


static func _trim() -> void:
	var all: PackedStringArray = list()
	for i: int in range(MAX, all.size()):
		delete(all[i])
