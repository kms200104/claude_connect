#!/usr/bin/env python3
"""마을 바닥 텍스처를 만든다: 잔디 바탕 + 흙길 + 광장 + 호숫가 모래톱 + 공항 활주로
+ v0.21 강변도시(data/world/city.json): 도로(아스팔트 · 차선 · 인도) · 구역 바닥(포장 · 콘크리트) · 곡교천 바닥 · 호안 돌 · 둔치 자전거길 · 하류 갯벌 · 강 건너 진흙
(data/world/village_layout.json, data/fish/spots.json, data/places/airport.json, data/world/city.json).

화질 설정마다 리소스팩(assets/packs/<pack>/)에 해상도를 달리해 만든다:
  ground_map.png    도시 가운데 ±map_extent 미터를 덮는 색 지도 (알파 = 잔디 정도)   low 1024² · high 2048²
  ground_town.png   시내 ±town_extent 미터 촘촘한 색 지도 (v0.21)                    low 512² · high 1024²
  ground_detail.png 바둑판처럼 이어지는 잔결 (3m마다 반복, 회색조)                    low 128² · high 512²
사용: python3 tools/art/gen_ground.py [low|high ...]   (기본 = 모두, numpy, pillow 필요)
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

from lake_poly import signed_distance

ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024
DETAIL = 256
## 리소스팩 → (색 지도 크기, 잔결 크기)
PACKS = {"low": (1024, 128), "high": (2048, 512)}
## 시내 지도 (±town_extent) 크기.
TOWN_SIZES = {"low": 512, "high": 1024}
OUT_DIR = ROOT / "assets/packs/low"

GRASS = np.array([0.56, 0.78, 0.43])
GRASS_DARK = np.array([0.45, 0.68, 0.36])
GRASS_LIGHT = np.array([0.66, 0.84, 0.5])
PATH = np.array([0.89, 0.8, 0.6])
PATH_EDGE = np.array([0.8, 0.69, 0.5])
PLAZA = np.array([0.92, 0.86, 0.7])
SAND = np.array([0.94, 0.87, 0.67])
LAKE_BED = np.array([0.42, 0.66, 0.66])
BEACH = np.array([0.96, 0.9, 0.72])
BEACH_WET = np.array([0.86, 0.8, 0.62])
SEA_BED = np.array([0.38, 0.68, 0.7])
RUNWAY = np.array([0.5, 0.52, 0.55])
RUNWAY_LINE = np.array([0.97, 0.96, 0.9])
# v0.21 강변도시
ASPHALT = np.array([0.36, 0.37, 0.4])
ASPHALT_DARK = np.array([0.3, 0.31, 0.34])
LANE_WHITE = np.array([0.92, 0.92, 0.9])
LANE_YELLOW = np.array([0.95, 0.78, 0.25])
SIDEWALK = np.array([0.78, 0.74, 0.7])
SIDEWALK_RED = np.array([0.72, 0.52, 0.45])
CURB = np.array([0.86, 0.85, 0.82])
PAVE = np.array([0.74, 0.72, 0.68])
CONCRETE = np.array([0.66, 0.67, 0.66])
RIVER_BED = np.array([0.34, 0.45, 0.38])
REVETMENT = np.array([0.62, 0.62, 0.6])
BIKE = np.array([0.66, 0.36, 0.3])
MUDFLAT = np.array([0.55, 0.5, 0.42])
MUD = np.array([0.5, 0.45, 0.36])
FIELD = np.array([0.6, 0.72, 0.42])
DISTRICT_FLOOR = {"commercial": (PAVE, 0.9), "station": (PAVE, 0.85), "industry": (CONCRETE, 0.8), "office": (PAVE, 0.55), "civic": (PAVE, 0.25)}


def periodic_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """끝과 끝이 이어지는 값 노이즈 (0~1)."""
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells))
    t = np.arange(size) / size * cells
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    rows = grid[i0][:, None, :] * (1 - f)[:, None, None] + grid[i1][:, None, :] * f[:, None, None]
    rows = rows[:, 0, :]
    out = rows[:, i0] * (1 - f)[None, :] + rows[:, i1] * f[None, :]
    return out


def fbm(size: int, seed: int, octaves: list) -> np.ndarray:
    total = np.zeros((size, size))
    weight = 0.0
    for k, (cells, amp) in enumerate(octaves):
        total += periodic_noise(size, cells, seed + k * 17) * amp
        weight += amp
    return total / weight


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def segment_distance(px: np.ndarray, pz: np.ndarray, a: tuple, b: tuple) -> np.ndarray:
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    length2 = dx * dx + dz * dz
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / max(length2, 1e-6), 0.0, 1.0)
    cx, cz = ax + t * dx, az + t * dz
    return np.hypot(px - cx, pz - cz)


def blend(color: np.ndarray, target, mask: np.ndarray) -> np.ndarray:
    target = np.asarray(target)
    if target.ndim == 1:
        target = target[None, None, :]
    return color * (1 - mask[..., None]) + target * mask[..., None]


def edge_z(edge: list, x: np.ndarray) -> np.ndarray:
    e = np.array(edge, dtype=float)
    return np.interp(x, e[:, 0], e[:, 1])


def paint_city(city: dict, spots: dict, layout: dict, px: np.ndarray, pz: np.ndarray, color: np.ndarray, grassiness: np.ndarray, wobble: np.ndarray):
    """강변도시 바닥 (도로 · 구역 · 강 · 둔치 · 강 건너). 모두 그림만 — 판정은 서버/규칙이 따로."""
    n = px.shape[0]
    noise = fbm(n, 23, [(40, 1.0), (120, 0.5)])
    island = layout.get("island", {})
    half = float(island.get("half", 420))
    power = float(island.get("power", 10))
    shape = (np.abs(px / half) ** power + np.abs(pz / half) ** power) ** (1.0 / power)
    # 도시 밖 들판 (논밭 줄무늬).
    outside = smoothstep(0.995, 1.01, shape)
    rows = (np.sin(px * 0.35) * 0.5 + 0.5) * 0.12
    color = blend(color, FIELD[None, None, :] * (0.92 + rows[..., None]), outside)
    # 구역 바닥.
    for d in city.get("districts", []):
        kind = d.get("kind", "")
        if kind not in DISTRICT_FLOOR:
            continue
        base, amount = DISTRICT_FLOOR[kind]
        x0, z0, x1, z1 = d["rect"]
        inside = smoothstep(0.0, 1.0, np.minimum.reduce([px - x0, x1 - px, pz - z0, z1 - pz]))
        patch = np.clip(amount + (noise - 0.5) * 0.9, 0, 1) if amount < 0.8 else np.full(px.shape, amount)
        m = inside * patch
        color = blend(color, base[None, None, :] * (0.95 + noise[..., None] * 0.1), m)
        grassiness = grassiness * (1 - m)
    # 건물 바닥 (건물 밑 · 둘레 1m 포장).
    cell = px[0, 1] - px[0, 0]
    x_min = px[0, 0]
    for b in city.get("buildings", []):
        if b.get("kind") == "flooded":
            continue
        # 건물 둘레 창만 계산한다 (전체 격자는 느리다).
        c0 = max(int((b["x"] - b["w"] / 2 - 3 - x_min) / cell), 0)
        c1 = min(int((b["x"] + b["w"] / 2 + 3 - x_min) / cell) + 1, n)
        r0 = max(int((b["z"] - b["d"] / 2 - 3 - x_min) / cell), 0)
        r1 = min(int((b["z"] + b["d"] / 2 + 3 - x_min) / cell) + 1, n)
        if c0 >= c1 or r0 >= r1:
            continue
        wx, wz = px[r0:r1, c0:c1], pz[r0:r1, c0:c1]
        dx = np.abs(wx - b["x"]) - b["w"] / 2 - 1.5
        dz = np.abs(wz - b["z"]) - b["d"] / 2 - 1.5
        m = smoothstep(0.4, -0.2, np.maximum(dx, dz))
        color[r0:r1, c0:c1] = blend(color[r0:r1, c0:c1], CONCRETE, m)
        grassiness[r0:r1, c0:c1] = grassiness[r0:r1, c0:c1] * (1 - m)
    # 도로: 인도 → 연석 → 차도 → 차선.
    side = float(city.get("sidewalk", 3.0))
    for r in city.get("roads", []):
        (ax, az), (bx, bz) = r["a"], r["b"]
        w = float(r["w"])
        horizontal = abs(az - bz) < 1e-6
        if horizontal:
            across = pz - az
            along = px
            lo, hi = min(ax, bx), max(ax, bx)
        else:
            across = px - ax
            along = pz
            lo, hi = min(az, bz), max(az, bz)
        span = smoothstep(lo - side - w / 2 - 0.5, lo - side - w / 2, along) * smoothstep(hi + side + w / 2 + 0.5, hi + side + w / 2, along)
        a = np.abs(across)
        walk = smoothstep(w / 2 + side + 0.15, w / 2 + side - 0.15, a) * span
        tiles = ((np.floor(along / 0.6) + np.floor(across / 0.6)) % 2)[..., None] * 0.04
        color = blend(color, SIDEWALK[None, None, :] * (0.97 + tiles), walk)
        # 인도 가운데 점자 · 자전거 붉은 띠.
        red = walk * smoothstep(0.5, 0.3, np.abs(a - (w / 2 + side * 0.62)))
        color = blend(color, SIDEWALK_RED, red * 0.8)
        curb = walk * smoothstep(0.35, 0.15, np.abs(a - w / 2 - 0.1))
        color = blend(color, CURB, curb)
        road = smoothstep(w / 2 + 0.05, w / 2 - 0.15, a) * span
        color = blend(color, ASPHALT[None, None, :] + (ASPHALT_DARK - ASPHALT)[None, None, :] * noise[..., None], road)
        grassiness = grassiness * (1 - walk) * (1 - road)
        # 가운데 노란 두 줄 · 차로 흰 점선.
        yellow = road * ((np.abs(a - 0.18) < 0.09) | (np.abs(a + 0.18) < 0.09))
        color[yellow > 0.5] = LANE_YELLOW
        dash = road * (np.abs(np.abs(a) - w / 4) < 0.08) * ((along % 9.0) < 4.5)
        color[dash > 0.5] = LANE_WHITE
    # 교차로: 가운데 선 · 점선 지우기 (두 길이 겹치는 자리).
    for r1 in city.get("roads", []):
        for r2 in city.get("roads", []):
            if r1 is r2 or abs(r1["a"][1] - r1["b"][1]) > 1e-6 or abs(r2["a"][0] - r2["b"][0]) > 1e-6:
                continue
            x, z = r2["a"][0], r1["a"][1]
            if not (min(r1["a"][0], r1["b"][0]) <= x <= max(r1["a"][0], r1["b"][0]) and min(r2["a"][1], r2["b"][1]) <= z <= max(r2["a"][1], r2["b"][1])):
                continue
            hw, hd = r2["w"] / 2, r1["w"] / 2
            box = (np.abs(px - x) <= hw) & (np.abs(pz - z) <= hd)
            color[box] = ASPHALT
            # 건널목 (네 방향 흰 줄무늬).
            for sx, sz, vertical in ((x, z - hd - 1.6, False), (x, z + hd + 1.6, False), (x - hw - 1.6, z, True), (x + hw + 1.6, z, True)):
                if vertical:
                    zebra = (np.abs(px - sx) < 1.4) & (np.abs(pz - sz) < hd) & (((pz - sz) % 1.0) < 0.5)
                else:
                    zebra = (np.abs(pz - sz) < 1.4) & (np.abs(px - sx) < hw) & (((px - sx) % 1.0) < 0.5)
                color[zebra] = LANE_WHITE
    # 곡교천: 북쪽 가장자리 호안(돌), 강 바닥, 강 건너 둑 · 진흙.
    river = city.get("river", {})
    if river:
        nz = edge_z(river["north"], px)
        sz = edge_z(river["south"], px)
        inside = (pz > nz) & (pz < sz)
        bed = smoothstep(-0.3, 0.6, np.minimum(pz - nz, sz - pz))
        color = blend(color, RIVER_BED[None, None, :] * (0.85 + noise[..., None] * 0.3), bed)
        grassiness = grassiness * (1 - smoothstep(-2.0, 0.0, pz - nz))
        rev = smoothstep(-2.2, -1.6, pz - nz) * smoothstep(0.4, 0.0, pz - nz)
        blocks = ((np.floor(px / 1.2) + np.floor((pz - nz) / 0.6)) % 2)[..., None] * 0.05
        color = blend(color, REVETMENT[None, None, :] * (0.95 + blocks), rev)
        far = smoothstep(0.0, 1.5, pz - sz)
        levee = far * smoothstep(3.0, 6.0, pz - sz) * smoothstep(16.0, 12.0, pz - sz)
        color = blend(color, GRASS_DARK, levee * 0.5)
        _ = inside
        # 하류 갯벌 (조개): 'sea' 낚시터 북쪽 물가 3.5m.
        clam = layout.get("island", {}).get("clam_spot")
        if clam:
            sea = next((s for s in spots["spots"] if s["id"] == clam), None)
            if sea:
                x0 = sea["x"] - sea["half_x"]
                flat = smoothstep(-4.2, -3.2, pz - nz) * smoothstep(0.2, -0.4, pz - nz) * smoothstep(x0 + 4, x0 + 10, px)
                flat = flat * smoothstep(0.0, 0.3, noise + wobble * 0.3 + 0.1)
                color = blend(color, MUDFLAT, flat)
                grassiness = grassiness * (1 - flat)
        # 둔치 자전거길 (붉은 띠 · 가운데 흰 점선) + 산책길.
        bike = city.get("bike_path", {})
        if bike:
            bz, bw = float(bike["z"]), float(bike["w"])
            m = smoothstep(bw / 2 + 0.1, bw / 2 - 0.1, np.abs(pz - bz)) * (1 - outside)
            color = blend(color, BIKE, m)
            line = m * (np.abs(pz - bz) < 0.06) * ((px % 4.0) < 2.0)
            color[line > 0.5] = LANE_WHITE
            walk = smoothstep(1.1, 0.9, np.abs(pz - bz - 4.5)) * (1 - outside)
            color = blend(color, PATH, walk)
            grassiness = grassiness * (1 - m) * (1 - walk)
    # 강 건너 침수: 다각형 안은 진흙(물 밑).
    flood = city.get("flood", {})
    if flood.get("polygon"):
        poly = np.array(flood["polygon"], dtype=float)
        sd = signed_distance(poly, px, pz)
        m = smoothstep(3.0, -2.0, sd + wobble * 2.0)
        color = blend(color, MUD, m)
        grassiness = grassiness * (1 - m)
    return color, grassiness


def main(pack: str) -> None:
    global DETAIL, OUT_DIR
    size, DETAIL = PACKS[pack]
    OUT_DIR = ROOT / "assets/packs" / pack
    layout = json.loads((ROOT / "data/world/village_layout.json").read_text(encoding="utf-8"))
    paint_map(size, float(layout["map_extent"]), "ground_map.png")
    # v0.21: 시내(±town_extent)는 촘촘한 지도를 따로 (도시 지도 한 장으로는 산책길이 흐릿하다).
    if layout.get("town_extent"):
        paint_map(TOWN_SIZES[pack], float(layout["town_extent"]), "ground_town.png")
    write_detail()


def paint_map(size: int, extent: float, name: str) -> None:
    global SIZE
    SIZE = size
    layout = json.loads((ROOT / "data/world/village_layout.json").read_text(encoding="utf-8"))
    spots = json.loads((ROOT / "data/fish/spots.json").read_text(encoding="utf-8"))
    # 픽셀 가운데의 월드 좌표 (이미지 위쪽 = -Z, 셰이더의 uv = xz / (2·extent) + 0.5 와 같은 방향).
    coords = (np.arange(SIZE) + 0.5) / SIZE * 2 * extent - extent
    px, pz = np.meshgrid(coords, coords)

    patches = fbm(SIZE, 3, [(6, 1.0), (14, 0.5), (32, 0.25)])
    color = GRASS[None, None, :] * np.ones((SIZE, SIZE, 1))
    color = color + (GRASS_LIGHT - GRASS)[None, None, :] * smoothstep(0.55, 0.75, patches)[..., None]
    color = color + (GRASS_DARK - GRASS)[None, None, :] * smoothstep(0.45, 0.25, patches)[..., None]
    grassiness = np.ones((SIZE, SIZE))

    wobble = (fbm(SIZE, 11, [(24, 1.0), (60, 0.5)]) - 0.5) * 0.7
    half = float(layout["path_width"]) * 0.5
    dist = np.full((SIZE, SIZE), 1e9)
    for line in layout["paths"]:
        for a, b in zip(line[:-1], line[1:]):
            dist = np.minimum(dist, segment_distance(px, pz, tuple(a), tuple(b)))
    plaza = layout["plaza"]
    plaza_d = np.hypot(px - plaza["x"], pz - plaza["z"]) - plaza["r"] + 0.0
    for extra in layout.get("plazas", []):
        plaza_d = np.minimum(plaza_d, np.hypot(px - extra["x"], pz - extra["z"]) - extra["r"])
    path_d = np.minimum(dist - half, plaza_d) + wobble
    path_mask = smoothstep(0.35, -0.15, path_d)
    edge_mask = smoothstep(0.35, 0.0, np.abs(path_d)) * path_mask
    surface = np.where((plaza_d + wobble < dist - half)[..., None], PLAZA, PATH)
    surface = surface + (PATH_EDGE - surface) * edge_mask[..., None] * 0.6
    color = color * (1 - path_mask[..., None]) + surface * path_mask[..., None]
    grassiness = grassiness * (1 - path_mask)

    shore = float(layout["lake_shore"])
    power = float(layout["lake_shape_power"])
    for spot in spots["spots"]:
        if spot.get("near_people"):
            continue  # v0.21 곡교천: paint_city 가 강 바닥 · 호안을 칠한다.
        if "outline" in spot:
            # 실제 윤곽 호수: 바깥 사각형 + 모래톱 폭 안쪽 창만 부호 있는 거리를 계산한다 (전체 격자는 낭비).
            outline = np.array(spot["outline"], dtype=float)
            pad = shore + 1.0
            win = (px >= spot["x"] - spot["half_x"] - pad) & (px <= spot["x"] + spot["half_x"] + pad) & (pz >= spot["z"] - spot["half_z"] - pad) & (pz <= spot["z"] + spot["half_z"] + pad)
            rows, cols = np.where(win)
            r0, r1, c0, c1 = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
            sd = np.full((SIZE, SIZE), 1e3)
            sd[r0:r1, c0:c1] = signed_distance(outline, px[r0:r1, c0:c1], pz[r0:r1, c0:c1])
            sand = smoothstep(shore + 0.1, shore - 0.4, sd + wobble * 0.7)
            bed = smoothstep(0.1, -0.35, sd)
            color = color * (1 - sand[..., None]) + SAND * sand[..., None]
            color = color * (1 - bed[..., None]) + LAKE_BED * bed[..., None]
            grassiness = grassiness * (1 - sand)
            continue
        cx, cz = float(spot["x"]), float(spot["z"])
        hx, hz = float(spot["half_x"]), float(spot["half_z"])

        def shape(sx: float, sz: float) -> np.ndarray:
            qx = np.abs(px - cx) / sx
            qz = np.abs(pz - cz) / sz
            return (qx ** power + qz ** power) ** (1.0 / power)

        sand = smoothstep(1.06, 0.98, shape(hx + shore, hz + shore) + wobble * 0.05)
        bed = smoothstep(1.0, 0.94, shape(hx, hz))
        color = color * (1 - sand[..., None]) + SAND * sand[..., None]
        color = color * (1 - bed[..., None]) + LAKE_BED * bed[..., None]
        grassiness = grassiness * (1 - sand)

    # 공항 활주로: 회색 띠 + 가운데 흰 점선 + 양끝 흰 줄무늬.
    airport = json.loads((ROOT / "data/places/airport.json").read_text(encoding="utf-8"))
    w = airport["runway"]
    half_w = w["width"] * 0.5
    inside = (px >= w["x0"]) & (px <= w["x1"]) & (np.abs(pz - w["z"]) <= half_w)
    soft = smoothstep(half_w + 0.3, half_w - 0.1, np.abs(pz - w["z"])) * smoothstep(w["x0"] - 0.3, w["x0"] + 0.1, px) * smoothstep(w["x1"] + 0.3, w["x1"] - 0.1, px)
    color = color * (1 - soft[..., None]) + RUNWAY * soft[..., None]
    dash = inside & (np.abs(pz - w["z"]) < 0.16) & (((px - w["x0"]) % 4.0) < 2.2)
    stripes = inside & ((px - w["x0"] < 2.0) | (w["x1"] - px < 2.0)) & ((np.abs(pz - w["z"]) % 1.0) < 0.5) & (np.abs(pz - w["z"]) < half_w - 0.4)
    color[dash | stripes] = RUNWAY_LINE
    grassiness = grassiness * (1 - soft)

    city_path = ROOT / "data/world/city.json"
    if city_path.exists():
        color, grassiness = paint_city(json.loads(city_path.read_text(encoding="utf-8")), spots, layout, px, pz, color, grassiness, wobble)

    # 섬: 바닷가 모래사장(물가로 갈수록 젖은 모래) → 해안선 너머 얕은 바다 밑. (v0.21 강변도시는 바닷가가 없다)
    island = layout.get("island")
    if island and not city_path.exists():
        half = float(island["half"])
        power = float(island.get("power", 4.0))
        beach = float(island.get("beach", 8.0))
        shape = (np.abs(px / half) ** power + np.abs(pz / half) ** power) ** (1.0 / power)
        coast = (shape - 1.0) * half + wobble * 1.4  # 해안선까지의 거리 (안쪽 음수, 미터)
        sand = smoothstep(-beach - 0.6, -beach + 0.6, coast)
        wet = smoothstep(-2.5, 0.0, coast)
        sea = smoothstep(0.0, 1.2, coast)
        beach_color = BEACH * (1 - wet[..., None]) + BEACH_WET * wet[..., None]
        color = color * (1 - sand[..., None]) + beach_color * sand[..., None]
        color = color * (1 - sea[..., None]) + SEA_BED * sea[..., None]
        grassiness = grassiness * (1 - sand)

    rgba = np.dstack([np.clip(color, 0, 1), grassiness])
    out = OUT_DIR / name
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
    print(out)


def write_detail() -> None:
    # 잔결: 큰 얼룩 + 잔 점 + 짧은 풀잎 줄.
    detail = fbm(DETAIL, 5, [(8, 0.6), (32, 0.6), (64, 0.5), (128, 0.4)])
    rng = np.random.default_rng(9)
    k_scale = DETAIL / 256
    for _ in range(int(900 * k_scale * k_scale)):
        x, y = rng.integers(0, DETAIL, 2)
        length = int(rng.integers(3, 7) * k_scale + 0.5)
        for k in range(length):
            detail[(y - k) % DETAIL, (x + k // 3) % DETAIL] += 0.18 * (1 - k / length)
    detail = (detail - detail.min()) / (detail.max() - detail.min())
    out = OUT_DIR / "ground_detail.png"
    Image.fromarray((detail * 255).astype(np.uint8), "L").save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    import sys
    for name in sys.argv[1:] or list(PACKS):
        main(name)
