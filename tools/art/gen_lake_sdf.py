#!/usr/bin/env python3
"""윤곽(outline)이 있는 호수마다 물 셰이더용 '거리 그림'을 만든다: data/fish/sdf/<id>.json.
정사각 size² 칸, 긴 변 기준 약 CELL m/칸 (최대 MAX_SIZE²). 값 = 윤곽까지의 부호 있는 거리(안쪽 음수)를 ±range m 로 잘라 0~255 로 (128 = 윤곽). 영역 = 수역 바깥 사각형 + pad m,
v0.13.5: 두 번째 채널(far)에 같은 거리를 ±far_range m 로 넣는다 (RG8: R = 물가 거품용 촘촘한 값, G = 큰 호수 가운데까지 깊이).
위쪽 = -Z. 사용: python3 tools/art/gen_lake_sdf.py   (numpy 필요; spots.json 의 outline 이 바뀔 때마다 다시 만든다)"""
import base64
import json
from pathlib import Path

import numpy as np

from lake_poly import signed_distance

ROOT = Path(__file__).resolve().parents[2]
CELL = 0.25
MAX_SIZE = 384
RANGE = 4.0
FAR_RANGE = 32.0
PAD = 2.0


def main() -> None:
    spots = json.loads((ROOT / "data/fish/spots.json").read_text(encoding="utf-8"))["spots"]
    out_dir = ROOT / "data/fish/sdf"
    out_dir.mkdir(parents=True, exist_ok=True)
    for spot in spots:
        if "outline" not in spot:
            continue
        hx, hz = spot["half_x"] + PAD, spot["half_z"] + PAD
        size = min(int(np.ceil(2 * max(hx, hz) / CELL)), MAX_SIZE)
        xs = spot["x"] + ((np.arange(size) + 0.5) / size * 2 - 1) * hx
        zs = spot["z"] + ((np.arange(size) + 0.5) / size * 2 - 1) * hz
        px, pz = np.meshgrid(xs, zs)
        sd = signed_distance(np.array(spot["outline"], dtype=float), px, pz)
        near = np.clip(np.rint((np.clip(sd / RANGE, -1, 1) * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)
        far = np.clip(np.rint((np.clip(sd / FAR_RANGE, -1, 1) * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)
        value = np.stack([near, far], axis=-1)
        doc = {"id": spot["id"], "size": size, "range": RANGE, "far_range": FAR_RANGE, "channels": 2, "half": [round(hx, 3), round(hz, 3)],
               "data": base64.b64encode(value.tobytes()).decode("ascii")}
        path = out_dir / f"{spot['id']}.json"
        path.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
        print(path, len(doc["data"]))


if __name__ == "__main__":
    main()
