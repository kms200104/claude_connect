# 자산 원장 (ASSET_LEDGER)

게임에 들어간 외부·참고 자산의 출처와 라이선스. 새 자산을 넣을 때마다 한 줄씩 더한다.

| 자산 | 위치 | 출처 | 라이선스 | 쓰임 |
|---|---|---|---|---|
| 주아체 (Jua) | `assets/fonts/jua_regular.ttf` | Google Fonts, The Jua Project Authors (우아한형제들) | SIL OFL 1.1 (`assets/fonts/LICENSE.txt`) | UI 기본 글꼴 |
| 고운돋움 기호 부분집합 | `assets/fonts/gowun_dodum_symbols.ttf` | Google Fonts, The Gowun Dodum Project Authors — `pyftsubset` 으로 기호 18자만 추림 | SIL OFL 1.1 (같은 파일) | 주아체에 없는 기호 폴백 |
| 참고 이미지 5장 | `art_source/reference/` | 프로젝트 오너가 제공한 아트 방향 이미지 (생성형 AI 표시 있음) | 오너 제공 — 출시 전 사용 정책 확인 필요 (DESIGN 13장 14번) | 아트 방향, 아래 오린 그림의 원본 |
| 로고 | `assets/ui/logo.png` | 참고 이미지 `logo_icons.webp` 에서 오림 | 위와 같음 | 첫 화면 |
| HUD 아이콘 3장 | `assets/ui/icons/` (낚시·상점·지도) | 참고 이미지 `logo_icons.webp` 에서 오림 | 위와 같음 | 상황 버튼 |
| 아이템 아이콘 12장 | `assets/icons/items/` (`tools/render_icons.gd` 의 `HAND_MADE`) | 참고 이미지 `furniture.png`, `fishing_items.png` 에서 오림 | 위와 같음 | 아이템 칸 |
| 아이템 아이콘 50장 | `assets/icons/items/` (그 밖) | 게임 모형을 `tools/render_icons.tscn` 으로 찍음 | 프로젝트 자체 제작 | 아이템 칸 |
| 3D 모형 전부 | `game/**` 코드 (`ClayMesh`, `CharacterModel`, `PartMesh` 데이터) | 프로젝트 자체 제작 (참고 이미지를 보고 새로 빚음, 트레이싱 없음) | 프로젝트 | 캐릭터·나무·집·가구 |
| 바닥 텍스처 | `assets/textures/` | `tools/art/gen_ground.py` 로 생성 | 프로젝트 | 마을 바닥 |
| 효과음 39개 · 배경음악 2곡 | `assets/audio/` | `tools/audio/gen_audio.py` 로 합성 (외부 샘플 없음) | 프로젝트 | 소리 |
