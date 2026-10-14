#!/usr/bin/env python3
"""탕정 제2지구 강변도시 (v0.21) — 도시 바닥 데이터를 만든다.

- 곡교천: 서→동으로 흐르는 강 (가운데 줄 z_c(x), 반폭 w(x)). x = WEIR 의 보(수중보)를 경계로
  상류 = 낚시터 'seongseong' (예전 id 그대로 — 저장 · 도감 호환), 하류 = 낚시터 'sea' (기수역, 바다 물고기가 올라온다).
  두 윤곽은 data/fish/spots.json 에 쓴다 (반시계 = 넓이 양수, 예전 호수와 같은 방향).
- 도시 땅: village_layout.json 의 island (half · power) 안, 그리고 z <= island.south (강 건너는 갈 수 없다).
- data/world/city.json: 도로(가로 · 세로 직선), 구역(district), 회색 건물(buildings: 가운데 x,z · 너비 w · 깊이 d · 층 · 종류),
  강 건너 침수 구역(flood: 다각형 + 수면 높이), 둔치 자전거길 · 보(weir) 자리.
  서버(world.js blockedAreas)는 건물 사각형을 놓기 · 심기 금지 자리로, 클라이언트(CityDistricts)는 그림으로 쓴다.
사용: python3 tools/art/gen_city.py  (그다음 gen_lake_sdf.py · gen_ground.py · gen_aqua.py)
"""
import json
import math
import random
from pathlib import Path

from json_compact import dumps

ROOT = Path(__file__).resolve().parents[2]
SPOTS = ROOT / "data/fish/spots.json"
CITY = ROOT / "data/world/city.json"

X0, X1 = -480.0, 480.0
STEP = 8.0
WEIR = 60.0
SOUTH = 190.0  # 이 줄 남쪽(강 한가운데 너머)은 땅이 아니다.
HALF = 420.0   # 도시 땅 반경 (village_layout island.half)


def z_c(x: float) -> float:
    return 188.0 + 4.0 * math.sin(x / 90.0) + 2.0 * math.sin(x / 37.0 + 1.0)


def w(x: float) -> float:
    # 강 건너 침수 구시가지가 둔치에서 보이도록 너무 넓지 않게 (땅 휘기 0.0025 로 60m 앞이 9m 가라앉는다).
    return 21.0 + 4.0 * (x - X0) / (X1 - X0) + 1.2 * math.sin(x / 53.0)


def north(x: float) -> float:
    return round(z_c(x) - w(x), 2)


def south(x: float) -> float:
    return round(z_c(x) + w(x), 2)


def xs(a: float, b: float) -> list:
    out = []
    x = a
    while x < b - 1e-6:
        out.append(round(x, 2))
        x += STEP
    out.append(round(b, 2))
    return out


def outline(a: float, b: float) -> list:
    """a..b 구간 강 윤곽: 남쪽 가장자리 서→동, 북쪽 동→서 (x,z 평면 넓이 양수 = 예전 윤곽과 같은 방향)."""
    pts = [[x, south(x)] for x in xs(a, b)] + [[x, north(x)] for x in reversed(xs(a, b))]
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts.reverse()
    return pts


def bbox(pts: list) -> dict:
    x0 = min(p[0] for p in pts)
    x1 = max(p[0] for p in pts)
    z0 = min(p[1] for p in pts)
    z1 = max(p[1] for p in pts)
    return {"x": round((x0 + x1) / 2, 2), "z": round((z0 + z1) / 2, 2), "half_x": round((x1 - x0) / 2, 2), "half_z": round((z1 - z0) / 2, 2)}


