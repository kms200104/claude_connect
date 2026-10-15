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
    # 안: 앞방 / 뒷방 (z = 0, v0.28.1 침실 문 x −1.4..0.1 · 욕실 문 x 2.4..3.7 비움 — 벽 끝 여유 0.1m 를 빼도 1.3m · 1.1m)
    [[-5, 0], [-1.4, 0]], [[0.1, 0], [2.4, 0]], [[3.7, 0], [5, 0]],
    # 침실 / 욕실 (x = 2.0)
    [[2.0, -4], [2.0, 0]],
]
# v0.24 뚫린 곳 (판자로 막을 수 있는 자리): 현관 + 창 5개 (로컬 가운데 · 바깥쪽 n). 집마다 창 2개는 깨져 있다 (broken).
# 막지 않은 현관 · 깨진 창으로 크리처가 들어온다.
OPENINGS = [
    {"id": "door", "kind": "door", "lx": -3.0, "lz": 4.0, "nx": 0, "nz": 1},
    {"id": "w1", "kind": "window", "lx": 1.6, "lz": 4.0, "nx": 0, "nz": 1},
    {"id": "w2", "kind": "window", "lx": -2.0, "lz": -4.0, "nx": 0, "nz": -1},
    {"id": "w3", "kind": "window", "lx": 2.8, "lz": -4.0, "nx": 0, "nz": -1},
    {"id": "w4", "kind": "window", "lx": -5.0, "lz": 2.0, "nx": -1, "nz": 0},
    {"id": "w5", "kind": "window", "lx": 5.0, "lz": -2.0, "nx": 1, "nz": 0},
]
# 안쪽 방 (앞방이 아닌 곳): 크리처가 방 사이를 문틈(door, 로컬)으로만 지나다니게. 문틈 앞(+z)이 앞방.
ROOMS = [
    {"id": "bed", "x0": -5.0, "x1": 2.0, "z0": -4.0, "z1": 0.0, "door": [-0.65, 0.0]},
    {"id": "bath", "x0": 2.0, "x1": 5.0, "z0": -4.0, "z1": 0.0, "door": [3.05, 0.0]},
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
    # 솔내 옛마을 16채 (v0.23) + v0.28.2 옛마을 남쪽 줄 4채 · 솔내 주거지(북서) 12채.
    # 뒤에 더한 집은 따로 굴린 난수로 — 앞 16채의 자리 · 색이 바뀌지 않는다.
    rows = [(z, xs, rng) for z in [-82.0, -56.0, -30.0, -4.0] for xs in [[-392.0, -358.0, -324.0, -290.0]]]
    extra = random.Random(282)
    rows += [(48.0, [-392.0, -358.0, -324.0, -290.0], extra)]
    rows += [(z, [-392.0, -358.0, -324.0, -290.0], extra) for z in [-166.0, -192.0, -218.0]]
    for zi, (z, xs, r) in enumerate(rows):
        for x in xs:
            rng = r
            n += 1
            hid = "h%02d" % n
            yaw = 0.0 if zi % 2 == 0 else math.pi
            hx = x + rng.uniform(-3, 3)
            hz = z + rng.uniform(-1.5, 1.5)
            cont = []
            for i, (kind, lx, lz, lyaw) in enumerate(CONTAINERS):
                wx, wz = world(hx, hz, yaw, lx, lz)
                cont.append({"id": "%s_%d" % (hid, i + 1), "kind": kind, "x": wx, "z": wz, "lx": lx, "lz": lz, "yaw": round(lyaw, 4)})
            wall, roof = rng.choice(WALL_COLORS), rng.choice(ROOF_COLORS)
            rng.random()  # (예전 boarded 자리 — 뒤 집들의 자리가 바뀌지 않게 하나 버린다)
            broken = sorted(random.Random(hid).sample([o["id"] for o in OPENINGS if o["kind"] == "window"], 2))
            houses.append({
                "id": hid, "x": round(hx, 2), "z": round(hz, 2), "yaw": round(yaw, 4), "w": W, "d": D,
                "wall": wall, "roof": roof,
                "broken": broken, "containers": cont,
            })
    doc = {
        "version": 1,
        "_comment": "v0.23 솔내 옛마을 빈집촌 (tools/art/gen_houses.py 가 만든다). 장마 뒤 사람이 떠난 1층 단층집 32채 (옛마을 20 · 솔내 주거지 12). "
                    "x,z = 집 가운데, yaw = 앞면(현관) 방향, w × d. walls = 로컬 칸막이 선분(문틈은 비움), openings = 판자로 막을 수 있는 현관 · 창 "
                    "(로컬, n = 바깥쪽), broken = 그 집의 깨진 창 (현관과 함께 크리처가 들어오는 곳), containers = 뒤질 수 있는 가구 "
                    "(x,z 월드 · lx,lz 로컬 · yaw 가구 앞면). 무엇이 나오는지는 data/survival/survival.json loot.",
        "name": "솔내 옛마을",
        "walls": WALLS,
        "openings": OPENINGS,
        "rooms": ROOMS,
        "houses": houses,
    }
    OUT.write_text(dumps(doc), encoding="utf-8")
    print("houses", len(houses), "containers", sum(len(h["containers"]) for h in houses))


if __name__ == "__main__":
    main()
