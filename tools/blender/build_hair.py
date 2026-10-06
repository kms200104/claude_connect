#!/usr/bin/env python3
"""캐릭터 머리카락 모형을 Blender(bpy)로 만든다 → assets/models/hair/<스타일>.glb (+ _mid · _low).

참고: art_source/reference/character_sheet.png (모동숲 같은 찰흙 단발 — 앞 · 옆 · 뒤).
  - 머리카락은 조각조각 붙인 다발이 아니라 **매끈한 찰흙 덩어리**: 정수리가 높고 둥글게 솟아, 아래로 갈수록 넓어지다가
    끝이 두툼하게 안으로 말려 들어가는 **초코송이(버섯 갓) 모양**.
  - 겉면에 빗으로 쓸어 놓은 듯한 **가늘고 얕은 결**이 흐르고(옆으로 넘긴 머리는 결도 비스듬히), 정수리 쪽은 옅다.
  - 얼굴 쪽은 깔끔한 창: 옆머리는 따로 늘어뜨린 **커튼**(얼굴 쪽 세로 가장자리가 둥글게 말린다),
    앞머리는 그 아래로 들어가는 **따로 된 판**(눈썹 위에서 둥글게 말린다) — 칸마다 길이를 바꿔 자르면 관자놀이에 틈이 생긴다.
  - 올림머리·꼬리·땋은 머리·삐침은 같은 찰흙 덩어리(공 · 관 · 둥근 뿔)로 붙이고 결을 낸다.
색은 게임이 입힌다 (머리 색 10가지): 정점 색 R = 그늘(AO × 결), G = 정수리 둘레 윤기 띠, B·A = 1.
머리끈은 색이 따로라 게임(절차, CharacterModel._hair_accessories)에서 그린다 — 자리는 아래 TIE_* 와 같게.
귀: bob · long · side 는 귀를 덮고, 나머지는 귀 위·뒤로 지나가 귀가 보인다 (CharacterModel._hair_cover_bottom).

좌표: 게임 머리 좌표 (Y 위, 얼굴이 -Z, 머리 가운데 HEAD_CENTER = (0, 0.4, 0), 머리 꼭대기 y 0.77 · 턱 y 0.03,
귀 (±0.4, 0.33)). 둘레 a(도): 0 = 얼굴 앞, +90 = 캐릭터 왼쪽(+X), ±180 = 뒤.
내보낼 때 X 축 +90° → glTF 가 다시 Y 위로.
사용: python3 tools/blender/build_hair.py [스타일 …]      (pip install bpy — Blender 5.0 파이썬 모듈)
"""
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/hair'

# game/player/character_model.gd 와 같은 값.
HEAD_CENTER = Vector((0.0, 0.4, 0.0))
HEAD_RADII = Vector((0.37, 0.37, 0.3))
HEAD_JOWL = 0.11
HAIR_CENTER = Vector((0.0, 0.43, 0.02))
Z_OFF = 0.035  # 머리카락은 머리보다 조금 뒤에 앉는다

# 머리끈 자리 (CharacterModel._hair_accessories 와 같은 값).
TIE_PONYTAIL = Vector((0.0, 0.72, 0.43))
TIE_PIGTAILS = Vector((0.4, 0.38, 0.17))  # x 는 양쪽 ±

# 화질(촘촘함 0 절약 · 1 중간 · 2 고화질)별: (둘레 칸(360° 기준), 세로 마디, 결 개수(360° 기준), 관 마디, 관 둘레).
GRID = {0: (56, 9, 16, 8, 8), 1: (84, 13, 26, 12, 10), 2: (120, 18, 38, 16, 14)}
QUALITY = {'_low': 0, '_mid': 1, '': 2}


def rad(d):
    return math.radians(d)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def wrap(a):
    """둘레 각을 -180 ~ 180 으로."""
    return ((a + 180.0) % 360.0) - 180.0


