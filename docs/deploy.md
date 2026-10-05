# 서버 항상 켜 두기 · 안드로이드 테스트 (v0.10, v0.11)

## 1. 안드로이드에서 테스트할 때

### 서버 없이: 앱 안 테스트 서버
- 첫 화면 **"서버 없이 테스트하기"**, 또는 접속에 실패했을 때 방 패널의 **"연결이 안 되면: 테스트 서버로 하기"**를 누르면 된다.
  게임 안에서 테스트 서버(`autoload/net/local_test_server.gd`, 127.0.0.1)가 열리고, 거기로 접속한다. 서버 주소 칸에 `test://local` 을 적어도 같다.
- 입장 정보는 진짜 서버에서 찍어 둔 것을 쓴다(`data/testserver/welcome.json`). 그래서 섬·나무·주민·상점·시세가 진짜 서버와 똑같이 보인다.
  - 서버 데이터나 프로토콜을 바꿨으면 `node server/tools/make_test_snapshot.js` 로 다시 찍는다.
- 테스트 서버가 직접 하는 일 (혼자 노는 데 필요한 것):
  - 걷기, 가방(옮기기·버리기·손에 들기)
  - 주민 대화(친밀도·수다), 나무 베기(그루터기 → 다시 자람), 낚시(입질·챔질)
  - 들판 채집, 씨앗 심기·꽃 따기, 옷 입기, 거울 얼굴
  - 상점 드나들기·사고팔기, 마을 가구 놓기·줍기
  - **아파트 집 구경과 꾸미기** — 테스트 서버에서는 어느 집이든 내 집처럼 꾸밀 수 있다.
  - (v0.11) 낚시 끌어올리기 연타, 주민 마을톡(답장 · 친한 주민의 먼저 연락), 가까이 선 친한 주민의 먼저 말 걸기.
  - 나무·꽃은 진짜 서버보다 10배 빨리 자란다.
- 여럿이 하는 일·경제(식당·증권·은행·동사무소·혼인신고·여울 그물·삽·마을톡 친구 대화)는 "테스트 서버에서는 아직 안 되는 기능이에요"로 알려 준다.
- 혼자만 들어가며, 상태는 기기의 `user://test_server.json` 에 남는다.

### PC 의 진짜 서버로: 같은 와이파이
- PC 에서 저장소 맨 위의 **`server.bat`** 을 더블클릭한다. 하는 일:
  - 코드 받기(`git pull`), 패키지 설치
  - 8080 포트 정리: 전에 켠 서버가 아직 포트를 잡고 있으면(`EADDRINUSE: address already in use :::8080`) 그 옛 서버를 끄고 새 코드로 다시 켠다. 다른 프로그램이 쓰고 있으면 8081, 8082… 로 바꿔 켠다.
  - 폰에 적을 주소(`ws://192.168.x.x:포트`)를 알려 준다. 172.x 주소는 WSL/Hyper-V 것이라 폰에서 닿지 않는다.
- 직접 켜려면 `cd server && npm start`. 포트를 바꾸려면 `set PORT=8081` 뒤에 `npm start`.
- 폰의 서버 주소 칸에 PC 의 내부 IP 를 적는다 (`ws://192.168.0.5:8080`). `127.0.0.1` 은 폰 자기 자신이라 PC 에 닿지 않는다.
- 에뮬레이터라면 `ws://10.0.2.2:8080` 이 PC 를 가리킨다.
- PC 방화벽에서 8080 포트를 열어야 한다.

### 안드로이드 내보내기 설정 (Godot 의 Project → Export → Android)
- **Permissions → Internet 을 켠다.** 꺼져 있으면 진짜 서버는 물론, 앱 안 테스트 서버(127.0.0.1)에도 소켓을 열 수 없다.
  - 안드로이드는 같은 기기 안의 연결에도 이 권한을 요구한다. "연결이 안 된다"의 가장 흔한 원인이다.
