#!/usr/bin/env python3
"""캐릭터 머리카락 모형을 Blender(bpy)로 만든다 → assets/models/hair/<스타일>.glb (+ _mid · _low).

절차 머리(CharacterModel._add_hair)는 얇은 리본 가닥과 갈라진 끝 때문에 떡진 것처럼 보였고, 큰 덩어리 몇 개로 빚으면
헬멧처럼 보였다. 여기서는
  - 머리카락 100올쯤이 모인 가는 다발(너비 4~7cm) 수십 개를 두 겹으로 엇갈려 얹고(얇은 속껍질 위),
  - 다발마다 끝이 따로 가늘어져 한 점으로 모이며(갈라지지 않게), 길이·휨이 조금씩 달라 결이 살아 있고,
  - Cycles AO 를 머리(두상) 모형과 함께 구워 다발 사이·머리에 닿는 안쪽이 어두워져 다발이 한 줄씩 보인다.
색은 게임이 입힌다 (머리 색 10가지): 정점 색 R = 그늘(1 밝음 ~ 0 어두움), G = 윤기 띠(천사링) 세기, B·A = 1.
리본·머리끈은 색이 따로라 게임(절차)에서 그린다.

좌표: 게임 머리 좌표 (Y 위, 얼굴이 -Z, 머리 가운데 HEAD_CENTER). 내보낼 때 X 축 +90° → glTF 가 다시 Y 위로.
사용: python3 tools/blender/build_hair.py [스타일 …]      (pip install bpy — Blender 5.0 파이썬 모듈)
"""
import math
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
HAIR_RADII = Vector((0.44, 0.39, 0.36))

# 삼각형 예산 (캐릭터 예산 8,000 / 12,000 / 24,000 안에서 머리카락 몫, 캐릭터 촘촘함 0 / 1 / 2 단계).
BUDGETS = {'_low': 2600, '_mid': 3600, '': 8000}


def rad(d):
    return math.radians(d)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def surface(a, e, rf=1.0):
    """머리카락 겉면 위의 점. a = 둘레(0 = 얼굴 앞, +90 = 캐릭터 왼쪽(+X), 180 = 뒤), e = 높이(+90 정수리).
    적도 아래로는 공처럼 안으로 말려 들지 않고 곧게 내려온다 (옆머리·뒷머리가 늘어진다)."""
    sa, ca = math.sin(rad(a)), math.cos(rad(a))
    if e >= 0.0:
        ce, se = math.cos(rad(e)), math.sin(rad(e))
        p = Vector((HAIR_RADII.x * ce * sa, HAIR_RADII.y * se, -HAIR_RADII.z * ce * ca))
    else:
        t = -e / 90.0
        # 아래로 갈수록 턱 쪽 볼살(jowl)을 덮게 살짝 넓어졌다가, 끝에서 안으로 아주 조금 모인다.
        widen = 1.0 + 0.06 * math.sin(min(t, 1.0) * math.pi)
        p = Vector((HAIR_RADII.x * sa * widen, -HAIR_RADII.y * 1.25 * t, -HAIR_RADII.z * ca * widen))
    return HAIR_CENTER + p * rf


def grid(bm, rows, cols, point, closed=False):
    """(행, 열) → 점 함수로 사각 격자 면을 만든다. closed 면 열 끝과 처음을 잇는다."""
    verts = [[bm.verts.new(point(i / rows, j / (cols if closed else cols))) for j in range(cols + (0 if closed else 1))] for i in range(rows + 1)]
    width = cols + (0 if closed else 1)
    for i in range(rows):
        for j in range(cols):
            j2 = (j + 1) % width if closed else j + 1
            bm.faces.new((verts[i][j], verts[i][j2], verts[i + 1][j2], verts[i + 1][j]))
    return verts


