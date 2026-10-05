# 상점·도구 Tripo 제작 가이드 (폴리곤 상한 · 프롬프트)

목표: 아기자기한 생활 게임 느낌(둥글고 통통한 장난감 비율, 파스텔, 무광 점토/플라스틱 질감)으로 상점 3단계 + 도구 7종을 다시 만든다.
기준 예산: CLAUDE.md · DESIGN.md 5.5~5.7 (모바일 30fps).

> 저작권: 화풍(둥근 비율·색감·무광 질감)은 맞춰도 되지만, 특정 게임의 건물·도구 디자인·로고·간판 글씨를 그대로 베끼면 출시 때 문제가 된다.
> 프롬프트에 게임 이름을 넣지 말고, 아래처럼 "형태 특징"으로만 설명한다. 레퍼런스 이미지도 원본 스크린샷 대신 직접 그린 스케치나 직접 찍은 사진을 쓴다.

## 1. 폴리곤·텍스처 상한

Tripo 는 사각형(quad) 기준으로 면 수를 보여 줄 수 있다. **게임 예산은 삼각형 기준이라 quad 수 × 2** 로 계산한다.

| 대상 | 크기 (가로×높이×깊이 m) | 삼각형 목표 / 상한 | 텍스처 (Albedo만) | 비고 |
|---|---|---|---|---|
| 상점 1단계 · 구멍가게(나무 노점) | 4.5 × 2.8 × 3.5 | 3,000 / 4,000 | 1024² 1장 | 현재 3,432 |
| 상점 2단계 · 잡화점 | 6.5 × 3.4 × 5.0 | 3,500 / 4,000 | 1024² 1장 | 현재 3,964 |
| 상점 3단계 · 백화점 | 9.0 × 4.6 × 6.5 | 3,500 / 4,000 | 1024² 1장 | 현재 3,370 |
| 상점 창문 (밤에 빛남) | 건물에 포함 | 건물 상한 안 | 같은 텍스처의 별도 머티리얼 | 유리는 불투명 + 발광색 (알파 블렌드 금지) |
| 실내 방 셸 (벽·바닥·문) | 8×7 / 10×8 / 12.5×9.5, 높이 3 | 1,500 / 2,000 | 512² 타일 | |
| 계산대 | 약 2.2 × 1.0 × 0.8 | 1,000 / 1,500 | 실내 세트 아틀라스 1024² | 가구 대 |
| 진열 선반 | 약 1.6 × 1.8 × 0.5 | 600 / 800 | 같은 아틀라스 | 가구 중 |
| 샹들리에 (3단계) | 지름 약 1.0 | 600 / 800 | 같은 아틀라스 | 카메라를 가리지 않게 낮고 작게 |
| 과일 상자·종·간판 등 소품 | 0.2~0.8 | 200 / 300 | 같은 아틀라스 | 소형 소품 |
| 낚싯대 | 길이 약 1.2 | 300 / 400 | 공용 도구 아틀라스 1024² (칸 256²) | 현재 500 (예산 초과) |
| 도끼 | 길이 약 0.6 | 200 / 300 | 공용 도구 아틀라스 | |
| 뜰채 | 길이 약 0.9, 그물 지름 0.4 | 300 / 400 | 공용 도구 아틀라스 | 그물은 알파 시저 텍스처 또는 통짜 반투명색 |
| 삽 | 길이 약 0.9 | 200 / 300 | 공용 도구 아틀라스 | |
| 식칼 | 길이 약 0.32 | 120 / 200 | 공용 도구 아틀라스 | 적용됨 |
| 프라이팬 | 지름 약 0.4 + 손잡이, 길이 0.5 | 200 / 300 | 공용 도구 아틀라스 | 적용됨 |
| 국자 | 길이 약 0.4 | 200 / 300 | 공용 도구 아틀라스 | 적용됨 |

공통 규칙
- 노멀맵·러프니스·메탈릭 맵은 버린다. **Albedo(색) 텍스처 1장만**.
- 도구 7종은 텍스처를 한 장(1024², 256² 칸 16개)에 모아 머티리얼 1개를 같이 쓴다. 실내 소품도 세트 아틀라스 1장.
- 텍스처 최대 1024². Tripo 가 2048² 로 주면 줄인다.
- 원점(피벗): 도구는 **손잡이 쥐는 곳**, +Y 방향으로 뻗게. 건물은 **앞면(문) 가운데 바닥**, 건물은 -Z 쪽으로.
- 단위 미터, 크기는 위 표에 맞춘다.

