class_name NetProtocol
extends RefCounted
## 서버(server/src/protocol.js)와 반드시 같은 값을 유지한다. 상세: docs/protocol.md

const VERSION: int = 12

## v12 말풍선(say): 대사 간격(ms)과 최대 글자 수 (서버와 같다).
const SAY_GAP_MS: int = 250
const SAY_MAX_CHARS: int = 90

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

# 상점 / 가구 / 옷
const ERR_NOT_NEAR_DOOR: String = "not_near_door"
const ERR_NOT_IN_SHOP: String = "not_in_shop"
const ERR_NOT_FOR_SALE: String = "not_for_sale"
const ERR_NOT_ENOUGH_SOL: String = "not_enough_sol"
const ERR_CANT_SELL: String = "cant_sell"
const ERR_BAD_PLACE: String = "bad_place"
const ERR_PLACE_LIMIT: String = "place_limit"
const ERR_NOT_OWNER: String = "not_owner"
const ERR_NOT_WEARABLE: String = "not_wearable"

# 날씨
const WEATHER_CLEAR: String = "clear"
const WEATHER_CLOUDY: String = "cloudy"
const WEATHER_RAIN: String = "rain"
const WEATHER_THUNDER: String = "thunder"

# 나무 상태
const TREE_GROWN: String = "grown"
const TREE_STUMP: String = "stump"
const TREE_SAPLING: String = "sapling"
## 씨앗을 심은 직후 (v6)
const TREE_SPROUT: String = "sprout"
## 묘목과 다 자란 나무 사이 (v6). 아직 벨 수 없다.
const TREE_YOUNG: String = "young"

# 꽃 상태 (v6)
const FLOWER_SPROUT: String = "sprout"
const FLOWER_BUD: String = "bud"
const FLOWER_BLOOM: String = "bloom"

# 부탁 종류
const QUEST_DELIVER: String = "deliver"
const QUEST_DELIVER_FISH: String = "deliver_fish"
const QUEST_ANY_FISH: String = "any_fish"

# fish_result.reason
const FISH_EARLY: String = "early"
const FISH_LATE: String = "late"
const FISH_ESCAPED: String = "escaped"
## 끌어올리기 연타가 모자라 놓침 (v0.11).
const FISH_SNAPPED: String = "snapped"
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

# 이벤트 (v5)
const ERR_NO_DROP: String = "no_drop"
const ERR_MERCHANT_AWAY: String = "merchant_away"
const ERR_NOT_WANTED: String = "not_wanted"

# 섬 생활 (v6): 심기 · 꽃 · 감정표현 · 박물관 · 공항 · 대화 주제
const ERR_NOT_SEED: String = "not_seed"
const ERR_BAD_PLANT: String = "bad_plant"
const ERR_PLANT_LIMIT: String = "plant_limit"
const ERR_NO_FLOWER: String = "no_flower"
const ERR_UNKNOWN_EMOTE: String = "unknown_emote"
const ERR_NOT_NEAR_KEEPER: String = "not_near_keeper"
const ERR_NOT_NEAR_MIRROR: String = "not_near_mirror"
const ERR_BAD_FACE: String = "bad_face"
const ERR_ALREADY_DONATED: String = "already_donated"
const ERR_NOT_FISH: String = "not_fish"
const ERR_BAD_TOPIC: String = "bad_topic"

# 경제 (v8): 증권 · 아파트 · 은행 · 식당
const ERR_MARKET_CLOSED: String = "market_closed"
const ERR_BAD_ORDER: String = "bad_order"
const ERR_NOT_ENOUGH_SHARES: String = "not_enough_shares"
const ERR_BAD_UNIT: String = "bad_unit"
const ERR_UNIT_TAKEN: String = "unit_taken"
const ERR_NOT_YOUR_UNIT: String = "not_your_unit"
const ERR_LOAN_LIMIT: String = "loan_limit"
const ERR_BAD_LOAN: String = "bad_loan"
const ERR_BAD_PRODUCT: String = "bad_product"
const ERR_BAD_ACCOUNT: String = "bad_account"
const ERR_ACCOUNT_LIMIT: String = "account_limit"
const ERR_JOB_BUSY: String = "job_busy"
const ERR_JOB_LIMIT: String = "job_limit"
const ERR_NO_JOB: String = "no_job"
const ERR_NOT_AT_JOB: String = "not_at_job"
const ERR_BAD_LEASE: String = "bad_lease"
const ERR_BANK_CLOSED: String = "bank_closed"
const ERR_REST_CLOSED: String = "rest_closed"
const ERR_REST_BUSY: String = "rest_busy"
const ERR_NOT_AT_RESTAURANT: String = "not_at_restaurant"
const ERR_ORDER_GONE: String = "order_gone"
const ERR_MISSING_INGREDIENT: String = "missing_ingredient"
const ERR_COOK_TOO_FAST: String = "cook_too_fast"

# 같이 하기 · 동사무소 · 여울 · 삽 (v9)
const ERR_NOT_STAFF: String = "not_staff"
const ERR_STEP_TAKEN: String = "step_taken"
const ERR_NOT_AT_CIVIC: String = "not_at_civic"
const ERR_NOT_ELIGIBLE: String = "not_eligible"
const ERR_BAD_PROGRAM: String = "bad_program"
const ERR_NO_PARTNER: String = "no_partner"
const ERR_ALREADY_MARRIED: String = "already_married"
const ERR_NOT_IN_SHALLOW: String = "not_in_shallow"
const ERR_BAD_DIG: String = "bad_dig"
## v10: 집 안
const ERR_NOT_AT_LOBBY: String = "not_at_lobby"
const ERR_NOT_HOME: String = "not_home"
const ERR_NOT_EDITABLE: String = "not_editable"
const ERR_HOME_FULL: String = "home_full"

## 감정표현 외에 보낼 수 있는 몸짓 (배우지 않아도 된다).
const MOTION_BRAKE: String = "brake"
## 대화 주제 (talk_topic.topic).
const TOPICS: PackedStringArray = ["mood", "hobby", "gossip", "fish", "past", "dream", "food", "you", "worry", "mbti"]
