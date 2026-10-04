# 네트워크 프로토콜 v2

WebSocket 텍스트 프레임, 메시지 하나가 JSON 객체 하나. `t`가 종류. 서버가 권위이고 클라이언트가 보내는 건 전부 **요청**이다.
상수는 `server/src/protocol.js` 와 `core/protocol/net_protocol.gd` 에 같은 값으로 둔다. 바꾸면 `VERSION`을 올린다.

## 클라이언트 → 서버
| t | 필드 | 설명 |
|---|---|---|
| `create` | `v uid` | 방 생성 + 입장. `uid`는 기기에 저장된 영구 ID(8~64자 `[A-Za-z0-9_-]`) |
| `join` | `v uid code` | 방 코드(대소문자 무관)로 입장. 같은 `uid`는 쓰던 자리·인벤토리를 되찾는다 |
| `resume` | `v`, `token` | 끊긴 자리로 복귀 (유예 시간 안에서만) |
| `move` | `x y z yaw vx vz` | 내 위치 요청 (m, rad). 서버가 속도·경계 검사 |
| `ping` | `c` | 클라이언트 시각. `pong`으로 RTT·서버 시계 추정 |
| `fish_cast` | `rid spot` | 낚시터에 던지기 요청. 수역 `cast_range` 안에 있어야 한다 |
| `fish_hook` | `rid reaction` | 챔질 요청. `reaction` = 입질 연출이 보인 뒤 버튼을 누르기까지 걸린 ms (입질 전이면 0) |
| `fish_cancel` | | 낚시 취소 |
| `inv_discard` | `rid id n` | 물고기 놓아주기 |

## 서버 → 클라이언트
| t | 필드 | 설명 |
|---|---|---|
| `welcome` | `id token code resumed st players[] inv` | 입장/복귀 성공. `token`은 재접속 열쇠, `inv`는 내 인벤토리 |
| `peer_joined` | `p` | 상대 입장 |
| `peer_status` | `id online` | 상대 연결 끊김/복귀 (자리는 유지) |
| `peer_left` | `id` | 유예 시간이 지나 자리가 비워짐 |
| `snap` | `st p[]` | 위치 스냅샷 (방 단위, 변화가 있을 때만, 기본 20Hz) |
| `correct` | `x y z` | 요청한 이동이 거부됨 → 이 위치로 되돌리기 |
| `pong` | `c s` | `s` = 서버 시각(ms) |
| `inventory` | `items[] cap` | 내 인벤토리 전체(`items`: `{id, n}`). 바뀔 때마다 나에게만 |
| `fish_started` | `rid spot` | 던지기 수락 |
| `fish_nibble` | `rid` | 가짜 입질 (0~3번). 아직 당기면 안 된다 |
| `fish_bite` | `rid windowMs` | 진짜 입질. 물고기 종류는 알리지 않는다 |
| `fish_result` | `rid ok fish? reason?` | 서버가 확정한 결과. 실패 사유: `early late escaped moved cancelled inventory_full` |
| `error` | `code msg rid?` | `bad_version bad_message not_in_room already_in_room room_not_found room_full resume_failed rate_limited not_at_spot already_fishing not_fishing inventory_full bad_item` |

`players[]`/`p[]` 항목: `{id, online, fishing, x, y, z, yaw, vx, vz}` (`fishing`은 상대 캐릭터의 낚시 자세 동기화용). `st`/`s`는 서버 단조 시계(ms).

## 흐름
- **입장**: `create`/`join` → `welcome`(+상대에게 `peer_joined`). 클라이언트는 `welcome`의 내 위치로 캐릭터를 맞춘다.
- **동기화**: 클라이언트는 20Hz로 `move`(바뀐 게 있을 때 + 1초 하트비트). 서버는 `snap`을 방송하고, 클라이언트는 서버 시계 기준 120ms 과거를 보간해서 그린다.
- **끊김**: 서버가 소켓 close 또는 ws ping 무응답으로 감지 → `peer_status(online:false)`, 자리를 30초 유지. 클라이언트는 close 또는 6초 무응답을 감지하면 백오프(0.3→3초)로 `resume`을 반복하고, 서버 유예보다 약간 긴 35초 뒤 포기한다.
- **복귀**: `resume` → `welcome(resumed:true)`. 서버가 알고 있는 마지막 위치로 되돌아간다(오프라인 중 이동은 인정하지 않음).
- **대체**: 같은 `token`으로 새 연결이 오면 낡은 연결을 close code `4000`으로 끊는다(클라이언트는 이 코드에서 재접속하지 않는다).

## 서버 검증
이동은 `max_speed × 1.6 × dt + 0.6m` 이내만 인정하고 초과분은 잘라낸 뒤 `correct`를 보낸다. 경계(±78m)·높이(−5~30m) 밖은 안으로 되돌린다.
연결당 초당 60개(버스트 120) 초과 시 `rate_limited`, 계속 넘으면 close `4008`. 메시지는 1KB 이하.

## 낚시 (서버 판정)
`fish_cast` → `fish_started` → 가짜 `fish_nibble` × 0~3 → `fish_bite{windowMs}` → `fish_hook{reaction}` → `fish_result`.
- 물고기는 던질 때 서버가 가중치로 정하고, 결과가 확정될 때에만 `fish_result.fish`로 알린다.
- 서버는 `reaction`이 허용 창(`hook_window_ms`, 450~700ms) 안인지, 사람이 낼 수 있는 값(≥80ms)인지, 서버가 잰 경과 시간과 모순되지 않는지만 본다. 네트워크 지연은 판정에 들어가지 않는다.
- 입질 전에 당기면 `early`, 창을 넘기면 `late`, 아예 반응이 없으면 `escaped`, 캐스팅 지점에서 1.5m 넘게 움직이면 `moved`.
- 같은 `rid`는 한 번만 처리한다. 접속이 끊기면 낚시는 취소된다.

## 인벤토리
물고기 종류 하나가 한 칸. 기본 20칸, 칸당 99마리. 가득 차면 던지기 전에 `inventory_full`로 거절하고, 던진 뒤 칸이 찼다면 `fish_result(inventory_full)`로 놓친다.

## 저장
방(마을) 하나 = JSON 파일 하나: `<SAVE_DIR>/<방코드>.json` (`schema`, `createdAt`, `world{totalCatches, species}`, `profiles{<uid>: {slot, items, catches, x, y, z, yaw}}`).
- 사람은 `uid`로 구분한다. 서버가 재시작되어 `token`이 사라져도, 클라이언트가 방 코드 + `uid`로 `join`하면 같은 자리·인벤토리·위치로 돌아온다(클라이언트가 `resume_failed` 뒤 자동으로 시도).
- 인벤토리 변경·입퇴장은 즉시, 위치는 변경이 있으면 5초 주기로 저장한다. 쓰기는 임시 파일 → rename 으로 원자적이다. 종료 시에는 메모리의 방을 전부 저장한다.
- 방 코드는 파일 이름이라 형식(`[A-HJ-KM-NP-Z2-9]{6}`)을 검사한 뒤에만 쓴다. 깨진 파일은 `.corrupt-<시각>`으로 옮겨 두고 방이 없는 것으로 처리한다.