## 2. 공통 스타일 문구

모든 프롬프트 뒤에 붙인다.

```
cozy life-sim game asset, chunky rounded toy-like proportions, soft bevelled edges, simplified shapes,
slightly oversized and stubby, clean readable silhouette from a top-down camera,
hand-painted flat colors with very soft gradients, pastel warm palette, matte clay and painted wood finish,
no text, no logo, no fine detail, low poly, game-ready, single object, centered, plain background
```

네거티브 (Tripo 에 네거티브 칸이 없으면 생략):

```
realistic, photoreal, PBR scratches, rust, grime, sharp edges, thin fragile parts, noisy texture,
detailed wood grain, text, letters, logo, brand, character, people
```

## 3. 상점

### 1단계 · 구멍가게 (나무 노점)
```
small wooden market stall shop, plank walls in warm honey brown, puffy rounded red roof like a cushion,
red and cream striped awning with scalloped bubbly edge, wooden crates of round fruit in front,
little golden bell hanging by the door, small green leaf-shaped sign board without letters,
single front door, 4.5m wide, 2.8m tall
```

### 2단계 · 잡화점
```
cute general store building, cream plaster walls with rounded corners, two-tier teal rounded roof,
coral pink striped awning with scalloped edge over big square windows, flower boxes under the windows,
round bushes beside the door, wooden double door with round handle, chimney with soft rounded top,
6.5m wide, 3.4m tall
```

### 3단계 · 백화점
```
small toy-like department store, pale marble walls, gold trim band along the roofline,
round white columns at the entrance, short front steps with red carpet, large arched windows,
small golden spire on the roof, symmetric facade, chunky rounded shapes, 9m wide, 4.6m tall
```

### 실내
```
shop counter, rounded wooden counter with cream top, small cash box and bell on top, 2.2m wide
```
```
shop display shelf, three rounded wooden shelves with soft corners, open front, 1.6m wide, 1.8m tall
```
```
small chandelier, gold frame with five round warm glowing bulbs, compact and low, 1m wide
```

## 4. 도구

```
fishing rod, stubby bamboo rod with rounded segment joints, chunky red and white reel, cork grip wrapped with cloth,
thick tip with a small round ring, 1.2m long
```
```
small hand axe, short chunky wooden handle with rounded end, thick rounded gray-blue metal head with soft edges,
toy-like proportions, 0.6m long
```
```
landing fishing net, long wooden handle, round metal hoop, deep soft net bag in light blue,
simplified net pattern painted on the texture, 0.9m long
```
```
garden shovel, wooden handle with round D-grip, chunky rounded gray metal blade, short stubby proportions, 0.9m long
```
```
kitchen knife, chunky rounded blade with soft tip, wooden handle with two round rivets, 0.3m long
```
```
frying pan, round thick pan with dark gray inside and warm red outside, short wooden handle, 0.3m diameter
```
```
soup ladle, deep round bowl, curved handle with rounded end, warm wooden handle, 0.35m long
```

## 5. Tripo → 게임 넣기

### 자동 변환 (적용된 방식)
`art_source/tripo/<이름>.glb` 에 원본을 넣고 `tools/blender/import_tripo.py` 의 `ASSETS` 에 한 줄 더한 뒤
`python3 tools/blender/import_tripo.py [id …]` (pip install bpy). 바탕색 텍스처를 정점 색으로 굽고, 방향·크기·원점을 맞춰
`assets/models/items/<id>.glb`(고화질 — **원본 폴리곤 그대로**)와 `<id>_low.glb`(절약 — 위 표의 상한까지 줄임, 이미 상한 안이면 만들지 않음)를 낸다.
게임은 화질 설정(`presets.json` 의 `models`)에 따라 고르고, 화질을 바꾸면 집·상점·손에 든 도구가 바로 바뀐다.
코드 쪽 머티리얼은 그대로(흰 툰 머티리얼)라 아래 "주의 1" 의 A 방식이다.

