class_name NetProtocol
extends RefCounted
## 서버(server/src/protocol.js)와 반드시 같은 값을 유지한다. 상세: docs/protocol.md

const VERSION: int = 19

## v14 닉네임: 최대 글자 수 (서버 nickname.js NAME_MAX 와 같다).
const NAME_MAX: int = 10

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
## v13: 겨눈 자리가 물이 아니거나 너무 멂.
const ERR_BAD_CAST: String = "bad_cast"
## v14: 쓸 수 없는 닉네임.
const ERR_BAD_NAME: String = "bad_name"
## v13: 집 안 · 상점 안에서는 바닥에 내려놓을 수 없다 / 마을 바닥에 물건이 너무 많다.
const ERR_CANT_DROP_HERE: String = "cant_drop_here"
const ERR_GROUND_FULL: String = "ground_full"
## v13: 이미 배달 중인 주문이 많다 / 식당 창고에 그 재료가 가득하다.
const ERR_DELIVERY_BUSY: String = "delivery_busy"
const ERR_STORAGE_FULL: String = "storage_full"

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
## v19 차고: 모르는 모델 · 차고에 없는 탈것 / 맞지 않는 부품 / 차고 가득 / 실내 · 낚시 중이라 못 탐.
const ERR_BAD_VEHICLE: String = "bad_vehicle"
const ERR_BAD_PART: String = "bad_part"
const ERR_GARAGE_FULL: String = "garage_full"
const ERR_CANT_RIDE: String = "cant_ride"
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
## v17 테스트 도구가 꺼진 서버 (DEV_TOOLS=1 이 아님).
const ERR_DEV_OFF: String = "dev_off"
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
## v16: 칭호 · 생일 · 놀러 가기 · 사진
const ERR_BAD_TITLE: String = "bad_title"
const ERR_BAD_BIRTHDAY: String = "bad_birthday"
const ERR_NOT_VISITABLE: String = "not_visitable"
const ERR_BAD_PHOTO: String = "bad_photo"
const ERR_NO_PHOTO: String = "no_photo"

## 감정표현 외에 보낼 수 있는 몸짓 (배우지 않아도 된다).
const MOTION_BRAKE: String = "brake"
## 대화 주제 (talk_topic.topic).
const TOPICS: PackedStringArray = ["mood", "hobby", "gossip", "fish", "past", "dream", "food", "you", "worry", "mbti"]


## 닉네임 정리 (서버 nickname.js cleanName 과 같은 규칙): 띄어쓰기를 한 칸으로, 앞뒤 공백 지우기,
## 글자 · 숫자 · 띄어쓰기 · _ - . 만 남기고, NAME_MAX 글자까지.
static func clean_name(raw: String) -> String:
	var out: String = ""
	var space: bool = false
	for ch: String in raw.strip_edges():
		var code: int = ch.unicode_at(0)
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			space = true
			continue
		var ok: bool = ch == "_" or ch == "-" or ch == "." or (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
			or (code >= 0xAC00 and code <= 0xD7A3) or (code >= 0x3131 and code <= 0x318E) or (code >= 0x00C0 and code <= 0x024F) \
			or (code >= 0x3040 and code <= 0x30FF) or (code >= 0x4E00 and code <= 0x9FFF)
		if not ok:
			continue
		if space and not out.is_empty():
			out += " "
		space = false
		out += ch
	return out.substr(0, NAME_MAX).strip_edges()
