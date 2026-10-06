#!/usr/bin/env python3
"""윤곽(outline)이 있는 호수마다 물 셰이더용 '거리 그림'을 만든다: data/fish/sdf/<id>.json.
값 = 윤곽까지의 부호 있는 거리(안쪽 음수)를 ±range m 로 잘라 0~255 로 (128 = 윤곽). 영역 = 수역 바깥 사각형 + pad m,
위쪽 = -Z. 사용: python3 tools/art/gen_lake_sdf.py   (numpy 필요; spots.json 의 outline 이 바뀔 때마다 다시 만든다)"""
import base64
import json
from pathlib import Path

import numpy as np

from lake_poly import signed_distance

ROOT = Path(__file__).resolve().parents[2]
SIZE = 160
RANGE = 4.0
PAD = 2.0


def main() -> None:
    spots = json.loads((ROOT / "data/fish/spots.json").read_text(encoding="utf-8"))["spots"]
    out_dir = ROOT / "data/fish/sdf"
    out_dir.mkdir(parents=True, exist_ok=True)
    for spot in spots:
        if "outline" not in spot:
            continue
        hx, hz = spot["half_x"] + PAD, spot["half_z"] + PAD
        xs = spot["x"] + ((np.arange(SIZE) + 0.5) / SIZE * 2 - 1) * hx
        zs = spot["z"] + ((np.arange(SIZE) + 0.5) / SIZE * 2 - 1) * hz
        px, pz = np.meshgrid(xs, zs)
        sd = signed_distance(np.array(spot["outline"], dtype=float), px, pz)
        value = np.clip(np.rint((np.clip(sd / RANGE, -1, 1) * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)
        doc = {"id": spot["id"], "size": SIZE, "range": RANGE, "half": [round(hx, 3), round(hz, 3)],
               "data": base64.b64encode(value.tobytes()).decode("ascii")}
        path = out_dir / f"{spot['id']}.json"
        path.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
        print(path, len(doc["data"]))


if __name__ == "__main__":
    main()
