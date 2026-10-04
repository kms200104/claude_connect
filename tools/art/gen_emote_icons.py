#!/usr/bin/env python3
"""감정표현 아이콘 (말풍선 안의 그림·글씨)을 만든다: assets/ui/emotes/<id>.png (160×160, 투명 배경).
감정표현 칸·머리 위 말풍선(Sprite3D)이 같은 그림을 쓴다. 사용: python3 tools/art/gen_emote_icons.py  (pillow 필요)
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/emotes"
FONT = str(ROOT / "assets/fonts/jua_regular.ttf")
S = 4  # 4배로 그려서 줄인다 (부드러운 가장자리)
SIZE = 160
INK = (92, 62, 38, 255)
BUBBLE = (255, 251, 242, 255)
EDGE = (138, 102, 70, 255)


def canvas():
    im = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def bubble(d):
    w = SIZE * S
    pad = 10 * S
    # 꼬리 (아래 가운데)
    tail = [(w * 0.42, w * 0.78), (w * 0.5, w * 0.95), (w * 0.6, w * 0.78)]
    d.polygon(tail, fill=EDGE)
    d.rounded_rectangle([pad, pad, w - pad, w * 0.82], radius=34 * S, fill=EDGE)
    inner = 6 * S
    d.rounded_rectangle([pad + inner, pad + inner, w - pad - inner, w * 0.82 - inner], radius=28 * S, fill=BUBBLE)
    d.polygon([(w * 0.445, w * 0.77), (w * 0.5, w * 0.89), (w * 0.565, w * 0.77)], fill=BUBBLE)


def center():
    return SIZE * S * 0.5, SIZE * S * 0.45


def text(d, s, size, color, dy=0):
    font = ImageFont.truetype(FONT, size * S)
    cx, cy = center()
    box = d.textbbox((0, 0), s, font=font)
    d.text((cx - (box[2] - box[0]) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1] + dy * S), s, font=font, fill=color)


def heart(d, cx, cy, r, color):
    pts = []
    for i in range(80):
        t = math.pi * 2 * i / 80
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * r / 16, cy + y * r / 16))
    d.polygon(pts, fill=color)


def sparkle(d, cx, cy, r, color):
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.35
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color)


def save(im, name):
    OUT.mkdir(parents=True, exist_ok=True)
    im.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")
    print(name)


def hello():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    skin = (247, 214, 176, 255)
    line = (196, 140, 96, 255)
    # 손바닥 + 손가락 넷 + 엄지 (살짝 기울어 흔드는 모양)
    hand = Image.new("RGBA", im.size, (0, 0, 0, 0))
    h = ImageDraw.Draw(hand)
    h.rounded_rectangle([cx - 26 * S, cy - 6 * S, cx + 26 * S, cy + 36 * S], radius=18 * S, fill=skin, outline=line, width=3 * S)
    for i, x in enumerate([-19, -7, 5, 17]):
        top = cy - (34 - abs(i - 1.5) * 4) * S
        h.rounded_rectangle([cx + (x - 5.5) * S, top, cx + (x + 5.5) * S, cy + 6 * S], radius=6 * S, fill=skin, outline=line, width=3 * S)
    h.rounded_rectangle([cx + 20 * S, cy + 2 * S, cx + 40 * S, cy + 14 * S], radius=6 * S, fill=skin, outline=line, width=3 * S)
    h.rectangle([cx - 23 * S, cy - 2 * S, cx + 23 * S, cy + 10 * S], fill=skin)
    hand = hand.rotate(-14, center=(cx, cy + 20 * S), resample=Image.BICUBIC)
    im.alpha_composite(hand)
    for k, a in enumerate([-50, -30]):
        r0, r1 = 44 * S, 54 * S
        for side in (-1, 1):
            ang = math.radians(a if side < 0 else 180 - a)
            d.line([(cx + math.cos(ang) * r0, cy + math.sin(ang) * r0), (cx + math.cos(ang) * r1, cy + math.sin(ang) * r1)], fill=(242, 160, 70, 255), width=5 * S)
    save(im, "hello")


def happy():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    d.ellipse([cx - 34 * S, cy - 32 * S, cx + 34 * S, cy + 34 * S], fill=(255, 214, 90, 255), outline=(214, 150, 40, 255), width=4 * S)
    for side in (-1, 1):
        x = cx + side * 13 * S
        d.arc([x - 8 * S, cy - 14 * S, x + 8 * S, cy + 2 * S], 200, 340, fill=INK, width=4 * S)
    d.chord([cx - 18 * S, cy - 2 * S, cx + 18 * S, cy + 24 * S], 0, 180, fill=(196, 70, 60, 255))
    for side in (-1, 1):
        d.ellipse([cx + side * 24 * S - 6 * S, cy + 4 * S, cx + side * 24 * S + 6 * S, cy + 12 * S], fill=(246, 150, 140, 200))
    sparkle(d, cx + 44 * S, cy - 30 * S, 13 * S, (255, 196, 60, 255))
    sparkle(d, cx - 46 * S, cy - 22 * S, 9 * S, (255, 196, 60, 255))
    save(im, "happy")


def label(name, s, size, color, extra=None):
    im, d = canvas()
    bubble(d)
    text(d, s, size, color)
    if extra:
        extra(d)
    save(im, name)


def surprise():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    d.rounded_rectangle([cx - 9 * S, cy - 40 * S, cx + 9 * S, cy + 14 * S], radius=9 * S, fill=(230, 70, 60, 255))
    d.ellipse([cx - 10 * S, cy + 22 * S, cx + 10 * S, cy + 42 * S], fill=(230, 70, 60, 255))
    for side in (-1, 1):
        d.line([(cx + side * 24 * S, cy - 30 * S), (cx + side * 36 * S, cy - 40 * S)], fill=(242, 160, 70, 255), width=5 * S)
        d.line([(cx + side * 28 * S, cy - 12 * S), (cx + side * 42 * S, cy - 14 * S)], fill=(242, 160, 70, 255), width=5 * S)
    save(im, "surprise")


def love():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    heart(d, cx, cy + 2 * S, 40 * S, (236, 96, 128, 255))
    heart(d, cx - 8 * S, cy - 8 * S, 12 * S, (250, 170, 190, 255))
    heart(d, cx + 42 * S, cy - 30 * S, 11 * S, (246, 140, 170, 255))
    save(im, "love")


def sad():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    blue = (100, 160, 230, 255)
    d.polygon([(cx, cy - 40 * S), (cx - 24 * S, cy + 6 * S), (cx + 24 * S, cy + 6 * S)], fill=blue)
    d.ellipse([cx - 25 * S, cy - 12 * S, cx + 25 * S, cy + 38 * S], fill=blue)
    d.ellipse([cx - 13 * S, cy - 2 * S, cx - 3 * S, cy + 12 * S], fill=(200, 230, 255, 255))
    save(im, "sad")


def angry():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    red = (226, 64, 56, 255)
    for qx, qy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
        ox, oy = cx + qx * 30 * S, cy + qy * 30 * S
        box = [ox - 24 * S, oy - 24 * S, ox + 24 * S, oy + 24 * S]
        start = {(-1, -1): 0, (1, -1): 90, (1, 1): 180, (-1, 1): 270}[(qx, qy)]
        d.arc(box, start, start + 90, fill=red, width=11 * S)
    save(im, "angry")


def think():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    for i in range(3):
        x = cx + (i - 1) * 24 * S
        d.ellipse([x - 8 * S, cy - 8 * S, x + 8 * S, cy + 8 * S], fill=INK)
    save(im, "think")


def clap():
    def extra(d):
        cx, cy = center()
        sparkle(d, cx - 44 * S, cy - 34 * S, 11 * S, (255, 196, 60, 255))
        sparkle(d, cx + 46 * S, cy + 26 * S, 9 * S, (255, 196, 60, 255))
    label("clap", "짝짝", 50, (222, 120, 50, 255), extra)


def sleepy():
    im, d = canvas()
    bubble(d)
    cx, cy = center()
    blue = (90, 120, 200, 255)
    for (x, y, size) in [(-20, 12, 46), (14, -10, 34), (38, -30, 24)]:
        font = ImageFont.truetype(FONT, size * S)
        d.text((cx + x * S - size * S * 0.3, cy + y * S - size * S * 0.55), "Z", font=font, fill=blue)
    save(im, "sleepy")


if __name__ == "__main__":
    hello()
    happy()
    label("laugh", "하하", 54, (226, 120, 60, 255))
    surprise()
    love()
    sad()
    angry()
    think()
    clap()
    label("bow", "꾸벅", 50, (120, 150, 90, 255))
    sleepy()
