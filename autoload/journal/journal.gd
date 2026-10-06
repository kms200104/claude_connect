extends Node
## 내 기록 (v16) — 서버가 보낸 값만 들고 있다: 도감(낚은 물고기 · 모은 가구와 옷) · 한 일(stats) · 이룬 업적 · 칭호 · 생일,
## 마을 사람들의 칭호, 날씨 · 달력(이레), 지금 들어간 집의 방명록, 마을톡 사진.
## 칭호 달기 · 생일 정하기 · 방명록 쓰기 · 친구 집 놀러 가기 · 사진 보내기 요청을 보낸다. 판정은 서버가 한다.

## 도감 · 업적 · 칭호 · 생일이 바뀌었다 (프로필).
signal changed
## 새로 이룬 업적.
signal achieved(ids: PackedStringArray)
## 누군가 칭호를 바꿨다 (나 포함).
signal title_changed(slot: int)
signal calendar_changed
signal guestbook_changed
## 마을톡 사진을 받아 왔다.
signal photo_ready(id: String)
## 사진을 보냈다 (서버가 확정).
signal photo_sent(id: String, thread: String)
## 친구가 우리 집에 놀러 왔다.
signal visited(slot: int)
signal failed(kind: String, code: String)

const KINDS: PackedStringArray = ["set_title", "set_birthday", "gb_write", "home_visit", "photo_up"]
## 받은 사진을 잠깐 두는 곳 (다시 받지 않게).
const PHOTO_CACHE: String = "user://photo_cache"

## 한 일 · 도감 크기 · 친밀도 등 업적 판정 값 (서버 statValues).
var stats: Dictionary[String, int] = {}
## 낚은 물고기 → 낚은 수.
var dex_fish: Dictionary[String, int] = {}
## 모은 가구 · 옷.
var dex_items: PackedStringArray = []
## 이룬 업적 → 이룬 마을 날짜.
var achieved_at: Dictionary[String, int] = {}
## 마을 사람 자리 → 단 칭호(업적 id).
var titles: Dictionary[int, String] = {}
## 내 생일 (달 · 날, 없으면 (0, 0)).
var birthday: Vector2i = Vector2i.ZERO
## 날씨 · 달력: [{ day, month, day_of_month, weekday, season, weather: PackedStringArray(8), event, meteor, npcs, players }].
var calendar: Array[Dictionary] = []
var calendar_today: int = -1
## 이번 주 경제 소식 (달력 맨 위).
var calendar_econ: String = ""
## 지금 들어간 집의 방명록 [{ by, tx, at }].
var guestbook: Array[Dictionary] = []

var _photos: Dictionary[String, Texture2D] = {}
var _photo_asked: Dictionary[String, int] = {}


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind in KINDS:
			failed.emit(kind, code))


# ---- 요청 ----

## 칭호 달기 ("" = 떼기).
func set_title(achievement_id: String) -> void:
	Net.request("set_title", {"id": achievement_id})


func set_birthday(month: int, day: int) -> void:
	Net.request("set_birthday", {"birthday": {"m": month, "d": day}})


## 날씨 · 달력 다시 받기.
func ask_calendar() -> void:
	Net.send_message({"t": "cal_info"})


func write_guestbook(text: String) -> void:
	var t: String = text.strip_edges()
	if not t.is_empty():
		Net.request("gb_write", {"tx": t.left(100)})


## 친구 집으로 바로 놀러 가기 (호수).
func visit(unit: String) -> void:
	Net.request("home_visit", {"unit": unit})


## 사진(JPEG)을 친구 대화방(pl:<자리>)으로 보낸다.
func send_photo(thread: String, jpeg: PackedByteArray, caption: String = "") -> void:
	Net.request("photo_up", {"th": thread, "img": Marshalls.raw_to_base64(jpeg), "tx": caption.strip_edges().left(60)})


# ---- 읽기 ----

func has(achievement_id: String) -> bool:
	return achieved_at.has(achievement_id)


func my_title() -> String:
	return titles.get(Net.my_id, "")


## 칭호 글자 (없으면 빈 문자열).
func title_text(slot: int) -> String:
	var a: AchievementInfo = GameData.achievement_by_id.get(titles.get(slot, ""))
	return a.title if a != null else ""


## 머리 위 · 목록에 쓰는 이름: "[칭호] 닉네임" (칭호가 없으면 닉네임만).
func display_name(slot: int) -> String:
	var t: String = title_text(slot)
	return GameData.player_name(slot) if t.is_empty() else "[%s] %s" % [t, GameData.player_name(slot)]


func stat(key: String) -> int:
	return stats.get(key, 0)


## 오늘이 생일인 주민 (마을 날짜 기준).
func npcs_with_birthday(day: int) -> Array[NpcInfo]:
	var date: Dictionary = VillageClock.date_of_day(day)
	var out: Array[NpcInfo] = []
	for npc: NpcInfo in GameData.npcs.values():
		if npc.birthday == Vector2i(int(date["month"]), int(date["day"])):
			out.append(npc)
	return out