def shell(bm, rim, rows=12, cols=48, rf=1.0, bump=None, notch=None):
    """정수리에서 가장자리(rim(a) 높이)까지 덮는 껍질. bump(a, v) → 반지름 배율 (덩어리 사이 골),
    notch(a) → 가장자리를 올려 깎는 정도(도) — 골 자리에서 끝이 살짝 들어가 다발 끝이 둥글게 나뉜다."""
    def point(u, s):
        a = s * 360.0 - 180.0
        r = rim(a) + (notch(a) if notch else 0.0)
        e = 90.0 - (90.0 - r) * u
        k = rf * (bump(a, u) if bump else 1.0)
        return surface(a, e, k)
    # 정수리 한 점에 몰리지 않게 첫 줄을 아주 조금 내려서 시작하고, 꼭대기는 부채꼴로 막는다.
    verts = grid(bm, rows, cols, lambda u, s: point(0.04 + 0.96 * u, s), closed=True)
    top = bm.verts.new(surface(0.0, 90.0, rf))
    for j in range(cols):
        bm.faces.new((top, verts[0][(j + 1) % cols], verts[0][j]))


def panel(bm, spine, width, rows=10, cols=6, rf=1.03, tip=0.35, bow=0.0):
    """다발 하나: spine = [(a, e), …] 위에서 아래로, width(v) = 둘레 방향 폭(도).
    끝(tip 비율 구간)은 폭이 둥글게 줄어 동그랗게 모인다. bow = 가운데가 볼록한 정도."""
    def at(v):
        f = v * (len(spine) - 1)
        i = min(int(f), len(spine) - 2)
        t = f - i
        a = spine[i][0] + (spine[i + 1][0] - spine[i][0]) * t
        e = spine[i][1] + (spine[i + 1][1] - spine[i][1]) * t
        return a, e

    def point(v, s):
        a, e = at(v)
        a2, e2 = at(min(1.0, v + 0.02))
        a1, e1 = at(max(0.0, v - 0.02))
        da, de = a2 - a1, e2 - e1
        n = math.hypot(da, de) or 1.0
        # 다발 진행 방향에 수직인 방향으로 폭만큼 벌린다 ((a, e) 평면에서).
        pa, pe = -de / n, da / n
        w = width(v)
        if v > 1.0 - tip:
            k = (v - (1.0 - tip)) / tip
            w *= math.sqrt(max(0.0, 1.0 - k * k))
        off = (s - 0.5) * w
        lift = 1.0 + bow * (1.0 - (2.0 * s - 1.0) ** 2) * (1.0 - 0.5 * v)
        return surface(a + pa * off, e + pe * off, rf * lift)
    grid(bm, rows, cols, lambda u, s: point(u, s))


def tube(bm, path, radius, rings=12, sides=10):
    """꼬리처럼 머리에서 떨어져 늘어진 다발: path(u) → 점, radius(u) → 반지름. 끝은 둥글게 모은다."""
    rows = []
    for i in range(rings + 1):
        u = i / rings
        p = path(u)
        q = path(min(1.0, u + 0.01)) - path(max(0.0, u - 0.01))
        t = q.normalized()
        side = t.cross(Vector((0.0, 0.0, 1.0)))
        if side.length < 1e-4:
            side = t.cross(Vector((1.0, 0.0, 0.0)))
        side.normalize()
        up = side.cross(t).normalized()
        r = radius(u)
        rows.append([bm.verts.new(p + (side * math.cos(k / sides * math.tau) + up * math.sin(k / sides * math.tau)) * r) for k in range(sides)])
    for i in range(rings):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rows[i][k], rows[i][k2], rows[i + 1][k2], rows[i + 1][k]))
    for ring, end in ((rows[0], path(0.0)), (rows[-1], path(1.0))):
        c = bm.verts.new(end)
        for k in range(sides):
            f = (ring[k], ring[(k + 1) % sides], c) if ring is rows[-1] else (c, ring[(k + 1) % sides], ring[k])
            bm.faces.new(f)


# ---- 다발 ----
#
# 한 다발 = 머리카락 100올쯤이 모인 가늘고 납작한 묶음 (너비 4~7cm, 두께 1.5~2.5cm). 단면은 렌즈 모양(가운데 두껍고
# 가장자리 얇음), 뿌리는 껍질 속에 묻히고, 끝으로 갈수록 가늘어져 한 점으로 모인다(갈라지지 않는다).
# 스타일마다 다발 수십 개를 두 겹으로 엇갈려 얹어, 다발 사이로 그늘이 지며 결이 보인다.
# 화질(q = 0 절약 · 1 중간 · 2 고화질)에 따라 다발 수는 같고 마디·둘레 점 수만 줄인다 (가는 다발을 줄이기(decimate)로
# 깎으면 모양이 깨진다).