def update_spots() -> None:
    doc = json.loads(SPOTS.read_text(encoding="utf-8"))
    for s in doc["spots"]:
        if s["id"] == "seongseong":
            o = outline(X0, WEIR)
            s.update(bbox(o))
            s["name"] = "곡교천"
            s["_comment"] = ("곡교천 상류 (v0.21 강변도시, tools/art/gen_city.py 가 만든다): 도시 남쪽을 서→동으로 흐르는 강, 보(x=%d) 위쪽. "
                             "id 는 예전 호수 그대로 (도감 · 저장 호환). 강물이 길어 물고기는 물가에 선 사람 둘레에 나타난다 (near_people)." % WEIR)
            s["near_people"] = True
            s["outline"] = o
            ford_x, bay_x = -70.0, -14.0
            s["shallows"][0].update({"name": "곡교천 여울", "x": ford_x, "z": round(north(ford_x) + 4.6, 2), "half_x": 4.0, "half_z": 3.0})
            s["shallows"][1].update({"name": "곡교천 물굽이", "x": bay_x, "z": round(north(bay_x) + 5.2, 2), "half_x": 3.0, "half_z": 4.0})
        elif s["id"] == "sea":
            o = outline(WEIR, X1)
            s.pop("kind", None)
            s.update(bbox(o))
            s["name"] = "곡교천 하류"
            s["_comment"] = ("곡교천 하류 기수역 (v0.21, gen_city.py): 보(x=%d) 아래 — 밀물 때 아산만 바닷물이 올라와 바다 물고기가 낚인다. "
                             "id 는 예전 '바다' 그대로 (도감 · 저장 호환)." % WEIR)
            s["near_people"] = True
            s["outline"] = o
        elif s["id"] == "lake":
            s["name"] = "중앙공원 연못"
            s["_comment"] = "중앙공원 서쪽 연못 (v0.21 강변도시). id · 물고기 31종 · 갈대 여울은 예전 그대로 — 도감 · 저장 데이터와 맞는다."
    # 키 순서를 읽기 좋게 (outline · shallows · fish 는 뒤로).
    order = ["id", "name", "_comment", "x", "z", "half_x", "half_z", "cast_range", "near_people", "outline", "shallows", "fish"]
    doc["spots"] = [{k: s[k] for k in order if k in s} | {k: v for k, v in s.items() if k not in order} for s in doc["spots"]]
    SPOTS.write_text(dumps(doc), encoding="utf-8")


# ---------------------------------------------------------------- 도시 (도로 · 구역 · 건물)

ROADS = [
    # 가로 (E-W): z, x 범위, 너비 (차도), 이름
    {"id": "riverside", "name": "강변로", "a": [-HALF, 104.0], "b": [HALF, 104.0], "w": 14.0},
    {"id": "cityhall", "name": "시청로", "a": [-HALF, -108.0], "b": [HALF, -108.0], "w": 14.0},
    {"id": "north", "name": "탕정로", "a": [-HALF, -262.0], "b": [HALF, -262.0], "w": 12.0},
    # 세로 (N-S)
    {"id": "west_av", "name": "서부대로", "a": [-98.0, -HALF], "b": [-98.0, 104.0], "w": 14.0},
    {"id": "east_av", "name": "동부대로", "a": [98.0, -HALF], "b": [98.0, 104.0], "w": 14.0},
    {"id": "west2", "name": "솔내길", "a": [-262.0, -HALF], "b": [-262.0, 104.0], "w": 12.0},
    {"id": "east2", "name": "역전로", "a": [262.0, -HALF], "b": [262.0, 104.0], "w": 12.0},
    {"id": "center_n", "name": "중앙로", "a": [0.0, -HALF], "b": [0.0, -108.0], "w": 12.0},
]
SIDEWALK = 3.0

# 구역: 이름, 사각형 (x0, z0, x1, z1), 종류. 시내(downtown)는 손으로 놓은 시설들이 있어 비워 둔다.
DISTRICTS = [
    {"id": "downtown", "name": "솔바람 시내 (중앙공원 · 상가)", "rect": [-91, -101, 91, 97], "kind": "downtown"},
    {"id": "estate", "name": "솔바람 리버파크 (1 · 2단지)", "rect": [-255, -101, -105, 97], "kind": "estate"},
    {"id": "west", "name": "솔내 옛마을 (빈집촌) · 리버시티", "rect": [-420, -101, -269, 97], "kind": "residential"},
    {"id": "east_market", "name": "탕정역 상권", "rect": [105, -101, 255, 97], "kind": "commercial"},
    {"id": "station", "name": "탕정역", "rect": [269, -101, 420, 97], "kind": "station"},
    {"id": "nw", "name": "솔내 주거지", "rect": [-420, -255, -105, -115], "kind": "residential"},
    {"id": "school", "name": "학교 · 도서관", "rect": [-91, -255, 91, -115], "kind": "civic"},
    {"id": "ne", "name": "업무지구", "rect": [105, -255, 420, -115], "kind": "office"},
    {"id": "industry", "name": "디스플레이 산업단지", "rect": [-420, -420, 420, -269], "kind": "industry"},
    {"id": "riverbank", "name": "곡교천 둔치", "rect": [-420, 111, 420, 150], "kind": "park"},
    {"id": "oldtown", "name": "강 건너 구시가지 (침수)", "rect": [-480, 222, 480, 470], "kind": "flooded"},
]