## 마을톡 사진 (아직 없으면 받아 오고 null — 오면 photo_ready).
func photo(id: String) -> Texture2D:
	if _photos.has(id):
		return _photos[id]
	var cached: String = "%s/%s.jpg" % [PHOTO_CACHE, id]
	if FileAccess.file_exists(cached):
		var tex: Texture2D = _texture_from_jpeg(FileAccess.get_file_as_bytes(cached))
		if tex != null:
			_photos[id] = tex
			return tex
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _photo_asked.get(id, -100000) > 8000:
		_photo_asked[id] = now_ms
		Net.send_message({"t": "photo_get", "id": id})
	return null


## 마을톡 사진의 JPEG (앨범에 저장할 때, 없으면 빈 배열).
func photo_bytes(id: String) -> PackedByteArray:
	var cached: String = "%s/%s.jpg" % [PHOTO_CACHE, id]
	return FileAccess.get_file_as_bytes(cached) if FileAccess.file_exists(cached) else PackedByteArray()


static func _texture_from_jpeg(bytes: PackedByteArray) -> Texture2D:
	var img: Image = Image.new()
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


# ---- 받기 ----

func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			titles.clear()
			for p: Variant in msg.get("players", []):
				if p is Dictionary:
					titles[int(p.get("id", 0))] = str(p.get("title", ""))
			_apply_profile(msg.get("prof", {}))
			calendar.clear()
			guestbook.clear()
		"peer_joined":
			var joined: Variant = msg.get("p", {})
			if joined is Dictionary:
				titles[int(joined.get("id", 0))] = str(joined.get("title", ""))
				title_changed.emit(int(joined.get("id", 0)))
		"profile":
			_apply_profile(msg)
		"ach":
			var ids: PackedStringArray = []
			for id: Variant in msg.get("ids", []):
				ids.append(str(id))
			if not ids.is_empty():
				achieved.emit(ids)
		"title":
			var slot: int = int(msg.get("id", 0))
			titles[slot] = str(msg.get("title", ""))
			title_changed.emit(slot)
			if slot == Net.my_id:
				changed.emit()
		"cal":
			_apply_calendar(msg)
		"home":
			guestbook.clear()
			for e: Variant in msg.get("gb", []):
				if e is Dictionary:
					guestbook.append(e)
			guestbook_changed.emit()
		"gb":
			if str(msg.get("unit", "")) == Home.unit:
				guestbook.clear()
				for e: Variant in msg.get("list", []):
					if e is Dictionary:
						guestbook.append(e)
				guestbook_changed.emit()
		"visit":
			visited.emit(int(msg.get("id", 0)))
		"photo":
			_on_photo(str(msg.get("id", "")), str(msg.get("img", "")))
		"photo_sent":
			photo_sent.emit(str(msg.get("id", "")), str(msg.get("th", "")))


func _apply_profile(prof: Variant) -> void:
	if not prof is Dictionary or not (prof as Dictionary).has("stats"):
		return
	var p: Dictionary = prof
	stats.clear()
	var raw_stats: Variant = p.get("stats", {})
	if raw_stats is Dictionary:
		for k: Variant in raw_stats:
			stats[str(k)] = int(raw_stats[k])
	dex_fish.clear()
	var dex: Dictionary = p.get("dex", {}) if p.get("dex") is Dictionary else {}
	var fish: Variant = dex.get("fish", {})
	if fish is Dictionary:
		for k: Variant in fish:
			dex_fish[str(k)] = int(fish[k])
	dex_items = PackedStringArray()
	for id: Variant in dex.get("items", []):
		dex_items.append(str(id))
	achieved_at.clear()
	for a: Variant in p.get("ach", []):
		if a is Dictionary:
			achieved_at[str(a.get("id", ""))] = int(a.get("at", 0))
	titles[Net.my_id] = str(p.get("title", ""))
	var b: Variant = p.get("birthday")
	birthday = Vector2i(int(b.get("m", 0)), int(b.get("d", 0))) if b is Dictionary else Vector2i.ZERO
	changed.emit()


func _apply_calendar(msg: Dictionary) -> void:
	calendar.clear()
	calendar_today = int(msg.get("today", -1))
	calendar_econ = str(msg.get("econ", ""))
	for d: Variant in msg.get("days", []):
		if not d is Dictionary:
			continue
		var weather: PackedStringArray = []
		for w: Variant in d.get("w", []):
			weather.append(str(w))
		var npcs: PackedStringArray = []
		for n: Variant in d.get("npc", []):
			npcs.append(str(n))
		var players: PackedInt32Array = []
		for s: Variant in d.get("pl", []):
			players.append(int(s))
		calendar.append({
			"day": int(d.get("day", 0)), "month": int(d.get("m", 0)), "date": int(d.get("d", 0)), "weekday": int(d.get("wd", 0)),
			"season": str(d.get("season", "")), "weather": weather, "event": str(d.get("ev", "")), "meteor": bool(d.get("meteor", false)),
			"npcs": npcs, "players": players,
		})
	calendar_changed.emit()


func _on_photo(id: String, b64: String) -> void:
	if id.is_empty() or b64.is_empty():
		return
	var bytes: PackedByteArray = Marshalls.base64_to_raw(b64)
	var tex: Texture2D = _texture_from_jpeg(bytes)
	if tex == null:
		return
	DirAccess.make_dir_recursive_absolute(PHOTO_CACHE)
	var f: FileAccess = FileAccess.open("%s/%s.jpg" % [PHOTO_CACHE, id], FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	_photos[id] = tex
	photo_ready.emit(id)
