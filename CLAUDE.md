# 솔바람 마을 — Godot 4.5+ · 3D · 모바일 세로 · 2인 협동 (상세: DESIGN.md)
- **폴더**: `autoload/`(전역 싱글턴 최소화) `core/`(클라·서버 공용, 렌더링 의존 금지) `game/`(기능별 씬+스크립트) `ui/` `server/`(서버 전용, 클라 export 제외) `data/`(정적 데이터) `assets/` `art_source/`(.gdignore) `tests/` `tools/` `docs/`
- 파일·폴더는 snake_case, 노드명은 PascalCase. 기능(feature) 단위로 씬과 스크립트를 같은 폴더에 둔다.
## GDScript
- 정적 타입 필수: 변수·인자·반환형 모두 명시 (`var hp: int`, `func f(a: float) -> void`). `:=`는 타입이 자명할 때만.
- 타입 없는 `Variant`, 무분별한 `Dictionary`/`get_node` 문자열 경로 지양 → `@export`/`@onready var x: Type`, 데이터는 Resource 클래스.
## 3D 성능 (Mobile 렌더러, 60fps, 프레임 16.6ms, 기준 기기 갤럭시 S24 · Z 폴드7)
- 폴리곤 예산: 캐릭터 ≤8,000tri(고화질 12,000), 나무 2,500, 집 4,000, 소형 소품 300, 가구 300/800/1,500, 방 합계 50k. 마을은 합계가 아니라 **화면 안** 기준 (그린 삼각형 ≤ 200k, `tools/art_preview.tscn -- --what=village --stats` 로 잰다).
- Tripo 모형(`tools/blender/import_tripo.py`)은 예외: 고화질은 원본 폴리곤 그대로(텍스처 + 임포트 자동 LOD), 절약 화질은 위 예산까지 줄인 `<id>_low.glb` 를 쓴다.
- 반복 물체(풀·꽃·울타리·조약돌)는 반드시 `MultiMeshInstance3D` 이고, 마을 전체 한 덩어리가 아니라 12m 칸으로 나눠 visibility range 를 건다. 세트별 공용 아틀라스 머티리얼 1개, 투명 머티리얼은 화면 내 10개 이하(알파 블렌드 대신 알파 시저).
- 노멀맵·블렌드셰이프·캐릭터 LOD 없음, 셰이더 8개 이하, 작은 소품은 visibility range 지정.
## 서버
- 서버가 권위: 클라이언트가 보내는 건 항상 "요청", 결과는 서버 응답으로만 확정 (낚시·배치·상점·인벤토리).
- 서버는 물리 시뮬레이션 없이 영역·거리·격자 검사만. 요청 ID로 중복 처리 방지, 초당 요청 제한, 프로토콜·데이터 버전 검사.
- 판정은 클라이언트가 보낸 경과 시간 기준(지연 불이익 없음). 게임 규칙은 `core/rules/`에 두고 클라·서버가 공유.
## 작업 범위
- **요청한 범위 밖은 수정하지 않는다.** 필요해 보이는 리팩터링·정리·포맷 변경은 하지 말고 제안만 한다.
