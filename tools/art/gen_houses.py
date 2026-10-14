#!/usr/bin/env python3
"""v0.23 빈집촌 (솔내 옛마을) — 사람이 떠난 1층 단층집들 (data/survival/houses.json).
집마다 w×d (로컬: 가운데 바닥, 앞면 +Z), 방 칸막이(문틈), 뒤질 수 있는 가구(containers: 서랍 · 냉장고 · 싱크대 · 옷장 · 신발장 · 약장).
가구 자리는 월드 좌표로도 써 둔다 (서버가 거리만 본다). 사용: python3 tools/art/gen_houses.py
"""
import json
import math
import random
from pathlib import Path

from json_compact import dumps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data/survival/houses.json"
W, D = 10.0, 8.0
# 로컬 가구 자리: (종류, x, z, yaw — 가구 앞면이 보는 쪽).
CONTAINERS = [
    ("shoe_cabinet", -4.55, 3.3, math.pi / 2),
    ("fridge", 4.45, 3.35, -math.pi / 2),
    ("sink", 4.5, 1.7, -math.pi / 2),
    ("drawer", 1.4, 0.45, 0.0),
    ("wardrobe", -4.5, -2.4, math.pi / 2),
    ("medicine", 4.75, -3.0, -math.pi / 2),
]
# 칸막이 (로컬 선분 a→b, 문틈은 비운다).
WALLS = [
    # 바깥: 앞(현관 x −3.6..−2.4 비움) · 뒤 · 옆
    [[-5, 4], [-3.6, 4]], [[-2.4, 4], [5, 4]],
    [[-5, -4], [5, -4]],
    [[-5, -4], [-5, 4]], [[5, -4], [5, 4]],
    # 안: 앞방 / 뒷방 (z = 0, 침실 문 x −1.2..−0.1 · 욕실 문 x 2.6..3.5 비움)
    [[-5, 0], [-1.2, 0]], [[-0.1, 0], [2.6, 0]], [[3.5, 0], [5, 0]],
    # 침실 / 욕실 (x = 2.0)
    [[2.0, -4], [2.0, 0]],
]
WALL_COLORS = ["#E8DCC6", "#D9CDB4", "#EFE6D6", "#CDBFA6", "#E2D2B8", "#D6CCC0"]
ROOF_COLORS = ["#4F7FA8", "#B8573E", "#5E8A5A", "#8A6A9A", "#C98B3A", "#5B6670"]


def world(hx, hz, yaw, x, z):
    c, s = math.cos(yaw), math.sin(yaw)
    return round(hx + x * c + z * s, 2), round(hz - x * s + z * c, 2)


def main() -> None:
    rng = random.Random(23)
    houses = []
    n = 0
    for zi, z in enumerate([-82.0, -56.0, -30.0, -4.0]):
        for x in [-392.0, -358.0, -324.0, -290.0]:
            n += 1
            hid = "h%02d" % n
            yaw = 0.0 if zi % 2 == 0 else math.pi
            hx = x + rng.uniform(-3, 3)
            hz = z + rng.uniform(-1.5, 1.5)
            cont = []
            for i, (kind, lx, lz, lyaw) in enumerate(CONTAINERS):
                wx, wz = world(hx, hz, yaw, lx, lz)
                cont.append({"id": "%s_%d" % (hid, i + 1), "kind": kind, "x": wx, "z": wz, "lx": lx, "lz": lz, "yaw": round(lyaw, 4)})
            houses.append({
                "id": hid, "x": round(hx, 2), "z": round(hz, 2), "yaw": round(yaw, 4), "w": W, "d": D,
                "wall": rng.choice(WALL_COLORS), "roof": rng.choice(ROOF_COLORS), "boarded": rng.random() < 0.5,
                "containers": cont,
            })
    doc = {
        "version": 1,
        "_comment": "v0.23 솔내 옛마을 빈집촌 (tools/art/gen_houses.py 가 만든다). 장마 뒤 사람이 떠난 1층 단층집 16채. "
                    "x,z = 집 가운데, yaw = 앞면(현관) 방향, w × d. walls = 로컬 칸막이 선분(문틈은 비움), containers = 뒤질 수 있는 가구 "
                    "(x,z 월드 · lx,lz 로컬 · yaw 가구 앞면). 무엇이 나오는지는 data/survival/survival.json loot.",
        "name": "솔내 옛마을",
        "walls": WALLS,
        "houses": houses,
    }
    OUT.write_text(dumps(doc), encoding="utf-8")
    print("houses", len(houses), "containers", sum(len(h["containers"]) for h in houses))


if __name__ == "__main__":
    main()