SEG = {0: (4, 3), 1: (6, 3), 2: (8, 4)}  # 화질별 (마디 수, 단면 점 수)


def dir_of(a, e):
    ce = math.cos(rad(e))
    return Vector((ce * math.sin(rad(a)), math.sin(rad(e)), -ce * math.cos(rad(a))))


def ae_of(d):
    d = d.normalized()
    return math.degrees(math.atan2(d.x, -d.z)), math.degrees(math.asin(max(-1.0, min(1.0, d.y))))


def slerp(d0, d1, t):
    d0, d1 = d0.normalized(), d1.normalized()
    dot = max(-1.0, min(1.0, d0.dot(d1)))
    om = math.acos(dot)
    if om < 1e-4:
        return d0
    return (d0 * math.sin((1 - t) * om) + d1 * math.sin(t * om)) / math.sin(om)


def strand(bm, path, outward, width, thick, q, taper=0.5, flat=0.35, end=0.35):
    """path(v) → 점 (v: 뿌리 0 ~ 끝 1), outward(v) → 바깥 방향. 렌즈 단면 튜브, 뿌리는 막는다.
    end = 끝 너비 비율: 끝은 바늘처럼 뾰족하지 않고 이만큼 남긴 채 둥글게 막는다 (자른 단발은 크게, 묶은 꼬리 끝은 작게)."""
    rows, sides = SEG[q]
    rings = []
    for i in range(rows + 1):
        v = i / rows
        p = path(v)
        t = (path(min(1.0, v + 0.02)) - path(max(0.0, v - 0.02))).normalized()
        n = outward(v)
        side = t.cross(n)
        if side.length < 1e-5:
            side = t.orthogonal()
        side.normalize()
        up = side.cross(t).normalized()
        if up.dot(n) < 0.0:
            up = -up
        k = (0.8 + 0.2 * smoothstep(0.0, 0.15, v)) * (1.0 - (1.0 - end) * smoothstep(taper, 1.0, v))
        w, th = width * k, thick * k
        ring = []
        for j in range(sides):
            ang = math.tau * j / sides + (math.pi / 2.0 if sides == 3 else 0.0)
            c, sn = math.cos(ang), math.sin(ang)
            # 위쪽(바깥)은 볼록, 아래쪽(머리 쪽)은 납작.
            lift = th * (0.5 * sn if sn > 0 else flat * sn)
            ring.append(bm.verts.new(p + side * (0.5 * w * c) + up * lift))
        rings.append(ring)
    for i in range(rows):
        a, b = rings[i], rings[i + 1]
        for j in range(sides):
            j2 = (j + 1) % sides
            bm.faces.new((a[j], a[j2], b[j2], b[j]))
    t_end = (path(1.0) - path(0.97)).normalized()
    tip = bm.verts.new(path(1.0) + t_end * (thick * end * 0.6))
    for j in range(sides):
        bm.faces.new((rings[-1][j], rings[-1][(j + 1) % sides], tip))
    root = bm.verts.new(path(0.0) - outward(0.0) * thick)
    for j in range(sides):
        bm.faces.new((rings[0][(j + 1) % sides], rings[0][j], root))