def resample(points, count):
    """꺾은선을 길이가 같은 count 개 점으로 다시 나눈다 (points: (r, y) 목록)."""
    seg = [math.dist(points[i], points[i + 1]) for i in range(len(points) - 1)]
    total = sum(seg)
    out = []
    for k in range(count):
        d = total * k / (count - 1)
        i = 0
        while i < len(seg) - 1 and d > seg[i]:
            d -= seg[i]
            i += 1
        t = 0.0 if seg[i] == 0 else min(1.0, d / seg[i])
        out.append((lerp(points[i][0], points[i + 1][0], t), lerp(points[i][1], points[i + 1][1], t)))
    return out


def cut(points, y_end):
    """윤곽(위 → 아래)을 높이 y_end 에서 자른다."""
    out = [points[0]]
    for i in range(1, len(points)):
        p0, p1 = points[i - 1], points[i]
        if p1[1] >= y_end:
            out.append(p1)
            continue
        t = (p0[1] - y_end) / max(1e-6, p0[1] - p1[1])
        out.append((lerp(p0[0], p1[0], t), y_end))
        break
    if len(out) < 2:
        out.append((points[0][0] + 0.01, points[0][1] - 0.01))
    return out


_COMB = {}


def combed(x, seed=7):
    """빗으로 쓸어 놓은 결 하나하나: x = 결 단위 좌표(정수 하나가 결 한 칸). 0(평평) ~ 1(골 가운데).
    골마다 깊이·자리가 조금씩 달라 자연스럽다."""
    i = math.floor(x)
    key = (seed, i)
    if key not in _COMB:
        rnd = random.Random(seed * 100003 + i)
        _COMB[key] = (rnd.uniform(-0.22, 0.22), rnd.uniform(0.5, 1.0))
    jit, amp = _COMB[key]
    f = x - i + jit
    g = max(0.0, 1.0 - abs(f - 0.5) * 2.0 / 0.55)
    return amp * g * g


# ---- 윤곽 ----

def mushroom(top=0.93, width=0.555, low=0.17):
    """초코송이 갓 윤곽 (r, y): 정수리가 높이 둥글게 솟고, 아래로 갈수록 넓어지다 턱선 쪽에서 가장 넓다.
    low 아래로 더 늘어뜨리면(긴 머리) 넓이를 유지하며 곧게 내려온다."""
    k = width / 0.555
    pts = [(0.0, top), (0.2 * k, top - 0.012), (0.35 * k, top - 0.065), (0.45 * k, top - 0.155),
           (0.51 * k, top - 0.27), (0.545 * k, top - 0.4), (width, top - 0.53)]
    y = pts[-1][1]
    while y - 0.12 > low:
        y -= 0.12
        pts.append((width - 0.01 * (top - 0.53 - y), y))
    pts.append((pts[-1][0] - 0.004, low))
    return pts


def close_cap(top=0.86, width=0.44, low=0.2):
    """머리에 붙는 짧은 머리 윤곽 (짧은 머리 · 묶은 머리): 정수리가 둥글고 옆은 머리에 가깝게."""
    k = width / 0.44
    return [(0.0, top), (0.17 * k, top - 0.012), (0.3 * k, top - 0.06), (0.39 * k, top - 0.14), (0.43 * k, top - 0.25),
            (0.445 * k, top - 0.37), (0.44 * k, top - 0.48), (0.42 * k, max(low, top - 0.6)), (0.4 * k, low)]


CURL_IN = [(0.03, -0.032), (0.07, -0.036), (0.1, -0.016), (0.116, 0.022), (0.122, 0.08), (0.12, 0.18)]
CURL_OUT = [(-0.025, -0.022), (-0.045, -0.005), (-0.04, 0.02), (-0.01, 0.03), (0.03, 0.03), (0.06, 0.06)]
CURL_SMALL = [(0.012, -0.02), (0.035, -0.026), (0.058, -0.012), (0.07, 0.02)]


# ---- 덩어리 ----