# 종류별 (층 범위, 너비 범위, 깊이 범위, 벽 색 후보)
KINDS = {
    "shop": ((2, 5), (12, 22), (10, 16), ["#E8DCCB", "#D9CDBE", "#F0E6D8", "#CFC4B6", "#E4D3BE"]),
    "office": ((8, 18), (18, 30), (14, 22), ["#B9C4CC", "#A8B4BE", "#C8D0D6", "#9AA8B4"]),
    "villa": ((3, 4), (10, 14), (10, 13), ["#E6D2BC", "#D8C0A6", "#EDE2D2", "#C9B39A"]),
    "factory": ((2, 3), (50, 90), (30, 55), ["#D4D8DC", "#C5CBD0", "#E1E4E6"]),
    "flooded": ((3, 6), (10, 18), (9, 14), ["#C9BCA8", "#B8AA94", "#D2C6B4", "#A99C88"]),
}


def place_in(rect: list, kind: str, rng: random.Random, count: int, gap: float = 6.0, avoid: list = ()) -> list:
    floors_r, w_r, d_r, colors = KINDS[kind]
    out = []
    taken = list(avoid)
    x0, z0, x1, z1 = rect
    tries = 0
    while len(out) < count and tries < count * 60:
        tries += 1
        bw = round(rng.uniform(*w_r), 1)
        bd = round(rng.uniform(*d_r), 1)
        cx = round(rng.uniform(x0 + bw / 2 + 2, x1 - bw / 2 - 2), 1)
        cz = round(rng.uniform(z0 + bd / 2 + 2, z1 - bd / 2 - 2), 1)
        r = (cx - bw / 2 - gap, cz - bd / 2 - gap, cx + bw / 2 + gap, cz + bd / 2 + gap)
        if any(not (r[2] < t[0] or r[0] > t[2] or r[3] < t[1] or r[1] > t[3]) for t in taken):
            continue
        taken.append((cx - bw / 2, cz - bd / 2, cx + bw / 2, cz + bd / 2))
        out.append({"kind": kind, "x": cx, "z": cz, "w": bw, "d": bd, "floors": rng.randint(*floors_r), "color": rng.choice(colors)})
    return out


def along_road(z_front: float, x0: float, x1: float, kind: str, rng: random.Random, facing: int) -> list:
    """길가 상가 줄: 앞면이 길(z_front)에서 인도만큼 떨어져 나란히 선다. facing = +1(남쪽 길을 봄) / -1."""
    floors_r, w_r, d_r, colors = KINDS[kind]
    out = []
    x = x0
    while x < x1 - 10:
        bw = round(min(rng.uniform(*w_r), x1 - x), 1)
        if bw < 8:
            break
        bd = round(rng.uniform(*d_r), 1)
        cz = z_front - facing * (bd / 2 + 1.0)
        out.append({"kind": kind, "x": round(x + bw / 2, 1), "z": round(cz, 1), "w": bw, "d": bd, "floors": rng.randint(*floors_r),
                    "color": rng.choice(colors), "front": facing})
        x += bw + rng.uniform(1.5, 4.0)
    return out


def road_edge(z_road: float, wide: float, side: int) -> float:
    return z_road + side * (wide / 2 + SIDEWALK)