| id | 원본 | 고화질 / 절약 (tri) | 크기 | 쓰는 곳 |
|---|---|---|---|---|
| `tool_pan` | `pan.glb` | 1,910 / 291 | 길이 0.5m | 요리 프라이팬 (`CharacterModel.pan`) |
| `tool_ladle` | `ladle.glb` | 1,796 / 290 | 길이 0.42m | 요리 국자 (`CharacterModel.ladle`) |
| `tool_knife` | `knife.glb` | 1,896 / 193 | 길이 0.32m | 요리 식칼 (`CharacterModel.knife`) |
| `npc_house` | `house.glb` | 4,827 / 3,879 | 3.8×4.2×3.9m, 문 +Z | 주민 집 6채 전부 (`NpcCrowd`) |
| `shop_ext_1` | `shop_1.glb` | 3,692 / 같음 | 4.5×4.0×2.8m | 구멍가게 바깥 (`ShopController`) |
| `shop_ext_2` | `shop_2.glb` | 3,798 / 같음 | 6.5×5.9×5.2m | 잡화점 바깥 |
| `shop_ext_3` | `shop_3.glb` | 5,711 / 3,880 | 9.0×6.0×5.7m | 백화점 바깥 |
| `shop_counter` | `shop_counter.glb` | 1,324 / 같음 | 2.0×1.2×1.7m | 상점 계산대 (모든 단계, `ShopBuilder.counter_model`) |

### 손으로 할 때

1. Tripo 에서 생성 → 면 수 설정이 있으면 위 목표치(quad 면 수 = 삼각형 목표 ÷ 2)로 받는다. 없으면 Blender Decimate 로 줄인다.
2. Blender: 크기·원점 맞추기 → 노멀·러프니스 맵 제거 → 텍스처 1024² 이하로 → 도구는 아틀라스 한 장으로 UV 합치기.
3. `.glb` 로 내보내 `assets/models/items/` 에 넣는다. 상점은 이 이름이면 코드 변경 없이 바로 바뀐다 (`PartMesh.get_mesh` 가 같은 이름의 glb 를 먼저 찾는다).

| 파일 이름 | 내용 |
|---|---|
| `shop_ext_1.glb` · `shop_ext_2.glb` · `shop_ext_3.glb` | 단계별 상점 바깥 (창문 유리 빼고) |
| `shop_win_1.glb` · `shop_win_2.glb` · `shop_win_3.glb` | 단계별 창문 유리만 (밤에 빛나는 머티리얼로 따로 그린다) |
| `shop_room_1.glb` · `shop_room_2.glb` · `shop_room_3.glb` | 단계별 실내 한 벌 (벽·바닥·문·계산대·선반을 **메시 하나로 합쳐서**) |
| `shop_chandelier.glb` | 3단계 샹들리에 |

4. 넣은 뒤 `tools/art_preview.tscn -- --what=compare --ids=...` 로 기존 모형과 나란히 비교한다.

> 주의 1 (텍스처): 지금 게임은 캐릭터·도구·건물을 **정점 색 + 흰 툰 머티리얼 하나**(`clay_material` / `foliage.tres`)로 덮어 그린다.
> 텍스처를 입힌 glb 를 넣어도 이 덮어쓰기 때문에 텍스처가 보이지 않는다. 둘 중 하나를 골라야 한다.
> - A. Blender 에서 텍스처를 **정점 색으로 굽기** (Bake → Color Attribute). 코드 변경 없음. 색면이 단순한 이 화풍에 잘 맞는다. 대신 무늬가 작으면 뭉개진다.
> - B. 텍스처를 쓰는 툰 머티리얼(공용 아틀라스 1개)을 추가하고 glb 를 쓸 때는 덮어쓰지 않게 코드를 바꾼다. 셰이더는 6종이 되어 예산(8) 안이다.
>
> 주의 2 (도구): 도구 7종(낚싯대·도끼·뜰채·삽·식칼·프라이팬·국자)은 모두 `CharacterModel` 코드로 빚고 있어서 glb 를 넣어도 바뀌지 않는다. 도구용 glb 를 읽는 코드를 더해야 한다.
