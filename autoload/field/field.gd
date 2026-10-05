extends Node
## 들판·물가 상태 (v9) — 서버가 보낸 값만 들고 있다: 여울(얕은 물)의 물고기 떼, 조개 숨구멍, 삽으로 고친 땅 칸.
## Net.message_received 로 받고, 뜰채질·삽질 요청을 보낸다. 판정은 전부 서버가 한다.

## 여울 물고기 떼가 움직였다 (zone_id).
signal shoal_changed(zone_id: String)
signal digspot_added(spot: Dictionary)
signal digspot_changed(spot: Dictionary)
signal digspot_removed(id: String, by: int)
## 땅 칸이 바뀌었다 (s = "hole" | "path" | "" 지워짐).
signal tile_changed(x: int, z: int, s: String)
## 뜰채질 결과 { fish[], coop, lost }.
signal net_done(result: Dictionary)
## 삽질 결과 { kind: spot|clam|dig|fill|path, item, hp, coop, s }.
signal dig_done(result: Dictionary)
signal failed(kind: String, code: String)

const KINDS: PackedStringArray = ["net", "dig"]
const TILE_HOLE: String = "hole"
const TILE_PATH: String = "path"

## 여울 id → { panic, fish: { id: { x, z, size, px, pz, t } } } — px/pz/t 는 보간용 이전 값.
var shoals: Dictionary[String, Dictionary] = {}
## 숨구멍 id → { id, kind, x, z, hp }
var digspots: Dictionary[String, Dictionary] = {}
## "x,z" → "hole" | "path"
var tiles: Dictionary[String, String] = {}


func _ready() -> void:
	Net.message_received.connect(_on_message)
	Net.request_failed.connect(func(kind: String, code: String) -> void:
		if kind in KINDS:
			failed.emit(kind, code))


## 여울 하나 (data/fish/spots.json 의 shallows): 이 자리를 덮는 여울 정보, 없으면 null.
static func zone_at(position: Vector3, margin: float = 0.0) -> Dictionary:
	for spot: SpotInfo in GameData.spots.values():
		for z: Dictionary in spot.shallows:
			if absf(position.x - float(z["x"])) <= float(z["half_x"]) + margin and absf(position.z - float(z["z"])) <= float(z["half_z"]) + margin:
				return z
	return {}


func tile_at(x: int, z: int) -> String:
	return tiles.get("%d,%d" % [x, z], "")


## 가장 가까운 숨구멍 id (max_distance 안), 없으면 빈 문자열.
func nearest_digspot(position: Vector3, max_distance: float) -> String:
	var best: String = ""
	var best_d: float = max_distance
	for id: String in digspots:
		var d: Dictionary = digspots[id]
		var dist: float = Vector2(position.x - float(d["x"]), position.z - float(d["z"])).length()
		if dist <= best_d:
			best_d = dist
			best = id
	return best


func swing_net() -> void:
	Net.request("net")


## 삽질: (x, z) 를 mode(dig · fill · path) 로. 숨구멍 곁이면 서버가 조개 캐기로 본다.
func dig(at: Vector3, mode: String) -> void:
	Net.request("dig", {"x": snappedf(at.x, 0.01), "z": snappedf(at.z, 0.01), "mode": mode})


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			shoals.clear()
			for s: Variant in msg.get("shoals", []):
				if s is Dictionary:
					_apply_shoal(s)
			digspots.clear()
			for d: Variant in msg.get("digspots", []):
				if d is Dictionary:
					digspots[str(d.get("id", ""))] = d
			tiles.clear()
			for t: Variant in msg.get("tiles", []):
				if t is Array and t.size() >= 3:
					tiles["%d,%d" % [int(t[0]), int(t[1])]] = str(t[2])
		"shoal":
			_apply_shoal(msg)
		"digspot":
			var d: Variant = msg.get("d", {})
			if d is Dictionary:
				var id: String = str(d.get("id", ""))
				var known: bool = digspots.has(id)
				digspots[id] = d
				if known:
					digspot_changed.emit(d)
				else:
					digspot_added.emit(d)
		"digspot_gone":
			var gone: String = str(msg.get("id", ""))
			digspots.erase(gone)
			digspot_removed.emit(gone, int(msg.get("by", 0)))
		"tile":
			var key: String = "%d,%d" % [int(msg.get("x", 0)), int(msg.get("z", 0))]
			var s: String = str(msg.get("s", ""))
			if s.is_empty():
				tiles.erase(key)
			else:
				tiles[key] = s
			tile_changed.emit(int(msg.get("x", 0)), int(msg.get("z", 0)), s)
		"net_result":
			net_done.emit(msg)
		"dig_result":
			dig_done.emit(msg)


func _apply_shoal(msg: Dictionary) -> void:
	var id: String = str(msg.get("id", ""))
	var now: float = float(Time.get_ticks_msec())
	var shoal: Dictionary = shoals.get(id, {"fish": {}})
	shoal["panic"] = bool(msg.get("panic", false))
	var old: Dictionary = shoal["fish"]
	var fish: Dictionary = {}
	for f: Variant in msg.get("f", []):
		if not f is Array or f.size() < 4:
			continue
		var fid: int = int(f[0])
		var prev: Dictionary = old.get(fid, {})
		fish[fid] = {
			"x": float(f[1]), "z": float(f[2]), "size": str(f[3]),
			"px": float(prev.get("x", f[1])), "pz": float(prev.get("z", f[2])), "t": now,
		}
	shoal["fish"] = fish
	shoals[id] = shoal
	shoal_changed.emit(id)