def build_city() -> dict:
    rng = random.Random(2140)
    buildings = []
    # 탕정역 상권: 강변로 · 시청로 길가 상가 + 안쪽 오피스텔.
    # 시청로 남쪽 줄은 앞면이 북쪽(-1), 강변로 북쪽 줄은 앞면이 남쪽(+1, 강 쪽)을 본다.
    buildings += along_road(road_edge(-108, 14, 1), 108, 252, "shop", rng, -1)
    buildings += along_road(road_edge(104, 14, -1), 108, 252, "shop", rng, 1)
    buildings += place_in([110, -70, 250, 70], "office", rng, 6, gap=8)
    # 서쪽 주거지 · 솔내 주거지: 빌라 골목 (+ 아파트 단지는 apartments.json samples).
    # 서쪽 주거지 아래쪽은 v0.23 빈집촌 (data/survival/houses.json, tools/art/gen_houses.py).
    buildings += place_in([-252, -250, -110, -150], "villa", rng, 12, gap=4)
    # 업무지구.
    buildings += place_in([110, -250, 415, -120], "office", rng, 9, gap=10)
    # 산업단지 (큰 공장 동).
    buildings += place_in([-415, -415, 415, -275], "factory", rng, 11, gap=14)
    # 강 건너 침수 구시가지: 강 남쪽 가장자리에서 6m 너머부터.
    old = []
    for b in place_in([-470, 222, 470, 440], "flooded", rng, 80, gap=3):
        if b["z"] - b["d"] / 2 > south(b["x"]) + 5:
            old.append(b)
    buildings += old
    # 학교 · 도서관 (손으로).
    landmarks = [
        {"kind": "school", "name": "솔바람초등학교", "x": -45.0, "z": -190.0, "w": 48.0, "d": 14.0, "floors": 4, "color": "#E9D8BC"},
        {"kind": "library", "name": "탕정 도서관", "x": 52.0, "z": -150.0, "w": 26.0, "d": 18.0, "floors": 3, "color": "#D7DDE2"},
        {"kind": "station", "name": "탕정역", "x": 340.0, "z": -10.0, "w": 60.0, "d": 22.0, "floors": 2, "color": "#C4CCD2"},
        {"kind": "office", "name": "아산시청 탕정출장소", "x": 160.0, "z": -150.0, "w": 30.0, "d": 20.0, "floors": 6, "color": "#C8D0D6"},
    ]
    # 랜드마크와 겹치는 무작위 건물은 뺀다.
    def clash(a: dict, b: dict, pad: float = 4.0) -> bool:
        return abs(a["x"] - b["x"]) < (a["w"] + b["w"]) / 2 + pad and abs(a["z"] - b["z"]) < (a["d"] + b["d"]) / 2 + pad
    buildings = [b for b in buildings if not any(clash(b, m) for m in landmarks)] + landmarks
    for i, b in enumerate(buildings):
        b["id"] = "b%03d" % i
    flood = {
        "_comment": "강 건너 구시가지가 잠긴 자리 (지난 장마 때 둑이 터졌다): 다각형 안 바닥은 물 밑, 수면 level.",
        "level": 0.35,
        "polygon": [[-430.0, 228.0], [-120.0, 226.0], [-40.0, 234.0], [40.0, 270.0], [10.0, 330.0], [-160.0, 370.0], [-430.0, 390.0]],
        "breach": [-60.0, south(-60.0)],
    }
    return {
        "version": 1,
        "_comment": "탕정 제2지구 강변도시 (v0.21, tools/art/gen_city.py 가 만든다). 도로(a→b 직선, w = 차도 너비, 양쪽 인도 sidewalk m), "
                    "구역(rect = x0,z0,x1,z1), 회색 건물(x,z = 가운데, w · d, floors, kind), 강 건너 침수(flood), 곡교천 보(weir).",
        "name": "탕정 제2지구 강변도시",
        "sidewalk": SIDEWALK,
        "floor_height": 3.0,
        "roads": ROADS,
        "districts": DISTRICTS,
        "weir": {"x": WEIR, "z0": north(WEIR), "z1": south(WEIR)},
        "river": {"name": "곡교천", "centerline": [[x, round(z_c(x), 2)] for x in xs(X0, X1)], "north": [[x, north(x)] for x in xs(X0, X1)],
                  "south": [[x, south(x)] for x in xs(X0, X1)]},
        "bike_path": {"z": 128.0, "w": 3.0},
        "flood": flood,
        "buildings": buildings,
    }


def main() -> None:
    update_spots()
    city = build_city()
    CITY.write_text(dumps(city), encoding="utf-8")
    n_max = max(p[1] for p in city["river"]["north"] if -HALF <= p[0] <= HALF)
    s_min = min(p[1] for p in city["river"]["south"] if -HALF <= p[0] <= HALF)
    print("river north edge max z %.1f, south edge min z %.1f (SOUTH %.0f), buildings %d" % (n_max, s_min, SOUTH, len(city["buildings"])))
    assert n_max < SOUTH - 6 and s_min > SOUTH + 6


if __name__ == "__main__":
    main()