def lock(bm, q, root, tip, width=0.06, thick=0.02, rf=1.0, bend=0.0, taper=0.5, mid=None, end=0.35):
    """머리 겉면을 따라 흐르는 다발: root·tip = (a, e). mid = 거쳐 가는 (a, e) (뒤로 빗어 넘긴 머리처럼 휘게).
    bend = 옆으로 휘는 정도(도). 뿌리는 껍질 속에 조금 묻힌다."""
    d0, d1 = dir_of(*root), dir_of(*tip)
    dm = dir_of(*mid) if mid else None

    def ae(v):
        if dm is not None:
            d = slerp(d0, dm, v * 2.0) if v < 0.5 else slerp(dm, d1, v * 2.0 - 1.0)
        else:
            d = slerp(d0, d1, v)
        a, e = ae_of(d)
        if e < -5.0 or tip[1] < -5.0:
            # 적도 아래(늘어진 머리)는 높이를 직선으로 이어 surface 의 늘어진 모양을 따른다.
            e = root[1] + (tip[1] - root[1]) * v if (mid is None) else e
        return a + bend * math.sin(math.pi * v), e

    def path(v):
        a, e = ae(v)
        return surface(a, e, rf * (0.985 + 0.015 * smoothstep(0.0, 0.2, v)))

    def outward(v):
        a, e = ae(v)
        p = surface(a, e, 1.0)
        n = p - HAIR_CENTER
        if e < 0.0:
            n.y *= 0.3
        return n.normalized()
    strand(bm, path, outward, width, thick, q, taper, end=end)


