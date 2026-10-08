#!/usr/bin/env python3
"""참고 이미지(art_source/reference)에서 로고·HUD 아이콘·아이템 아이콘을 오려 투명 PNG로 저장한다.

배경(회색 단색 또는 바둑판 무늬)과 그 위의 옅은 그림자를 가장자리부터 지우고, 경계는 배경과의 색 차이로 부드럽게 만든다.
사용: python3 tools/art/extract_reference.py   (numpy, pillow, scipy 필요)
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / "art_source" / "reference"

# (원본, 자를 영역 x0, y0, x1, y1, 저장 경로, 긴 변 크기[, 지울 영역(원본 좌표)])
CROPS = [
    ("logo_icons.webp", (286, 10, 652, 222), "assets/ui/logo.png", 720),
    ("logo_icons.webp", (403, 414, 578, 592), "assets/ui/icons/map.png", 128),
    ("logo_icons.webp", (489, 234, 665, 413), "assets/ui/icons/fishing.png", 128),
    ("logo_icons.webp", (610, 416, 781, 590), "assets/ui/icons/shop.png", 128),
    ("furniture.png", (40, 40, 264, 258), "assets/icons/items/log_stool.png", 128),
    ("furniture.png", (340, 72, 708, 258), "assets/icons/items/braided_rug.png", 128),
    ("furniture.png", (814, 20, 990, 276), "assets/icons/items/bookshelf.png", 128),
    ("furniture.png", (70, 283, 434, 563), "assets/icons/items/quilt_bed.png", 128),
    ("furniture.png", (562, 299, 724, 558), "assets/icons/items/flower_pot.png", 128),
    ("furniture.png", (856, 296, 957, 558), "assets/icons/items/floor_lamp.png", 128),
    ("fishing_items.png", (47, 49, 414, 533), "assets/icons/items/rod.png", 128, (300, 330, 414, 533)),
    ("fishing_items.png", (561, 49, 744, 284), "assets/icons/items/wooden_bucket.png", 128),
    ("fishing_items.png", (817, 355, 1001, 524), "assets/icons/items/spiral_shell.png", 128),
]


def background_mask(rgb: np.ndarray, checker: bool) -> np.ndarray:
    """배경이 될 수 있는 화소 (가장자리와 이어진 것만 실제로 지운다)."""
    hi = rgb.max(axis=2)
    lo = rgb.min(axis=2)
    neutral = (hi - lo) < 16
    if checker:
        return neutral & (lo > 170)
    # 단색 배경과 그 위의 옅은 그림자(같은 회색 계열로 조금 어두운 것).
    ref = np.median(rgb[:6, :6].reshape(-1, 3), axis=0)
    return neutral & (lo > ref.min() - 48)


def cut_out(rgb: np.ndarray, checker: bool) -> np.ndarray:
    maybe_bg = background_mask(rgb, checker)
    labels, _ = ndimage.label(maybe_bg)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    bg = np.isin(labels, list(border))
    fg = ~bg
    # 작은 부스러기(워터마크 조각, 바둑판 틈)는 버리고, 가장 큰 덩어리와 그 근처만 남긴다.
    lab, n = ndimage.label(fg)
    if n > 1:
        sizes = ndimage.sum(fg, lab, range(1, n + 1))
        keep = np.zeros(n + 1, bool)
        keep[1:] = sizes >= max(sizes.max() * 0.04, 40)
        fg = keep[lab]
    fg = ndimage.binary_fill_holes(fg)
    if not checker:
        # 낚싯줄과 대 사이처럼 물건에 둘러싸인 배경은 가장자리와 이어지지 않아 남는다. 배경색과 거의 같은 덩어리는 뚫는다.
        ref = np.median(rgb[:6, :6].reshape(-1, 3), axis=0)
        same = (np.abs(rgb - ref).max(axis=2) < 10)
        lab, n = ndimage.label(same & fg)
        if n > 0:
            sizes = ndimage.sum(same, lab, range(1, n + 1))
            big = np.zeros(n + 1, bool)
            big[1:] = sizes > 30
            fg = fg & ~big[lab]
    # 경계 1~2px는 반투명하게: 안쪽으로부터의 거리로 알파를 준다.
    inside = ndimage.distance_transform_edt(fg)
    alpha = np.clip(inside / 1.6, 0.0, 1.0)
    return (alpha * 255).astype(np.uint8)


def save_crop(src: str, box: tuple, out: str, size: int, erase: tuple | None = None) -> None:
    image = Image.open(REF / src).convert("RGB")
    if erase is not None:
        # 이웃 물건이 겹쳐 들어오는 곳은 배경색으로 덮는다.
        bg = image.getpixel((2, 2))
        Image.Image.paste(image, bg, erase)
    crop = np.asarray(image.crop(box)).astype(np.int32)
    alpha = cut_out(crop, src.endswith(".webp"))
    rgba = np.dstack([crop.astype(np.uint8), alpha])
    result = Image.fromarray(rgba, "RGBA")
    bbox = result.getbbox()
    if bbox:
        result = result.crop(bbox)
    w, h = result.size
    scale = size / max(w, h)
    result = result.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    if not out.endswith("logo.png"):
        # 아이콘은 정사각 캔버스 가운데에.
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.paste(result, ((size - result.width) // 2, (size - result.height) // 2), result)
        result = canvas
    target = ROOT / out
    target.parent.mkdir(parents=True, exist_ok=True)
    result.save(target, optimize=True)
    print(f"{out}: {result.size}")


if __name__ == "__main__":
    for entry in CROPS:
        save_crop(*entry)
