# 소리 크레딧

솔바람 마을의 효과음·배경음악 출처. 소리를 더하거나 바꾸면 여기에 적는다 (`docs/licenses/ASSET_LEDGER.md` 의 소리 줄도 함께).

## 합성 (프로젝트 자체 제작)

`tools/audio/gen_audio.py` 로 만든 오리지널 (외부 샘플 없음): 주민 말소리 `voice_a/e/i/o/u.wav` 와 `assets/audio/music/title_theme.ogg`.
나머지 효과음 · 환경음은 아래 "받은 파일" (발소리 · 실제 녹음 CC0).

## 받은 파일

### 발소리 — `assets/audio/sfx/step_*.wav`

`step_grass_1~3` · `step_dirt_1~3` · `step_run_1~3` · `step_wood_1~2` · `step_stone_1~3` · `step_metal_1~2` · `step_water_1~2`

원문 (`CREDITS_footsteps.txt`):

```
Footstep sounds (CC BY 3.0, 일부 CC0): Freesound
- grass/wood/tile(stone): swuing (freesound.org/people/swuing/sounds/38874, 38873, 38876)
- dirt(gravel): Ali_6868 (freesound.org/people/Ali_6868/packs/21608)
- metal: Eelke (freesound.org/people/Eelke/sounds/462598)
- water: EminYILDIRIM (freesound.org/people/EminYILDIRIM/sounds/608663)
CC BY 3.0 requires attribution; 개인용이면 문제 없지만 공개 시 이 파일을 크레딧에 포함하세요.
```

| 재질 | 파일 | 만든 사람 | 출처 | 라이선스 |
|---|---|---|---|---|
| 풀 · 나무 · 돌(타일) | `step_grass_*`, `step_run_*`, `step_wood_*`, `step_stone_*` | swuing | https://freesound.org/people/swuing/sounds/38874 · 38873 · 38876 | CC BY 3.0 (일부 CC0) |
| 흙(자갈) | `step_dirt_*` | Ali_6868 | https://freesound.org/people/Ali_6868/packs/21608 | CC BY 3.0 (일부 CC0) |
| 금속 | `step_metal_*` | Eelke | https://freesound.org/people/Eelke/sounds/462598 | CC BY 3.0 (일부 CC0) |
| 물 | `step_water_*` | EminYILDIRIM | https://freesound.org/people/EminYILDIRIM/sounds/608663 | CC BY 3.0 (일부 CC0) |

CC BY 3.0 은 출처 표시가 필요하다 — 게임을 공개할 때 이 표를 게임 안 크레딧(또는 스토어 설명)에 넣는다.
`step_run_*` 은 원문에 따로 적혀 있지 않아 풀 발소리와 같은 묶음으로 적었다 (확인 필요).

### 마을 배경음악 — `assets/audio/music/`

`village_theme.ogg`(낮) · `night_theme.ogg`(밤) · `rain_theme.ogg`(비) · `event_theme.ogg`(이벤트) — 44.1kHz 스테레오 Vorbis.

받은 묶음(`game_audio.zip`)에 음악의 출처·라이선스는 적혀 있지 않았다. **공개 전에 출처와 라이선스를 확인해 이 칸을 채운다.**

### 식당 음악 (v0.18) — `tools/audio/gen_kitchen_music.py`

`restaurant_theme.ogg`(식당 개업 · 120 BPM C장조) · `cooking_theme.ogg`(통통 주방 · 약 112 BPM F장조, 리듬 요리의 박자 격자 536 ms) — 이 프로젝트에서 작곡.
악기 소리는 모두 **CC0** 실제 녹음 샘플이다 (lavenderdotpet/CC0-Public-Domain-Sounds 묶음):

- 베이스: bb - Novice Cello (C2 · G2 · D3 · A3 피치카토) — Ben Burnes
- 멜로디 · 화음: Kenney Music Jingles (스틸팬 STEEL00/02 · 피치카토 PIZZI00/02 의 끝음) — Kenney
- 드럼: BB 2HTC 드럼 (킥 · 스네어 · 박수 · 하이햇 · 트라이앵글 · 딱딱이) — Ben Burnes

### 실제 녹음 효과음 · 환경음 (CC0) — `tools/audio/import_cc0_sfx.py`

