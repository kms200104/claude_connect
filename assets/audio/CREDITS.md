# 소리 크레딧

솔바람 마을의 효과음·배경음악 출처. 소리를 더하거나 바꾸면 여기에 적는다 (`docs/licenses/ASSET_LEDGER.md` 의 소리 줄도 함께).

## 합성 (프로젝트 자체 제작)

`tools/audio/gen_audio.py` 로 만든 오리지널 (외부 샘플 없음). 아래 "받은 파일"을 뺀 `assets/audio/sfx/*.wav` 전부와 `assets/audio/music/title_theme.ogg`.
낚시·도끼질·주민 말소리·비·천둥·새·풀벌레·UI·이벤트·감정표현·브레이크·비행기 등.

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
