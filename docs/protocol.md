# 네트워크 프로토콜 v1

WebSocket 텍스트 프레임, 메시지 하나가 JSON 객체 하나. `t`가 종류. 서버가 권위이고 클라이언트가 보내는 건 전부 **요청**이다.
상수는 `server/src/protocol.js` 와 `core/protocol/net_protocol.gd` 에 같은 값으로 둔다. 바꾸면 `VERSION`을 올린다.

## 클라이언트 → 서버
| t | 필드 | 설명 |
|---|---|---|
| `create` | `v` | 방 생성 + 입장 |
| `join` | `v`, `code` | 방 코드(대소문자 무관)로 입장 |
| `resume` | `v`, `token` | 끊긴 자리로 복귀 (유예 시간 안에서만) |
| `move` | `x y z yaw vx vz` | 내 위치 요청 (m, rad). 서버가 속도·경계 검사 |
| `ping` | `c` | 클라이언트 시각. `pong`으로 RTT·서버 시계 추정 |

## 서버 → 클라이언트
| t | 필드 | 설명 |
|---|---|---|
| `welcome` | `id token code resumed st players[]` | 입장/복귀 성공. `token`은 재접속 열쇠 |
| `peer_joined` | `p` | 상대 입장 |
| `peer_status` | `id online` | 상대 연결 끊김/복귀 (자리는 유지) |
| `peer_left` | `id` | 유예 시간이 지나 자리가 비워짐 |
| `snap` | `st p[]` | 위치 스냅샷 (방 단위, 변화가 있을 때만, 기본 20Hz) |
| `correct` | `x y z` | 요청한 이동이 거부됨 → 이 위치로 되돌리기 |
| `pong` | `c s` | `s` = 서버 시각(ms) |
| `error` | `code msg` | `bad_version bad_message not_in_room already_in_room room_not_found room_full resume_failed rate_limited` |

`players[]`/`p[]` 항목: `{id, online, x, y, z, yaw, vx, vz}`. `st`/`s`는 서버 단조 시계(ms).

## 흐름
- **입장**: `create`/`join` → `welcome`(+상대에게 `peer_joined`). 클라이언트는 `welcome`의 내 위치로 캐릭터를 맞춘다.
- **동기화**: 클라이언트는 20Hz로 `move`(바뀐 게 있을 때 + 1초 하트비트). 서버는 `snap`을 방송하고, 클라이언트는 서버 시계 기준 120ms 과거를 보간해서 그린다.
- **끊김**: 서버가 소켓 close 또는 ws ping 무응답으로 감지 → `peer_status(online:false)`, 자리를 30초 유지. 클라이언트는 close 또는 6초 무응답을 감지하면 백오프(0.3→3초)로 `resume`을 반복하고, 서버 유예보다 약간 긴 35초 뒤 포기한다.
- **복귀**: `resume` → `welcome(resumed:true)`. 서버가 알고 있는 마지막 위치로 되돌아간다(오프라인 중 이동은 인정하지 않음).
- **대체**: 같은 `token`으로 새 연결이 오면 낡은 연결을 close code `4000`으로 끊는다(클라이언트는 이 코드에서 재접속하지 않는다).

## 서버 검증
이동은 `max_speed × 1.6 × dt + 0.6m` 이내만 인정하고 초과분은 잘라낸 뒤 `correct`를 보낸다. 경계(±78m)·높이(−5~30m) 밖은 안으로 되돌린다.
연결당 초당 60개(버스트 120) 초과 시 `rate_limited`, 계속 넘으면 close `4008`. 메시지는 1KB 이하.