합성 파형이던 효과음 49개를 실제 녹음으로 바꿨다 (주민 말소리 `voice_*` 만 합성으로 남음). 모두 **CC0** 이라 출처 표시는 필요 없지만 고마움을 담아 적는다.
원본은 아래 두 저장소에서 받아, 스크립트가 자르고 · 겹치고 · 음높이와 크기를 맞춰 만든다 (어느 파일의 몇 초를 썼는지는 스크립트의 `RECIPES`).
앞서 넣었던 Cozy Farm SFX · Ylmir 빗소리 · DoKashiteru 천둥 (`tools/audio/import_real_sfx.py`)은 이것으로 대체했다.

- 묶음 저장소: https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds (CC0 1.0)
- 환경음 저장소: https://github.com/mateusfg7/noisekun (`.github/assets/sounds`, README 의 크레딧 표 기준 CC0 인 것만)

| 소리 | 파일 | 원본 묶음 · 만든 사람 | 라이선스 |
|---|---|---|---|
| 찌 착수 · 입질 · 끌어올림 · 놓침 | `fish_plop`, `fish_nibble`, `fish_bite`, `fish_catch`, `fish_escape` | 40 CC0 water / splash / slime SFX · 100 CC0 SFX — rubberduck (OpenGameArt) | CC0 |
| 낚싯대 휘두르기 | `fish_cast` | Micro Pack - Organic Wooshes — Ben Burnes | CC0 |
| 줄 풀림 · 릴 감기 · 카메라 셔터 | `line_zip`, `fish_reel`, `camera_shutter` | bb - Smol Mechanisms — Ben Burnes | CC0 |
| 도끼질 · 나무 삐걱 · 쓰러짐 | `chop`, `tree_creak`, `tree_land` | Kenney RPG Audio · Kenney Impact Sounds — Kenney · 100 CC0 wood and metal SFX · 75 CC0 breaking/falling/hit SFX — rubberduck · Leaves — Stek59 (Freesound, Noisekun) | CC0 |
| 자람 | `grow` | Leaves — Stek59 (Freesound, Noisekun) | CC0 |
| 땅 파기 · 미끄러짐 | `dig`, `skid` | 25 CC0 mud SFX — rubberduck · BB Retail Therapy — Ben Burnes · Kenney Impact Sounds | CC0 |
| 줍기 · 킥보드 걸쇠 · 화면 열기/닫기 | `pickup`, `kick_latch`, `ui_open`, `ui_close` | Kenney RPG Audio — Kenney | CC0 |
| 칼질 | `cook_chop` | Micro Pack - Kitchen Knives — Ben Burnes · 100 CC0 wood and metal SFX — rubberduck | CC0 |
| 지글지글 | `cook_sizzle` | Fire Wood — SFX Producer (Noisekun) · BB Retail Therapy — Ben Burnes | CC0 |
| 보글보글 | `cook_bubble` | 30 CC0 SFX loops · 40 CC0 water SFX — rubberduck | CC0 |
| 접시 · 주문 종 · 가게 문 종 | `cook_plate`, `order_bell`, `door_bell` | 100 CC0 SFX — rubberduck | CC0 |
| 동전 · 계산 | `coin`, `cash_in` | 80 CC0 RPG SFX · 100 CC0 SFX — rubberduck | CC0 |
| 킥보드 차기 · 브레이크 · 구름 | `kick_push`, `kick_brake`, `kick_roll_loop` | Kenney Impact Sounds · BB Retail Therapy — Ben Burnes · 30 CC0 SFX loops — rubberduck | CC0 |
| 감정표현 · 팡파르 · 퀘스트 · 레벨 업 · 이벤트 | `emote_up`, `emote_down`, `emote_hey`, `fanfare_small`, `fanfare_big`, `quest_done`, `level_up`, `event_start` | Kenney Music Jingles (피치카토 · 스틸팬) — Kenney | CC0 |
| 펑 (감정표현) | `emote_pop` | BB Retail Therapy (코르크 뚜껑) — Ben Burnes | CC0 |
| 반짝 | `twinkle` | Kenney Impact Sounds (유리) — Kenney | CC0 |
| 화면 단추 | `ui_click`, `ui_confirm`, `ui_cancel` | Kenney UI Audio — Kenney | CC0 |
| 새소리 · 풀벌레 · 비 · 비행기 | `birds_loop`, `crickets_loop`, `rain_loop`, `plane_loop` | Birds · Night · Rain · Airplane — SFX Producer (YouTube, Noisekun) | CC0 |
| 천둥 | `thunder_1`, `thunder_2` | Thunder Storm — Borys Kozielski (Freesound, Noisekun) | CC0 |
