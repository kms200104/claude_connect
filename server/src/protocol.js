// 클라이언트(core/protocol/net_protocol.gd)와 반드시 같은 값을 유지한다. 상세: docs/protocol.md
export const PROTOCOL_VERSION = 4;

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
});

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