- 안드로이드 9 이상은 암호화되지 않은 연결(`ws://`)을 막을 수 있다. 출시용·외부 서버는 `wss://`(아래 Caddy · Fly.io)를 쓰는 것이 안전하다.
  - 내부 IP 로 테스트하다 막히면 Gradle 빌드의 매니페스트에서 cleartext 를 허용한다.

## 2. 서버를 항상 켜 두려면 — 무엇을 쓸까

서버(`server/`)의 특성:
- 방이 **한 프로세스의 메모리**에 있다.
- 저장은 **JSON 파일**(`SAVE_DIR`)이다.
- 접속은 오래 붙어 있는 **WebSocket** 이다.

그래서 아래가 필요하다:
- **늘 켜져 있는 작은 가상 서버(VM) 하나**
- 디스크
- `wss://` 인증서

요청이 올 때만 깨어나는 서버리스(Cloud Run · Lambda)나 잠드는 무료 호스팅은 맞지 않는다. 연결이 끊기고, 파일이 사라지기 때문이다.

| 추천 | 무엇 | 왜 |
|---|---|---|
| **1순위** | 서울 리전의 작은 리눅스 VM (AWS Lightsail · Vultr · 네이버클라우드 등, 가장 작은 요금제) + `systemd` + Caddy | 한국 플레이어 지연이 가장 짧다. 설정이 단순하고 저장 파일이 디스크에 그대로 남는다. 월 고정비가 작다 |
| 무료로 시작 | Oracle Cloud Always Free (춘천·서울 리전 ARM VM) + 같은 설정 | 무료. 다만 가입 심사가 있고, 오래 놀리면 회수될 수 있다 |
| 도커로 편하게 | Fly.io (도쿄 `nrt`) + 볼륨 1GB, `server/deploy/fly.toml` | 배포와 HTTPS 가 자동이다. 기계 하나를 멈추지 않게 둬야 한다 (`auto_stop_machines = "off"`) |

요금·무료 범위는 자주 바뀌니 가입할 때 확인한다. 동시 접속이 많아져 한 프로세스로 모자라면, 그때 DESIGN.md 8·10장(전용 서버 + PostgreSQL)으로 옮긴다.

### VM 에 직접 (systemd + Caddy)
```bash
# Ubuntu 기준
sudo apt install -y nodejs npm caddy        # Node 20 이상 (낮으면 NodeSource 로 설치)
sudo useradd -r -s /usr/sbin/nologin solbaram
sudo mkdir -p /opt/solbaram /var/lib/solbaram/saves && sudo chown -R solbaram /var/lib/solbaram
sudo cp -r server data /opt/solbaram/ && (cd /opt/solbaram/server && sudo npm ci --omit=dev)
sudo cp server/deploy/solbaram.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now solbaram
sudo cp server/deploy/Caddyfile /etc/caddy/Caddyfile   # game.example.com 을 내 도메인으로
sudo systemctl reload caddy
```
- 앱의 서버 주소: `wss://내도메인`
- 꺼지면 `systemd` 가 다시 켜고, 끌 때(SIGTERM)는 방을 저장한다.
- 저장 파일은 `/var/lib/solbaram/saves`. 이 폴더를 매일 백업한다.

### 도커
```bash
docker build -f server/Dockerfile -t solbaram-server .     # 저장소 맨 위에서 (data/ 를 같이 넣는다)
docker run -d --restart unless-stopped -p 8080:8080 -v solbaram-saves:/srv/saves --name solbaram solbaram-server
```

### 업데이트
- 서버를 올리기 전에 저장 폴더를 백업한다. 프로토콜이 바뀌면(`PROTOCOL_VERSION`) 앱도 같이 올린다. v0.11 은 프로토콜 11 — 서버와 앱을 함께 올린다 (예전 앱은 `bad_version` 으로 막힌다).
- 앱 안 테스트 서버의 입장 정보(`make_test_snapshot.js`)도 다시 찍는다.
