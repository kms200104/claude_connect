// 클라이언트(core/protocol/net_protocol.gd)와 반드시 같은 값을 유지한다. 상세: docs/protocol.md
export const PROTOCOL_VERSION = 12;

// v12: 말풍선(say) — 한 사람이 보내는 대사 간격(ms)과 최대 글자 수.
export const SAY_GAP_MS = 250;
export const SAY_MAX_CHARS = 90;

export const ErrorCode = Object.freeze({
  badVersion: 'bad_version',
  badMessage: 'bad_message',
  notInRoom: 'not_in_room',
  alreadyInRoom: 'already_in_room',
  roomNotFound: 'room_not_found',
  roomFull: 'room_full',
  resumeFailed: 'resume_failed',
  rateLimited: 'rate_limited',
  // 낚시 / 인벤토리
  notAtSpot: 'not_at_spot',
  alreadyFishing: 'already_fishing',
  notFishing: 'not_fishing',
  inventoryFull: 'inventory_full',
  badItem: 'bad_item',
  cantDiscard: 'cant_discard', // 도구는 버릴 수 없다
  // 도구 / 나무 베기
  noTool: 'no_tool', // 알맞은 도구를 손에 들고 있지 않음
  notNearTree: 'not_near_tree',
  treeNotReady: 'tree_not_ready', // 그루터기·묘목
  tooFast: 'too_fast',
  // 주민 대화 / 부탁
  notNearNpc: 'not_near_npc',
  npcBusy: 'npc_busy', // 다른 사람과 이야기 중
  notTalking: 'not_talking',
  noOffer: 'no_offer',
  badQuest: 'bad_quest',
  questNotReady: 'quest_not_ready', // 아이템이 모자람
  // 상점
  notNearDoor: 'not_near_door',
  notInShop: 'not_in_shop',
  notForSale: 'not_for_sale', // 지금 상점 단계에서 팔지 않는 물건
  notEnoughSol: 'not_enough_sol',
  cantSell: 'cant_sell', // 도구 등
  // 가구 설치 · 옷
  badPlace: 'bad_place', // 너무 멀거나, 물·나무·다른 가구와 겹침, 상점 안
  placeLimit: 'place_limit',
  notOwner: 'not_owner',
  notWearable: 'not_wearable',
  // 이벤트
  noDrop: 'no_drop', // 주울 선물·별 조각이 없거나 너무 멂
  merchantAway: 'merchant_away', // 떠돌이 상인이 없거나 너무 멂
  notWanted: 'not_wanted', // 떠돌이 상인이 찾는 물건이 아님
  // 심기 · 꽃
  notSeed: 'not_seed', // 손에 든 게 씨앗이 아님
  badPlant: 'bad_plant', // 물·길·건물·나무와 겹치거나 너무 멂
  plantLimit: 'plant_limit', // 마을에 심을 수 있는 수를 넘음
  noFlower: 'no_flower', // 딸 꽃이 없거나 아직 안 핌, 너무 멂
  // 감정표현
  unknownEmote: 'unknown_emote', // 아직 배우지 않은 감정표현
  // 박물관 · 공항
  notNearKeeper: 'not_near_keeper', // 관장·조종사 곁이 아님
  notNearMirror: 'not_near_mirror', // 거울 앞이 아님
  badFace: 'bad_face', // 모르는 얼굴 항목·모양
  marketClosed: 'market_closed', // 장이 닫혔다 (MARKET_HOURS=krx)
  badOrder: 'bad_order', // 모르는 종목·수량
  notEnoughShares: 'not_enough_shares', // 가진 주식보다 많이 팔려고 함
  // 예적금 (v0.12)
  badProduct: 'bad_product', // 모르는 상품·기간·금액
  badAccount: 'bad_account', // 없는 계좌
  accountLimit: 'account_limit', // 계좌를 더 만들 수 없음
  badUnit: 'bad_unit', // 모르는 호수
  unitTaken: 'unit_taken', // 이미 누가 가진 집
  notYourUnit: 'not_your_unit', // 내 집이 아님
  loanLimit: 'loan_limit', // 대출 한도 · DSR 초과
  badLoan: 'bad_loan', // 모르는 대출 · 이상한 금액
  restClosed: 'rest_closed', // 식당이 닫혀 있다
  restBusy: 'rest_busy', // 다른 사람이 식당을 열었다
  notAtRestaurant: 'not_at_restaurant', // 식당 카운터에서 멀다
  orderGone: 'order_gone', // 손님이 떠났거나 없는 주문
  missingIngredient: 'missing_ingredient', // 떼어 둔 재료가 가방에 없다
  cookTooFast: 'cook_too_fast', // 요리를 너무 빨리 냈다
  // v0.9 같이 하기 · 동사무소 · 여울 · 삽
  notStaff: 'not_staff', // 식당 직원이 아니다 (같이 일하기 먼저)
  stepTaken: 'step_taken', // 다른 사람이 맡은(또는 끝낸) 요리 동작
  notAtCivic: 'not_at_civic', // 동사무소 그 창구에서 멀다
  notEligible: 'not_eligible', // 지원·대출 자격이 안 된다 (이유는 civic 에)
  badProgram: 'bad_program', // 모르는 민원·정책
  noPartner: 'no_partner', // 혼인신고 상대가 없거나 곁에 없다
  alreadyMarried: 'already_married', // 이미 혼인신고한 세대
  notInShallow: 'not_in_shallow', // 여울(얕은 물) 안이 아니다
  badDig: 'bad_dig', // 팔 수 없는 자리 (물·건물·길·나무 곁 …)
  // v10: 집 안
  notAtLobby: 'not_at_lobby', // 그 동 공동 현관 앞이 아님
  notHome: 'not_home', // 집 안이 아님 (또는 현관문 곁이 아님)
  notEditable: 'not_editable', // 내(세대) 집이 아니라 가구를 옮길 수 없음
  homeFull: 'home_full', // 집 안 가구가 너무 많음
  alreadyDonated: 'already_donated', // 이미 기증한 물고기
  notFish: 'not_fish',
  // 대화 주제
  badTopic: 'bad_topic',
});

// 감정표현 외에 보낼 수 있는 몸짓 (배우지 않아도 된다).
export const MOTIONS = Object.freeze(['brake']);
// 대화 주제 (talk_topic.topic).
export const TOPICS = Object.freeze(['mood', 'hobby', 'gossip', 'fish', 'past', 'dream', 'food', 'you', 'worry', 'mbti']);

export const Weather = Object.freeze({
  clear: 'clear',
  cloudy: 'cloudy',
  rain: 'rain',
  thunder: 'thunder',
});

// fish_result.reason
export const FishFail = Object.freeze({
  early: 'early', // 입질 전에(또는 가짜 입질에) 당김
  late: 'late', // 허용 창을 넘김
  escaped: 'escaped', // 아예 반응이 없어 도망감
  moved: 'moved', // 움직여서 취소됨
  cancelled: 'cancelled',
  inventoryFull: 'inventory_full',
  snapped: 'snapped', // 끌어올리기 연타가 모자라 놓침 (v0.11)
  disconnected: 'disconnected',
});

// 헷갈리는 글자(0/O, 1/I/L)를 뺀 방 코드 문자.
export const ROOM_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const ROOM_CODE_LENGTH = 6;

// 닫힘 코드 (클라이언트가 재접속 여부를 판단할 때 쓴다).
export const CloseCode = Object.freeze({
  replaced: 4000, // 같은 세션이 다른 연결로 이어짐 → 재접속하지 말 것
  rateLimited: 4008,
  badProtocol: 4009,
});
