class_name NetProtocol
extends RefCounted
## 서버(server/src/protocol.js)와 반드시 같은 값을 유지한다. 상세: docs/protocol.md

const VERSION: int = 3

# 에러 코드 (서버 → 클라이언트 `error.code`)
const ERR_BAD_VERSION: String = "bad_version"
const ERR_BAD_MESSAGE: String = "bad_message"
const ERR_NOT_IN_ROOM: String = "not_in_room"
const ERR_ALREADY_IN_ROOM: String = "already_in_room"
const ERR_ROOM_NOT_FOUND: String = "room_not_found"
const ERR_ROOM_FULL: String = "room_full"
const ERR_RESUME_FAILED: String = "resume_failed"
const ERR_RATE_LIMITED: String = "rate_limited"

# 낚시 / 인벤토리
const ERR_NOT_AT_SPOT: String = "not_at_spot"
const ERR_ALREADY_FISHING: String = "already_fishing"
const ERR_NOT_FISHING: String = "not_fishing"
const ERR_INVENTORY_FULL: String = "inventory_full"
const ERR_BAD_ITEM: String = "bad_item"
const ERR_CANT_DISCARD: String = "cant_discard"

# 도구 / 나무 베기
const ERR_NO_TOOL: String = "no_tool"
const ERR_NOT_NEAR_TREE: String = "not_near_tree"
const ERR_TREE_NOT_READY: String = "tree_not_ready"
const ERR_TOO_FAST: String = "too_fast"

# 주민 대화 / 부탁
const ERR_NOT_NEAR_NPC: String = "not_near_npc"
const ERR_NPC_BUSY: String = "npc_busy"
const ERR_NOT_TALKING: String = "not_talking"
const ERR_NO_OFFER: String = "no_offer"
const ERR_BAD_QUEST: String = "bad_quest"
const ERR_QUEST_NOT_READY: String = "quest_not_ready"

# 날씨
const WEATHER_CLEAR: String = "clear"
const WEATHER_CLOUDY: String = "cloudy"
const WEATHER_RAIN: String = "rain"
const WEATHER_THUNDER: String = "thunder"

# 나무 상태
const TREE_GROWN: String = "grown"
const TREE_STUMP: String = "stump"
const TREE_SAPLING: String = "sapling"

# 부탁 종류
const QUEST_DELIVER: String = "deliver"
const QUEST_DELIVER_FISH: String = "deliver_fish"
const QUEST_ANY_FISH: String = "any_fish"

# fish_result.reason
const FISH_EARLY: String = "early"
const FISH_LATE: String = "late"
const FISH_ESCAPED: String = "escaped"
const FISH_MOVED: String = "moved"
const FISH_CANCELLED: String = "cancelled"
const FISH_INVENTORY_FULL: String = "inventory_full"

# 클라이언트 쪽에서 만든 에러 코드
const ERR_CONNECT_FAILED: String = "connect_failed"
const ERR_RECONNECT_TIMEOUT: String = "reconnect_timeout"

# WebSocket 닫힘 코드
const CLOSE_REPLACED: int = 4000
const CLOSE_RATE_LIMITED: int = 4008

const ROOM_CODE_LENGTH: int = 6