def under_shell(bm, rim, rf=0.975, rows=8, cols=28):
    """다발 사이로 머리가 비쳐 보이지 않게 까는 얇은 속껍질 (그늘이 지는 머리색). 따로 만들어 바깥을 보게 맞추고
    두께를 줘 닫는다 (한 겹이면 면이 뒤집혀 앞에서 안 보일 수 있다)."""
    sb = bmesh.new()
    shell(sb, rim, rows=rows, cols=cols, rf=rf)
    bmesh.ops.recalc_face_normals(sb, faces=sb.faces)
    sb.faces.ensure_lookup_table()
    f = sb.faces[len(sb.faces) // 2]
    if f.normal.dot(f.calc_center_median() - HAIR_CENTER) < 0.0:
        bmesh.ops.reverse_faces(sb, faces=sb.faces)
    bmesh.ops.solidify(sb, geom=sb.faces[:], thickness=0.012)
    me = bpy.data.meshes.new('shell')
    sb.to_mesh(me)
    sb.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


# ---- 스타일 ----

def style_bob(bm, q, rnd):
    """청록 히메컷(단발): 일자 앞머리, 턱선에서 자른 옆·뒷머리 (리본은 게임이 단다)."""
    def rim(a):
        return 50.0 - (50.0 + 50.0) * smoothstep(52.0, 70.0, abs(a))
    under_shell(bm, rim)
    # 옆·뒷머리: 정수리에서 턱선까지 두 겹 (바깥 겹은 반 칸 어긋나게).
    for layer, (step, off, rf, w) in enumerate(((9.0, 0.0, 1.0, 0.105), (9.0, 4.5, 1.025, 0.095))):
        a = 58.0 + off
        while a <= 302.0:
            aa = a if a <= 180.0 else a - 360.0
            tip_e = -55.0 + rnd.uniform(-3.5, 3.5) + (2.0 if layer else 0.0)
            lock(bm, q, (aa * 0.9, 76.0 + rnd.uniform(-4, 4)), (aa + rnd.uniform(-2.5, 2.5), tip_e),
                 width=w, thick=0.014, rf=rf, bend=rnd.uniform(-2.5, 2.5), taper=0.72, end=0.5)
            a += step
    # 얼굴 옆 히메 다발 (볼 옆으로 곧게).
    for side in (-1.0, 1.0):
        for k, a in enumerate((60.0, 67.0, 74.0)):
            lock(bm, q, (side * (a - 8.0), 60.0), (side * a, -48.0 + k * 2.0 + rnd.uniform(-2, 2)),
                 width=0.075, thick=0.014, rf=1.045, bend=side * 2.0, taper=0.72, end=0.5)
    # 일자 앞머리: 정수리 앞에서 이마로 모여 내려와 눈썹 위에서 끝난다. 두 겹.
    for layer, (step, off, rf) in enumerate(((8.0, 0.0, 1.04), (8.0, 4.0, 1.055))):
        a = -60.0 + off
        while a <= 60.0:
            lock(bm, q, (a * 0.35, 80.0 + rnd.uniform(-3, 3)), (a + rnd.uniform(-1.5, 1.5), 12.0 + rnd.uniform(-2.0, 2.5) + layer * 1.5),
                 width=0.09 if layer == 0 else 0.08, thick=0.014, rf=rf, bend=rnd.uniform(-2, 2), taper=0.8, end=0.65)
            a += step


def style_ponytail(bm, q, rnd):
    """검정 포니테일: 머리 전체를 뒤통수 위(묶은 자리)로 빗어 넘기고, 옆으로 넘긴 앞머리, 휘어 내린 꼬리."""
    def rim(a):
        f = abs(a)
        front = 22.0 - 4.0 * math.cos(rad(a) * 2.0)
        e = front + (-12.0 - front) * smoothstep(48.0, 78.0, f)
        return e + (-36.0 - e) * smoothstep(105.0, 160.0, f)
    under_shell(bm, rim)
    tie = (180.0, 44.0)
    # 이마선·옆·목덜미에서 묶은 자리로 빗어 넘긴 다발 (위쪽은 정수리를 넘어서 간다).
    a = -172.0
    while a <= 172.0:
        e0 = rim(a) + 3.0
        f = abs(a)
        if f < 100.0:
            mid = (a * 0.55, 72.0 - 0.15 * f)  # 정수리 쪽으로 올라갔다가 뒤로
        else:
            mid = None
        tip = (180.0 + rnd.uniform(-8.0, 8.0) - (360.0 if a < 0 and f > 150 else 0.0), tie[1] + rnd.uniform(-4.0, 3.0))
        lock(bm, q, (a, e0), tip, width=0.095, thick=0.015, rf=1.0 + 0.02 * (int(a / 8.0) % 2), mid=mid,
             bend=rnd.uniform(-2.0, 2.0), taper=0.88, end=0.5)
        a += 8.0
    # 정수리 위 겹: 앞쪽에서 뒤로.
    for a in (-48.0, -32.0, -16.0, 0.0, 16.0, 32.0, 48.0):
        lock(bm, q, (a, 50.0), (180.0 + a * 0.12, tie[1] + 2.0), width=0.09, thick=0.015, rf=1.035, mid=(a * 0.4, 86.0), taper=0.9, end=0.5)
    # 옆으로 넘긴 앞머리: 오른쪽 가르마에서 왼쪽 눈썹 위로 쓸어 넘긴 다발 여러 개 (부채꼴).
    for k in range(8):
        t = k / 7.0
        lock(bm, q, (34.0 + 6.0 * t, 74.0 - 4.0 * t), (-64.0 + 26.0 * t, 4.0 + 14.0 * t), width=0.085, thick=0.016,
             rf=1.05 + 0.008 * (k % 2), mid=(-8.0 + 18.0 * t, 46.0 + 4.0 * t), taper=0.65, end=0.4)
    # 귀 앞 짧은 옆머리.
    for side in (-1.0, 1.0):
        for k in range(3):
            lock(bm, q, (side * (66.0 + k * 5.0), 34.0), (side * (72.0 + k * 5.0), -16.0 + rnd.uniform(-3, 3)),
                 width=0.045, thick=0.018, rf=1.03, taper=0.6, end=0.35)
    # 꼬리: 묶은 자리에서 휘어 내려오는 다발 10개가 꼬리 길을 따라 비틀려 감기고, 끝에서 하나로 모인다.
    def tail(u):
        return HAIR_CENTER + Vector((0.28 * math.sin(u * math.pi * 0.6), 0.28 + 0.16 * u - 0.72 * u * u, 0.3 + 0.08 * math.sin(u * math.pi)))

    def tail_radius(u):
        return 0.075 * (0.75 + 0.25 * min(u * 4.0, 1.0)) * (1.0 - 0.45 * smoothstep(0.35, 1.0, u))

    def frame(u):
        t = (tail(min(1.0, u + 0.01)) - tail(max(0.0, u - 0.01))).normalized()
        s1 = t.cross(Vector((0.0, 0.0, 1.0)))
        if s1.length < 1e-4:
            s1 = t.cross(Vector((1.0, 0.0, 0.0)))
        s1.normalize()
        return t, s1, s1.cross(t).normalized()
    # 속 심 (다발 사이로 빈틈이 안 보이게).
    strand(bm, tail, lambda v: frame(v)[2], 0.1, 0.1, q, taper=0.55, flat=0.5)
    for k in range(10):
        ang0 = math.tau * k / 10.0

        def path(v, ang0=ang0):
            _, s1, s2 = frame(v)
            ang = ang0 + 0.9 * v
            r = tail_radius(v) * (1.0 - 0.85 * smoothstep(0.7, 1.0, v))
            return tail(v) + (s1 * math.cos(ang) + s2 * math.sin(ang)) * r

        def out(v, ang0=ang0):
            _, s1, s2 = frame(v)
            ang = ang0 + 0.9 * v
            return (s1 * math.cos(ang) + s2 * math.sin(ang)).normalized()
        strand(bm, path, out, 0.06, 0.024, q, taper=0.72, end=0.15)


STYLES = {'bob': style_bob, 'ponytail': style_ponytail}


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


def apply(ob, mod):
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)


