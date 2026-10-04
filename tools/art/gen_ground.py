#!/usr/bin/env python3
"""마을 바닥 텍스처를 만든다: 잔디 바탕 + 흙길 + 광장 + 호숫가 모래톱 + 섬 바닷가 모래사장·얕은 바다 밑 + 공항 활주로
(data/world/village_layout.json, data/fish/spots.json, data/places/airport.json).

화질 설정마다 리소스팩(assets/packs/<pack>/)에 해상도를 달리해 만든다:
  ground_map.png    마을 가운데 ±map_extent 미터를 덮는 색 지도 (알파 = 잔디 정도)   low 512² · high 2048²
  ground_detail.png 바둑판처럼 이어지는 잔결 (3m마다 반복, 회색조)                    low 128² · high 512²
사용: python3 tools/art/gen_ground.py [low|high ...]   (기본 = 모두, numpy, pillow 필요)
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024
DETAIL = 256
## 리소스팩 → (색 지도 크기, 잔결 크기)
PACKS = {"low": (512, 128), "high": (2048, 512)}
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


def main(pack: str) -> None:
    global SIZE, DETAIL, OUT_DIR
    SIZE, DETAIL = PACKS[pack]
    OUT_DIR = ROOT / "assets/packs" / pack
    layout = json.loads((ROOT / "data/world/village_layout.json").read_text(encoding="utf-8"))
    spots = json.loads((ROOT / "data/fish/spots.json").read_text(encoding="utf-8"))
    extent = float(layout["map_extent"])
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

    # 섬: 바닷가 모래사장(물가로 갈수록 젖은 모래) → 해안선 너머 얕은 바다 밑.
    island = layout.get("island")
    if island:
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
    out = OUT_DIR / "ground_map.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
    print(out)

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
