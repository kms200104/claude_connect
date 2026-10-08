#!/usr/bin/env python3
"""물고기 살갗 텍스처 (v0.16): data/fish/fish.json 의 색 · 무늬와 data/fish/fish_plans.json 의 몸 설계로
assets/textures/fish/<id>.jpg 를 그린다. FishModel(game/props/fish_model.gd)의 UV 배치와 짝이다.

  512 × 256 한 장:
    몸     x 0.01~0.99 = 주둥이 u 0 → 꼬리자루 u 1,  y 0.01~0.71 = 등(0) → 한쪽 옆 → 배(π) → 다른 옆 → 등(2π)
    지느러미 x 0.01~0.74 = 지느러미 밑동 따라, y 0.76~0.98 = 밑동 → 끝
    눈     가운데 (0.875, 0.87), 반지름 x 0.1 · y 0.2 (픽셀로는 동그라미)
  사진처럼: 등은 짙고 배는 밝은 그늘(countershading), 겹친 비늘의 뒤쪽 테, 옆줄 구멍, 아가미뚜껑 테, 무늬(점 · 띠 · 줄),
  은빛 물고기의 무지갯빛, 상어의 아가미구멍 · 매끈한 살갗, 지느러미의 줄기(ray)와 비치는 가장자리, 금빛 눈동자.
사용: python3 tools/art/gen_fish_textures.py [물고기 id …]   (numpy, Pillow)
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/textures/fish"
W, H = 512, 256
BODY_Y = (0.01, 0.71)
FIN_X = (0.01, 0.74)
FIN_Y = (0.76, 0.98)
EYE_C = (0.875, 0.87)
EYE_R = (0.1, 0.2)


def hexcol(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def value_noise(shape, scale, seed):
    """부드러운 값 잡음 (0~1). scale = 칸 수."""
    rng = np.random.default_rng(seed)
    gh, gw = int(scale[0]) + 2, int(scale[1]) + 2
    grid = rng.random((gh, gw))
    ys = np.linspace(0, scale[0], shape[0])
    xs = np.linspace(0, scale[1], shape[1])
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - yi, xs - xi
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = grid[yi][:, xi]
    b = grid[yi][:, xi + 1]
    c = grid[yi + 1][:, xi]
    d = grid[yi + 1][:, xi + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def plan_of(plans, shape):
    p = dict(plans.get(shape) or plans["slim"])
    if "base" in p:
        base = dict(plans[p["base"]])
        base.update({k: v for k, v in p.items() if k != "base"})
        p = base
    return p


def prof_at(plan, u):
    pts = plan["prof"]
    us = [q[0] for q in pts]
    return [np.interp(u, us, [q[i] for q in pts]) for i in (1, 2, 3)]


def paint(fish, plans, seed):
    look = fish["look"]
    plan = plan_of(plans, look["shape"])
    L = plan["L"]
    body, belly, fin = hexcol(look["body"]), hexcol(look["belly"]), hexcol(look["fin"])
    accent = hexcol(look.get("accent", look["body"]))
    iris = hexcol(look.get("iris", "#C8A040"))
    pattern = look.get("pattern", "")
    shape = look["shape"]
    shark = shape in ("shark", "hammerhead")
    img = np.ones((H, W, 3)) * body
    rng = np.random.default_rng(seed)

    # ---- 몸 ----
    y0, y1 = int(BODY_Y[0] * H), int(BODY_Y[1] * H)
    x0, x1 = int(0.01 * W), int(0.99 * W)
    bh, bw = y1 - y0, x1 - x0
    u = np.linspace(0, 1, bw)[None, :].repeat(bh, 0)
    th = np.linspace(0, 2 * math.pi, bh)[:, None].repeat(bw, 1)
    vert = np.cos(th)
    top, bot, half = prof_at(plan, u)
    r_eff = (top + bot) * 0.5 * L + 1e-4
    # 등 → 배 그늘 (등은 짙게, 배는 밝게, 옆구리는 그 사이). 상어 · 다랑어는 경계가 또렷하다.
    sharp = 0.25 if shark or shape == "tuna" else 0.55
    k = smooth(-0.62 - sharp * 0.2, 0.0 + sharp * 0.25, vert)
    col = belly[None, None, :] * (1 - k[..., None]) + body[None, None, :] * k[..., None]
    col *= (1.0 - 0.22 * smooth(0.55, 1.0, vert))[..., None]
    col = col * (1 - 0.12 * smooth(-0.95, -1.0, -vert))[..., None]
    # 은빛 무지갯빛 (밝고 채도 낮은 옆구리).
    sat = body.max() - body.min()
    if body.mean() > 0.45 and sat < 0.25 or shape in ("tuna", "ribbon"):
        band = np.exp(-((vert - 0.15) / 0.35) ** 2)
        hue = np.stack([0.06 * np.sin(u * 9 + 1.0), 0.03 * np.sin(u * 7 + 2.0), 0.08 * np.cos(u * 6)], -1)
        col += band[..., None] * (hue + 0.08)
    # 얼룩덜룩한 결 (두 겹 잡음).
    n1 = value_noise((bh, bw), (6, 18), seed)
    n2 = value_noise((bh, bw), (24, 90), seed + 1)
    col *= (0.93 + 0.1 * n1 + 0.05 * n2)[..., None]
    # 머리(아가미뚜껑 앞)와 몸.
    oper = plan["oper"]
    edge_u = oper - 0.04 * (1 - vert ** 2)
    head = smooth(0.004, -0.004, u - edge_u)
    # 비늘: 겹친 비늘의 뒤쪽 테 (아가미뚜껑 뒤부터, 배로 갈수록 옅게).
    sc = plan.get("scales", 0.02)
    if sc > 0:
        s_len = u * L / (sc * L)
        c_len = th * r_eff / (sc * L * 0.78)
        row = np.floor(c_len)
        col_f = s_len + 0.5 * (row % 2)
        fx = col_f - np.floor(col_f)
        fy = c_len - row
        arc = fx + 0.22 * np.cos(math.pi * (fy - 0.5) * 2) * 0.5
        rim = smooth(0.72, 0.9, arc) * (1 - smooth(0.9, 1.0, arc))
        shine = np.exp(-(((fx - 0.4) / 0.28) ** 2 + ((fy - 0.5) / 0.35) ** 2))
        strength = (1 - head) * (0.45 + 0.55 * smooth(-0.6, 0.4, vert)) * smooth(0.0, 0.02, 1.0 - u)
        col *= (1 - 0.2 * rim * strength)[..., None]
        col += (0.06 * shine * strength)[..., None]
    else:
        # 매끈한 살갗: 잔결 (상어는 고운 비늘가죽).
        fine = value_noise((bh, bw), (60, 220), seed + 2)
        col *= (0.96 + 0.06 * fine)[..., None]
    # 아가미뚜껑 테와 뺨 빛.
    if not shark and shape not in ("lamprey",):
        line = np.exp(-((u - edge_u) / 0.006) ** 2) * smooth(-0.85, -0.5, vert) * smooth(0.95, 0.75, vert)
        col *= (1 - 0.35 * line)[..., None]
        cheek = head * np.exp(-((vert - 0.0) / 0.5) ** 2) * smooth(0.02, 0.08, u)
        col += (0.05 * cheek)[..., None]
    # 옆줄: 아가미 뒤에서 꼬리까지, 머리 쪽이 조금 높다.
    if sc > 0 and shape not in ("goldfish",):
        ll = 0.32 - 0.25 * u
        line = np.exp(-((vert - ll) / 0.018) ** 2) * (1 - head) * smooth(0.0, 0.03, 1 - u)
        dots = 0.5 + 0.5 * np.cos(u * L / (sc * L) * 2 * math.pi)
        col *= (1 - 0.28 * line * dots)[..., None]
    # ---- 무늬 ----
    meters_u = u * L

    def blot(cu, cv, rad, color, amount, soft=0.6):
        nonlocal col
        for th0 in (cv, 2 * math.pi - cv):
            d = np.sqrt(((meters_u - cu * L)) ** 2 + ((th - th0) * r_eff) ** 2) / (rad * L)
            m = smooth(1.0, soft, d) * amount
            col = col * (1 - m[..., None]) + color[None, None, :] * m[..., None]

    if pattern == "spots":
        many = 28 if shark else 22
        for _ in range(many):
            cu = rng.uniform(max(oper, 0.12), 0.95)
            cv = math.acos(rng.uniform(-0.35, 0.95))
            rad = rng.uniform(0.008, 0.016) if shark else rng.uniform(0.012, 0.03)
            blot(cu, cv, rad, accent, 0.9 if shark else 0.75)
    elif pattern == "band":
        if shape == "tuna":
            # 고등어 · 다랑어: 등에 물결 줄무늬.
            waves = np.sin(u * 46 + np.sin(th * 3.0) * 2.2)
            m = smooth(0.45, 0.85, waves) * smooth(0.25, 0.6, vert) * (1 - head)
            col = col * (1 - 0.8 * m[..., None]) + accent[None, None, :] * 0.8 * m[..., None]
        elif shape == "trout":
            # 무지개송어 · 은어: 옆구리 분홍(노랑) 띠 + 등의 잔점.
            m = np.exp(-((vert - 0.05) / 0.22) ** 2) * (1 - head * 0.5)
            col = col * (1 - 0.55 * m[..., None]) + accent[None, None, :] * 0.55 * m[..., None]
            for _ in range(36):
                blot(rng.uniform(0.15, 0.98), math.acos(rng.uniform(0.2, 0.95)), rng.uniform(0.006, 0.011), body * 0.35, 0.85)
        else:
            count = 6 if shape in ("perch", "bream") else 5
            for i in range(count):
                cu = oper + 0.06 + (0.92 - oper - 0.06) * i / max(count - 1, 1)
                wob = 0.012 * np.sin(th * 4 + i)
                m = np.exp(-((u - cu - wob) / 0.028) ** 2) * smooth(-0.45, 0.2, vert)
                col = col * (1 - 0.7 * m[..., None]) + accent[None, None, :] * 0.7 * m[..., None]
    elif pattern == "stripe":
        m = np.exp(-((vert - 0.02) / 0.09) ** 2) * smooth(oper - 0.02, oper + 0.06, u)
        col = col * (1 - 0.75 * m[..., None]) + accent[None, None, :] * 0.75 * m[..., None]
    # 상어: 아가미구멍 다섯 줄 · 가슴 위 그늘.
    if "gills" in plan:
        g0, g1, n = plan["gills"]
        for i in range(int(n)):
            gu = g0 + (g1 - g0) * i / max(n - 1, 1)
            m = np.exp(-((u - gu - 0.01 * vert) / 0.0035) ** 2) * smooth(-0.35, -0.1, vert) * smooth(0.55, 0.3, vert)
            col *= (1 - 0.55 * m)[..., None]
    if "pores" in plan:
        for i in range(int(plan["pores"])):
            blot(0.12 + 0.022 * i, math.acos(0.3), 0.007, body * 0.25, 0.9)
    # 입 (주둥이 끝의 어두운 틈) · 눈 둘레 그늘.
    mh, ms = plan["mouth"]
    m = np.exp(-((vert - mh) / 0.05) ** 2) * smooth(ms * 1.4, ms * 0.3, u) * (1 if not shark else 0.8)
    col *= (1 - 0.6 * m)[..., None]
    eu, eh, er = plan["eye"]
    if "hammer" not in plan:
        blot(eu, math.acos(max(-0.99, min(0.99, eh))), er * 1.5, body * 0.55, 0.35, soft=0.2)
    img[y0:y1, x0:x1] = np.clip(col, 0, 1)

    # ---- 지느러미: 밑동은 짙고 끝은 비치듯 밝다, 줄기(ray)가 부챗살처럼 ----
    fy0, fy1 = int(FIN_Y[0] * H), int(FIN_Y[1] * H)
    fx0, fx1 = int(FIN_X[0] * W), int(FIN_X[1] * W)
    fh, fw = fy1 - fy0, fx1 - fx0
    s = np.linspace(0, 1, fw)[None, :].repeat(fh, 0)
    t = np.linspace(0, 1, fh)[:, None].repeat(fw, 1)
    fcol = fin[None, None, :] * (0.78 + 0.25 * t[..., None])
    fcol = fcol * (1 - 0.3 * t[..., None]) + np.array([1.0, 1.0, 1.0])[None, None, :] * 0.3 * t[..., None] * (0.3 if shark else 1.0)
    rays = np.abs(np.sin(s * math.pi * 30))
    fcol *= (1 - 0.22 * smooth(0.85, 1.0, rays) * (0.4 + 0.6 * (1 - t)))[..., None]
    fcol *= (0.94 + 0.08 * value_noise((fh, fw), (4, 24), seed + 3))[..., None]
    if shark or shape == "tuna":
        fcol *= (1 - 0.18 * smooth(0.7, 1.0, t))[..., None]
    if pattern == "spots" and shape in ("trout", "perch", "goldfish"):
        for _ in range(16):
            cx, cy = rng.uniform(0, 1), rng.uniform(0.2, 0.9)
            d = np.sqrt(((s - cx) * fw) ** 2 + ((t - cy) * fh) ** 2)
            fcol *= (1 - 0.5 * smooth(4.0, 2.0, d))[..., None]
    img[fy0:fy1, fx0:fx1] = np.clip(fcol, 0, 1)

    # ---- 눈: 금빛 홍채 (방사형 결) + 검은 눈동자 + 반짝 ----
    yy, xx = np.mgrid[0:H, 0:W]
    ex, ey = (xx / W - EYE_C[0]) / EYE_R[0], (yy / H - EYE_C[1]) / EYE_R[1]
    r = np.sqrt(ex ** 2 + ey ** 2)
    a = np.arctan2(ey, ex)
    inside = r <= 1.05
    streak = 0.85 + 0.15 * np.sin(a * 23 + r * 6)
    iris_col = iris[None, None, :] * (0.6 + 0.55 * (1 - r))[..., None] * streak[..., None]
    eye = np.where((r < 0.98)[..., None], iris_col, np.array([0.08, 0.07, 0.06]))
    pupil = r < (0.5 if not shark else 0.45)
    if shark:
        pupil = (np.abs(ex) < 0.18) & (r < 0.75)
    eye = np.where(pupil[..., None], np.array([0.02, 0.02, 0.03]), eye)
    hl = np.exp(-(((ex + 0.32) / 0.18) ** 2 + ((ey + 0.34) / 0.14) ** 2))
    eye = eye + hl[..., None] * 0.9
    img = np.where(inside[..., None], np.clip(eye, 0, 1), img)
    return (img * 255).astype(np.uint8)


def main():
    fish = json.load(open(ROOT / "data/fish/fish.json"))["fish"]
    plans = json.load(open(ROOT / "data/fish/fish_plans.json"))
    only = set(sys.argv[1:])
    OUT.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(fish):
        if only and f["id"] not in only:
            continue
        if f["look"]["shape"] in ("crayfish", "turtle"):
            continue
        img = paint(f, plans, 1000 + sum(map(ord, f["id"])))
        path = OUT / f"{f['id']}.jpg"
        Image.fromarray(img).save(path, quality=90)
        print("fish", f["id"], path.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