class Hair:
    """한 스타일의 메시를 모은다. 정점마다 결 세기 'groove' 를 남긴다 (굽기에서 결 속을 조금 어둡게)."""

    def __init__(self, q):
        self.q = q
        self.bm = bmesh.new()
        self.layer = self.bm.verts.layers.float.new('groove')
        self.cols, self.rows, self.grooves, self.rings, self.sides = GRID[q]

    def vert(self, p, g=0.0):
        v = self.bm.verts.new(p)
        v[self.layer] = g
        return v

    def quads(self, grid, closed):
        rows, cols = len(grid), len(grid[0])
        for i in range(rows - 1):
            for j in range(cols if closed else cols - 1):
                j2 = (j + 1) % cols
                self.bm.faces.new((grid[i][j], grid[i][j2], grid[i + 1][j2], grid[i + 1][j]))

    def curtain(self, profile, a0, a1, length, sz=lambda a: 0.9, curl=CURL_IN, curl_k=lambda a: 1.0,
                rf=lambda a, y: 1.0, groove=0.013, tilt=lambda a, t: 0.0, wave=lambda a, y, t: 0.0,
                edge=0.0, fade_from=0.08, seed=7):
        """머리 겉 껍질 한 장: 둘레 a0 ~ a1(도), 칸마다 profile 을 length(a) 높이에서 자르고 끝을 curl 로 말아 넣는다.
        a1 - a0 = 360 이면 닫힌 갓. edge > 0 이면 양 옆 세로 가장자리를 둥글게 안으로 말아 넣는다(커튼).
        tilt(a, t) = 결이 비스듬히 흐르는 정도(도), wave(a, y, t) = 반지름 물결(곱슬·웨이브).
        콜백이 받는 a 는 -180 ~ 180."""
        closed = abs(a1 - a0 - 360.0) < 1e-6
        span = a1 - a0
        cols = max(6, int(round(self.cols * span / 360.0)))
        rows = self.rows
        count = cols if closed else cols + 1
        grid = None
        for j in range(count):
            s = j / cols
            a = a0 + span * s
            an = wrap(a)
            body = resample(cut(profile, length(an)), rows)
            end = body[-1]
            k = curl_k(an)
            pts = body + [(end[0] - c[0] * k, end[1] + c[1] * k) for c in curl]
            sa, ca = math.sin(rad(a)), math.cos(rad(a))
            # 커튼 양 끝: 얼굴 쪽 세로 가장자리를 둥글게 (끝 두어 칸이 안으로 말린다).
            side = 1.0
            if not closed and edge > 0.0:
                d = min(s, 1.0 - s) * cols
                side = 1.0 - edge * (1.0 - smoothstep(0.0, 2.5, d)) ** 2
            col = []
            for i, (r, y) in enumerate(pts):
                t = min(1.0, i / (rows - 1))
                inner = i >= rows
                fade = 0.0 if inner else smoothstep(fade_from, fade_from + 0.32, t) * (1.0 - smoothstep(0.93, 1.0, t))
                g = combed((a + tilt(an, t)) / 360.0 * self.grooves, seed) * fade
                # 정수리 쪽은 그대로 두어 앞머리 끝을 덮고, 눈썹 아래부터만 둥글게 만다.
                edge_k = lerp(1.0, side, smoothstep(0.6, 0.48, y))
                rr = r * rf(an, y) * edge_k + (0.0 if inner else wave(an, y, t)) - groove * g
                col.append(self.vert(Vector((rr * sa, y, -rr * ca * sz(an) + Z_OFF)), g))
            if grid is None:
                grid = [[] for _ in range(len(col))]
            for i, v in enumerate(col):
                grid[i].append(v)
        self.quads(grid, closed)
        if closed:
            top = self.vert(Vector((0.0, profile[0][1] + 0.004, Z_OFF)))
            for j in range(cols):
                self.bm.faces.new((top, grid[0][(j + 1) % cols], grid[0][j]))

    def tube(self, path, radius, rings=None, sides=None, groove=0.006, twist=0.0, seed=11, cap_start=True):
        """관 (꼬리 · 땋은 머리 · 옆 가닥 · 삐침): path(u) → 점, radius(u) → 반지름. 끝은 둥글게 모은다.
        결은 관을 따라 흐르고(twist 만큼 비틀린다), 끝으로 갈수록 옅어진다."""
        rings = rings or self.rings
        sides = sides or self.sides
        grid = []
        for i in range(rings + 1):
            u = i / rings
            p = path(u)
            t = (path(min(1.0, u + 0.01)) - path(max(0.0, u - 0.01))).normalized()
            s1 = t.cross(Vector((0.0, 0.0, 1.0)))
            if s1.length < 1e-3:
                s1 = t.cross(Vector((1.0, 0.0, 0.0)))
            s1.normalize()
            s2 = s1.cross(t).normalized()
            r = radius(u)
            row = []
            for k in range(sides):
                ang = math.tau * k / sides
                g = combed((k / sides + twist * u) * max(4, sides // 2), seed) * smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.8, 1.0, u))
                rr = r - groove * g
                row.append(self.vert(p + (s1 * math.cos(ang) + s2 * math.sin(ang)) * rr, g))
            grid.append(row)
        self.quads(grid, True)
        tip = path(1.0) + (path(1.0) - path(0.98)).normalized() * radius(1.0) * 0.6
        c = self.vert(tip)
        for k in range(sides):
            self.bm.faces.new((grid[-1][k], grid[-1][(k + 1) % sides], c))
        if cap_start:
            c = self.vert(path(0.0))
            for k in range(sides):
                self.bm.faces.new((c, grid[0][(k + 1) % sides], grid[0][k]))

    def ball(self, center, radii, swirl=1.2, groove=0.008, seed=13):
        """둥근 덩어리 (올림머리): 결이 소용돌이처럼 감긴다."""
        rows = max(6, self.rows // 2 + 2)
        cols = max(10, self.cols // 4)
        m = max(radii.x, radii.y, radii.z)
        grid = []
        for i in range(1, rows):
            lat = math.pi * (i / rows - 0.5)
            row = []
            for j in range(cols):
                lon = math.tau * j / cols
                g = combed((j / cols + swirl * (i / rows)) * (cols // 2), seed) * math.cos(lat)
                d = Vector((math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon)))
                off = Vector((d.x * radii.x, d.y * radii.y, d.z * radii.z)) * (1.0 - groove * g / m)
                row.append(self.vert(center + off, g))
            grid.append(row)
        self.quads(grid, True)
        for ring, y in ((grid[0], -1.0), (grid[-1], 1.0)):
            c = self.vert(center + Vector((0.0, radii.y * y, 0.0)))
            for j in range(cols):
                self.bm.faces.new((ring[j], ring[(j + 1) % cols], c))

    def spike(self, base, tip, width, bend=Vector((0.0, 0.0, 0.0)), blunt=0.6):
        """둥근 뿔 삐침: base 에서 tip 으로 (가운데가 bend 만큼 휜다), 밑동은 갓 속에 묻힌다.
        blunt 가 작을수록 끝까지 통통하다 (찰흙이라 끝이 바늘처럼 뾰족하지 않게)."""
        def path(u):
            return base.lerp(tip, u) + bend * math.sin(math.pi * u)

        def radius(u):
            return max(0.008, width * (1.0 - u) ** blunt)
        self.tube(path, radius, rings=max(4, self.rings // (2 if self.q == 2 else 3)), sides=max(6, self.sides - 4), groove=0.004,
                  cap_start=False)


# ---- 스타일 ----

FACE = 54.0  # 얼굴 창 절반 폭(도): 커튼은 그 바깥, 앞머리는 그 안쪽


def bangs(h, profile, brow, span=FACE + 10.0, sz=0.8, curl=CURL_SMALL, tilt=lambda a, t: 0.0, rf=lambda a, y: 0.985,
          wave=lambda a, y, t: 0.0):
    """앞머리 판: 얼굴 창 위를 덮고 brow(a) 높이에서 둥글게 말린다. 양 끝은 커튼 아래로 들어간다."""
    h.curtain(profile, -span, span, brow, sz=lambda a: sz, curl=curl,
              rf=lambda a, y: rf(a, y) * (1.0 - 0.05 * smoothstep(span - 12.0, span, abs(a))),
              tilt=tilt, wave=wave, groove=0.009, fade_from=0.18, seed=3)


def side_curtain(h, profile, length, sz=lambda a: lerp(0.8, 0.94, smoothstep(40.0, 160.0, abs(a))), hug=0.0,
                 rf=lambda a, y: 1.0, **kw):
    """얼굴 창 바깥(귀 앞 ~ 뒤)을 도는 커튼. 얼굴 쪽 세로 가장자리는 둥글게 말린다.
    hug > 0 이면 눈 아래 볼 쪽 옆머리를 볼에 붙여, 앞에서 볼 때 커튼과 볼 사이로 안쪽이 비치지 않게 한다."""
    def hugged(a, y):
        return rf(a, y) * (1.0 - hug * (1.0 - smoothstep(FACE, FACE + 35.0, abs(a))) * smoothstep(0.55, 0.36, y))
    h.curtain(profile, FACE, 360.0 - FACE, length, sz=sz, edge=0.12, rf=hugged, **kw)


def style_bob(h):
    """청록 히메컷 단발 (참고 그림): 초코송이처럼 높이 솟은 갓, 턱선에서 두툼하게 말린 끝, 일자 앞머리."""
    prof = mushroom(top=0.95, width=0.56, low=0.16)
    side_curtain(h, prof, lambda a: 0.16 + 0.01 * smoothstep(60.0, 120.0, abs(a)), hug=0.16)
    bangs(h, prof, lambda a: 0.505 + 0.006 * math.sin(rad(a) * 9.0) + 0.01 * smoothstep(30.0, FACE, abs(a)))


def style_long(h):
    """갈색 웨이브 롱: 어깨 아래까지 물결치며 내려오고, 옆으로 넘긴 앞머리."""
    prof = mushroom(top=0.94, width=0.54, low=-0.36)

    def wave(a, y, t):
        return 0.022 * smoothstep(0.32, 0.15, y) * math.sin(y * 26.0 + a * 0.05)
    side_curtain(h, prof, lambda a: -0.3 - 0.06 * smoothstep(80.0, 170.0, abs(a)), wave=wave, curl=CURL_SMALL, hug=0.14,
                 rf=lambda a, y: 1.0 - 0.06 * smoothstep(0.2, -0.3, y))
    bangs(h, prof, lambda a: 0.47 + 0.11 * smoothstep(-40.0, 50.0, a), tilt=lambda a, t: -25.0 * t)


def style_side(h):
    """파랑 옆으로 넘긴 중단발: 한쪽으로 길게 넘긴 앞머리, 턱 아래에서 바깥으로 뻗친 끝."""
    prof = mushroom(top=0.94, width=0.55, low=0.04)
    side_curtain(h, prof, lambda a: 0.06, curl=CURL_OUT, hug=0.14,
                 curl_k=lambda a: lerp(0.25, 0.75, smoothstep(FACE, FACE + 30.0, abs(a))))
    bangs(h, prof, lambda a: 0.42 + 0.2 * smoothstep(-30.0, 55.0, a), tilt=lambda a, t: -28.0 * t)


def style_curly(h):
    """초록 웨이브: 가운데 가르마, 볼록볼록한 겉면, 턱 아래로 물결치는 옆머리."""
    prof = mushroom(top=0.95, width=0.57, low=0.08)

    def bumps(a, y, t):
        return 0.02 * math.sin(a * 0.21 + y * 17.0) * math.sin(a * 0.13 - y * 11.0) * smoothstep(0.1, 0.5, t)
    side_curtain(h, prof, lambda a: 0.08 + 0.03 * math.sin(rad(a) * 6.0), wave=bumps, curl_k=lambda a: 0.8, hug=0.14)
    # 가운데 가르마: 앞머리가 가운데에서 갈라져 양옆으로 내려간다.
    bangs(h, prof, lambda a: 0.6 - 0.11 * smoothstep(0.0, 45.0, abs(a)), wave=bumps,
          rf=lambda a, y: 0.985 - 0.04 * (1.0 - smoothstep(0.0, 6.0, abs(a))) * smoothstep(0.62, 0.9, y),
          tilt=lambda a, t: math.copysign(20.0, a) * t)


def style_pigtails(h):
    """보라 땋은 양갈래: 일자 앞머리, 귀 뒤에서 묶어 마디진 땋은 머리를 늘어뜨린다."""
    prof = close_cap(top=0.9, width=0.465, low=0.3)
    side_curtain(h, prof, lambda a: 0.4 - 0.08 * smoothstep(100.0, 170.0, abs(a)), curl=CURL_SMALL)
    bangs(h, prof, lambda a: 0.52 + 0.01 * smoothstep(30.0, FACE, abs(a)), sz=0.86)
    for side in (-1.0, 1.0):
        root = Vector((TIE_PIGTAILS.x * side, TIE_PIGTAILS.y, TIE_PIGTAILS.z))

        def path(u, root=root, side=side):
            return root + Vector((0.07 * u * side, -0.42 * u, 0.02 * u))

        def radius(u):
            bead = 0.82 + 0.18 * abs(math.cos(u * math.pi * 4.5))
            return 0.068 * bead * (1.0 - 0.45 * smoothstep(0.85, 1.0, u))
        h.tube(path, radius, rings=h.rings + (6 if h.q == 2 else 2), groove=0.008, twist=1.5)


def tail_path(u):
    """포니테일 꼬리 길 (묶은 자리에서 뒤로 휘어 나왔다가 아래로)."""
    return TIE_PONYTAIL + Vector((0.05 * u, 0.03 * u - 0.5 * u * u, 0.17 * math.sin(u * math.pi * 0.5) - 0.02 * u))


def style_ponytail(h):
    """검정 포니테일: 뒤로 매끈하게 빗어 넘긴 머리, 옆으로 넘긴 앞머리, 뒤통수 위에서 묶어 휘어 내린 꼬리. 귀가 보인다."""
    prof = close_cap(top=0.88, width=0.45, low=0.18)
    side_curtain(h, prof, lambda a: lerp(0.47, 0.3, smoothstep(110.0, 170.0, abs(a))), curl=CURL_SMALL)
    bangs(h, prof, lambda a: 0.53 + 0.1 * smoothstep(-40.0, 50.0, a), tilt=lambda a, t: -22.0 * t, sz=0.86)

    def radius(u):
        # 묶은 자리는 잘록, 바로 아래가 가장 통통하고 끝으로 모인다.
        return 0.07 + 0.065 * smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(0.45, 1.0, u)) - 0.03 * smoothstep(0.7, 1.0, u)
    h.tube(tail_path, radius, rings=h.rings + 4, groove=0.009, twist=0.6)


def style_bun(h):
    """금발 똥머리: 옆으로 넘긴 앞머리, 얼굴 옆 두 가닥, 정수리 위 동그란 올림머리. 귀가 보인다."""
    prof = close_cap(top=0.87, width=0.45, low=0.2)
    side_curtain(h, prof, lambda a: lerp(0.46, 0.3, smoothstep(110.0, 170.0, abs(a))), curl=CURL_SMALL)
    bangs(h, prof, lambda a: 0.54 + 0.08 * smoothstep(50.0, -40.0, a), tilt=lambda a, t: 22.0 * t, sz=0.86)
    h.ball(Vector((0.0, 0.98, 0.06)), Vector((0.16, 0.14, 0.16)), swirl=1.4)
    for side in (-1.0, 1.0):
        def path(u, side=side):
            return Vector((0.37 * side + 0.035 * side * math.sin(u * math.pi * 0.8), 0.6 - 0.36 * u, -0.17 + 0.02 * u))
        h.tube(path, lambda u: 0.036 * (1.0 - 0.55 * smoothstep(0.5, 1.0, u)), rings=max(6, h.rings // 2),
               sides=max(6, h.sides - 4), groove=0.004)


def style_short(h):
    """분홍 삐죽 숏컷: 끝이 뾰족한(둥근 뿔) 앞머리가 이리저리 뻗치고, 목덜미도 뾰족. 귀가 보인다."""
    prof = close_cap(top=0.88, width=0.46, low=0.25)
    side_curtain(h, prof, lambda a: lerp(0.47, 0.32, smoothstep(110.0, 170.0, abs(a))), curl=CURL_SMALL)
    bangs(h, prof, lambda a: 0.56 + 0.03 * smoothstep(30.0, FACE, abs(a)), sz=0.86)
    for a, drop, bend in ((-44.0, 0.1, 6.0), (-20.0, 0.13, -4.0), (4.0, 0.12, 5.0), (28.0, 0.13, -6.0), (50.0, 0.1, 4.0)):
        base = Vector((0.43 * math.sin(rad(a)), 0.6, -0.43 * math.cos(rad(a)) * 0.86 + Z_OFF))
        tip = base + Vector((0.02 * math.sin(rad(a + bend * 3)), -drop, -0.02))
        h.spike(base, tip, 0.05, bend=Vector((0.01 * math.copysign(1, bend), 0.0, -0.015)))
    for a in (150.0, 180.0, 210.0):
        base = Vector((0.4 * math.sin(rad(a)), 0.4, -0.4 * math.cos(rad(a)) * 0.94 + Z_OFF))
        h.spike(base, base + Vector((0.03 * math.sin(rad(a)), -0.13, 0.04)), 0.055)


def style_spiky(h):
    """빨강 부스스 숏: 정수리부터 사방으로 뻗친 뾰족한(끝이 둥근) 찰흙 뿔. 귀가 보인다."""
    prof = close_cap(top=0.87, width=0.46, low=0.25)
    side_curtain(h, prof, lambda a: lerp(0.47, 0.32, smoothstep(110.0, 170.0, abs(a))), curl=CURL_SMALL)
    bangs(h, prof, lambda a: 0.58 + 0.02 * math.sin(rad(a) * 6.0), sz=0.86)
    rnd = random.Random(5)
    for k, a in enumerate(range(-150, 181, 30)):
        e = 52.0 + (12.0 if k % 2 else 0.0)
        d = Vector((math.cos(rad(e)) * math.sin(rad(a)), math.sin(rad(e)), -math.cos(rad(e)) * math.cos(rad(a))))
        base = Vector((0.0, 0.5, Z_OFF)) + Vector((d.x * 0.36, d.y * 0.34, d.z * 0.34))
        tip = base + d * (0.17 + rnd.uniform(-0.03, 0.03)) + Vector((0.0, 0.03, 0.0))
        h.spike(base, tip, 0.1, bend=Vector((rnd.uniform(-0.025, 0.025), 0.02, rnd.uniform(-0.025, 0.025))), blunt=0.45)
    for a in (-30.0, 0.0, 28.0):
        base = Vector((0.42 * math.sin(rad(a)), 0.66, -0.42 * math.cos(rad(a)) * 0.86 + Z_OFF))
        h.spike(base, base + Vector((0.03 * math.sin(rad(a)), -0.08, -0.07)), 0.06)


def style_buzz(h):
    """회색 짧은 남자 머리: 짧게 친 머리, 이마에 짧은 앞머리 자국과 구레나룻. 귀가 보인다."""
    prof = close_cap(top=0.82, width=0.4, low=0.25)
    side_curtain(h, prof, lambda a: lerp(0.44, 0.3, smoothstep(110.0, 170.0, abs(a))), curl=CURL_SMALL,
                 curl_k=lambda a: 0.6, groove=0.007)
    bangs(h, prof, lambda a: 0.64 + 0.015 * math.sin(rad(a) * 8.0), sz=0.9)
    for side in (-1.0, 1.0):
        base = Vector((0.365 * side, 0.5, -0.1))
        h.spike(base, base + Vector((0.004 * side, -0.11, -0.005)), 0.032, blunt=0.3)


STYLES = {'bob': style_bob, 'long': style_long, 'side': style_side, 'curly': style_curly, 'pigtails': style_pigtails,
          'ponytail': style_ponytail, 'bun': style_bun, 'short': style_short, 'spiky': style_spiky, 'buzz': style_buzz}


# ---- 만들기 · 굽기 · 내보내기 ----

def head_proxy():
    """AO 를 구울 때 머리카락 안쪽을 가리는 두상 (게임 머리와 같은 크기)."""
    bm = bmesh.new()
    for i in range(17):
        ny = -1.0 + 2.0 * i / 16
        w = 1.0 + HEAD_JOWL * smoothstep(0.5, -0.3, ny)
        r = math.sqrt(max(0.0, 1.0 - ny * ny)) * w
        for j in range(24):
            t = j / 24 * math.tau
            bm.verts.new(HEAD_CENTER + Vector((HEAD_RADII.x * r * math.cos(t), HEAD_RADII.y * ny, HEAD_RADII.z * r * math.sin(t))))
    bm.verts.ensure_lookup_table()
    for i in range(16):
        for j in range(24):
            a, b = i * 24 + j, i * 24 + (j + 1) % 24
            bm.faces.new((bm.verts[a], bm.verts[b], bm.verts[b + 24], bm.verts[a + 24]))
    me = bpy.data.meshes.new('head')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('head', me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def orient_outward(bm):
    """면이 바깥을 보게: 덩어리(이어진 면 묶음)마다 방향을 맞추고, 덩어리 가운데에서 바깥을 보게 뒤집는다."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.index_update()
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        island, stack = [], [f]
        seen.add(f.index)
        while stack:
            x = stack.pop()
            island.append(x)
            for e in x.edges:
                for y in e.link_faces:
                    if y.index not in seen:
                        seen.add(y.index)
                        stack.append(y)
        center = sum((x.calc_center_median() for x in island), Vector()) / len(island)
        score = sum(x.normal.dot(x.calc_center_median() - center) * x.calc_area() for x in island)
        if score < 0.0:
            bmesh.ops.reverse_faces(bm, faces=island)


def build(style, suffix):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    h = Hair(QUALITY[suffix])
    STYLES[style](h)
    bm = h.bm
    orient_outward(bm)
    me = bpy.data.meshes.new(style)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(style, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    # 게임 좌표(Y 위) → Blender(Z 위).
    rot = Matrix.Rotation(math.pi / 2, 4, 'X')
    ob.data.transform(rot)
    head = head_proxy()
    head.data.transform(rot)
    bake_shade(ob)
    bpy.data.objects.remove(head)
    OUT.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'{style}{suffix}.glb'), export_format='GLB', use_selection=True,
                              export_vertex_color='ACTIVE', export_materials='NONE', export_normals=True, export_apply=True)
    return tri_count(ob)


def bake_shade(ob):
    """정점 색 R = 그늘(AO: 결 속 · 앞머리 아래 · 머리에 닿는 안쪽 × 결), G = 정수리 둘레 윤기 띠."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 96
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.world = scene.world or bpy.data.worlds.new('World')
    scene.world.light_settings.distance = 0.03
    ob.data.materials.append(bpy.data.materials.new('bake'))
    ao = ob.data.color_attributes.new('AO', 'FLOAT_COLOR', 'CORNER')
    ob.data.color_attributes.active_color = ao
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='AO')
    me = ob.data
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    groove = me.attributes.get('groove')
    center = Vector((HAIR_CENTER.x, -HAIR_CENTER.z, HAIR_CENTER.y))  # Blender 좌표
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            d = (v.co - center).normalized()
            facing = max(0.0, v.normal.dot(d))
            # 윤기 띠: 정수리 아래 둘레, 바깥을 보는 면에만, 부드럽게.
            band = smoothstep(0.48, 0.6, d.z) * (1.0 - smoothstep(0.74, 0.86, d.z))
            # AO 는 너무 검지 않게 (찰흙처럼 부드러운 그늘), 결(빗질 골) 속은 조금 더 어둡게.
            shade = 0.35 + 0.65 * ao.data[li].color[0]
            if groove is not None:
                shade *= 1.0 - 0.38 * groove.data[v.index].value
            col.data[li].color = (shade, band * facing * 0.8, 1.0, 1.0)
    me.color_attributes.remove(ao)
    me.color_attributes.active_color = col
    me.materials.clear()


def main():
    styles = sys.argv[1:] or list(STYLES)
    for s in styles:
        counts = {suffix: build(s, suffix) for suffix in QUALITY}
        print(f"[hair] {s:10s} 고화질 {counts['']:5d} · 중간 {counts['_mid']:5d} · 절약 {counts['_low']:5d} tri")


if __name__ == '__main__':
    main()
