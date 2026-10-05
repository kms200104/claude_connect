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
| 바닥 텍스처 (리소스팩) | `assets/packs/low/`, `assets/packs/high/` | `tools/art/gen_ground.py` 로 생성 | 프로젝트 | 마을 바닥 (화질별 해상도) |
| 효과음 (발소리 제외) · 첫 화면 음악 | `assets/audio/sfx/`, `assets/audio/music/title_theme.ogg` | `tools/audio/gen_audio.py` 로 합성 (외부 샘플 없음) | 프로젝트 | 소리 |
| 발소리 18개 (풀·흙·달리기·나무·돌·금속·물) | `assets/audio/sfx/step_*.wav` | Freesound (swuing · Ali_6868 · Eelke · EminYILDIRIM), 자세한 출처는 `assets/audio/CREDITS.md` | CC BY 3.0 (일부 CC0) — **출처 표시 필요** | 발소리 |
| 마을 음악 4곡 (낮·밤·비·이벤트) | `assets/audio/music/{village,night,rain,event}_theme.ogg` | 받은 파일 (`game_audio.zip`) | **미기재 — 공개 전 확인 필요** | 배경음악 |
| 식재료·요리 아이콘 38장 (v0.8) | `assets/icons/items/` (식재료 21) · `assets/icons/dishes/` (요리 17) | 게임 모형(`items.json` · `recipes.json` 의 model)을 `tools/render_icons.tscn` 으로 찍음 | 프로젝트 자체 제작 | 아이템 칸 · 주문 말풍선 · 주방 창 |
| 식당 효과음 6개 (v0.8) | `assets/audio/sfx/{cook_chop,cook_sizzle,cook_bubble,cook_plate,order_bell,cash_in}.wav` | `tools/audio/gen_cook_sfx.py` 로 합성 (외부 샘플 없음) | 프로젝트 | 요리·주문·계산 |
| 아파트·식당·부동산 부스 모형 (v0.8) | `game/places/apartment_site.gd` · `restaurant_site.gd` | 코드로 빚음 (`PartMesh`) | 프로젝트 | 마을 건물 |
| 도구·조개·땅 속 물건·조개 요리 아이콘 14장 (v0.9) | `assets/icons/items/` (뜰채 그물·삽·바지락·개조개·맛조개·키조개·재첩·화석·옛날 동전·동글 조약돌) · `assets/icons/dishes/` (바지락 칼국수·재첩국·맛조개 구이·키조개 관자 구이) | 게임 모형(`items.json` · `recipes.json` 의 model)을 `tools/render_icons.tscn` 으로 찍음 | 프로젝트 자체 제작 | 아이템 칸 · 주문 말풍선 |
| 동사무소 건물·창구 · 여울(얕은 물) · 물고기 떼 · 조개 숨구멍 · 구덩이/흙길 · 첫 화면 구름 (v0.9) | `game/places/civic_site.gd` · `game/fishing/fishing_spot.gd` · `game/field/field_controller.gd` · `ui/title/title_screen.gd` | 코드로 빚음 (`PartMesh`, `ClayMesh`) | 프로젝트 | 마을 건물·물가·땅 |
| 가구 아이콘 11장 (v0.10) | `assets/icons/items/` (TV · 스탠드 에어컨 · 선풍기 · 더블/싱글 침대 · 4인 식탁 · 양문형 냉장고 · 옷장 · 책상 세트 · 패브릭 소파 · 드럼 세탁기) | 게임 모형(`items.json` 의 model)을 `tools/render_icons.tscn` 으로 찍음 | 프로젝트 자체 제작 | 아이템 칸 · 꾸미기 |
| 아파트 평면도 데이터 (v0.10) | `data/realestate/floorplans.json` (방 사각형 · 문 · 현관 좌표) | 프로젝트 오너가 준 푸르지오 평면도 그림 4장(네이버 부동산 평면도 이미지)을 보고 좌표만 옮겨 적음 — 그림 자체는 저장소에 넣지 않았다 | 평면 배치 참고 — 공개 전 사용 범위 확인 필요 | 집 안 벽·바닥 |
| 집 안 벽·바닥·붙박이 (v0.10) | `game/home/home_interior.gd` | 평면도 데이터로 코드가 빚음 (`PartMesh`) | 프로젝트 | 아파트 집 안 |