QUALITY = {'_low': 0, '_mid': 1, '': 2}


def build(style, suffix):
    budget = BUDGETS[suffix]
    q = QUALITY[suffix]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import random
    bm = bmesh.new()
    STYLES[style](bm, q, random.Random(hash(style) & 0xFFFF))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(style)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(style, me)
    bpy.context.scene.collection.objects.link(ob)
    tris = tri_count(ob)
    if tris > budget:
        dec = ob.modifiers.new('fit', 'DECIMATE')
        dec.ratio = budget / tris * 0.97
        apply(ob, dec)
    for p in ob.data.polygons:
        p.use_smooth = True
    # 게임 좌표(Y 위) → Blender(Z 위).
    rot = Matrix.Rotation(math.pi / 2, 4, 'X')
    ob.data.transform(rot)
    head = head_proxy()
    head.data.transform(rot)
    bake_shade(ob, head)
    bpy.data.objects.remove(head)
    OUT.mkdir(parents=True, exist_ok=True)
    name = style + suffix
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'{name}.glb'), export_format='GLB', use_selection=True,
                              export_vertex_color='ACTIVE', export_materials='NONE', export_normals=True, export_apply=True)
    return tri_count(ob)


def bake_shade(ob, head):
    """정점 색 R = 그늘(AO, 두상과 다른 다발에 가린 곳), G = 정수리 둘레 윤기 띠."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 64
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.world = scene.world or bpy.data.worlds.new('World')
    scene.world.light_settings.distance = 0.09
    ob.data.materials.append(bpy.data.materials.new('bake'))
    ao = ob.data.color_attributes.new('AO', 'FLOAT_COLOR', 'CORNER')
    ob.data.color_attributes.active_color = ao
    for o in scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='AO')
    me = ob.data
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    center = Vector((HAIR_CENTER.x, -HAIR_CENTER.z, HAIR_CENTER.y))  # Blender 좌표
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            d = (v.co - center).normalized()
            n = v.normal
            facing = max(0.0, n.dot(d))
            # 윤기 띠: 정수리 아래 둘레, 바깥을 보는 면에만, 결을 따라 끊어진다.
            around = math.atan2(d.x, d.y)
            band = smoothstep(0.38, 0.52, d.z) * (1.0 - smoothstep(0.66, 0.8, d.z))
            streak = 0.6 + 0.4 * math.sin(around * 7.0 + d.z * 4.0)
            shade = ao.data[li].color[0]
            col.data[li].color = (shade, band * streak * facing, 1.0, 1.0)
    vals = [ao.data[i].color[0] for i in range(len(ao.data))]
    print(f'[hair]   AO {min(vals):.2f}~{max(vals):.2f} (평균 {sum(vals) / max(len(vals), 1):.2f})')
    me.color_attributes.remove(ao)
    me.color_attributes.active_color = col
    me.materials.clear()


def main():
    styles = sys.argv[1:] or list(STYLES)
    for s in styles:
        counts = {suffix: build(s, suffix) for suffix in BUDGETS}
        print(f"[hair] {s:10s} 고화질 {counts['']:5d} · 중간 {counts['_mid']:5d} · 절약 {counts['_low']:5d} tri")


if __name__ == '__main__':
    main()
