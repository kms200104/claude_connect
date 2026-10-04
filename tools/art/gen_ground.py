#!/usr/bin/env python3
"""마을 바닥 텍스처를 만든다: 잔디 바탕 + 흙길 + 광장 + 호숫가 모래톱 (data/world/village_layout.json, data/fish/spots.json).

  assets/textures/ground_map.png    512×512, 마을 가운데 ±map_extent 미터를 덮는 색 지도 (알파 = 잔디 정도)
  assets/textures/ground_detail.png 256×256, 바둑판처럼 이어지는 잔결 (3m마다 반복, 회색조)
사용: python3 tools/art/gen_ground.py   (numpy, pillow 필요)
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIZE = 512
DETAIL = 256

GRASS = np.array([0.56, 0.78, 0.43])
GRASS_DARK = np.array([0.45, 0.68, 0.36])
GRASS_LIGHT = np.array([0.66, 0.84, 0.5])
PATH = np.array([0.89, 0.8, 0.6])
PATH_EDGE = np.array([0.8, 0.69, 0.5])
PLAZA = np.array([0.92, 0.86, 0.7])
SAND = np.array([0.94, 0.87, 0.67])
LAKE_BED = np.array([0.42, 0.66, 0.66])


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


def main() -> None:
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

    rgba = np.dstack([np.clip(color, 0, 1), grassiness])
    out = ROOT / "assets/textures/ground_map.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
    print(out)

    # 잔결: 큰 얼룩 + 잔 점 + 짧은 풀잎 줄.
    detail = fbm(DETAIL, 5, [(8, 0.6), (32, 0.6), (64, 0.5), (128, 0.4)])
    rng = np.random.default_rng(9)
    for _ in range(900):
        x, y = rng.integers(0, DETAIL, 2)
        length = rng.integers(3, 7)
        for k in range(length):
            detail[(y - k) % DETAIL, (x + k // 3) % DETAIL] += 0.18 * (1 - k / length)
    detail = (detail - detail.min()) / (detail.max() - detail.min())
    out = ROOT / "assets/textures/ground_detail.png"
    Image.fromarray((detail * 255).astype(np.uint8), "L").save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    main()
