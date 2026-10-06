#!/usr/bin/env python3
"""캐릭터 머리카락 모형을 Blender(bpy)로 만든다 → assets/models/hair/<스타일>.glb (+ _mid · _low).

절차 머리(CharacterModel._add_hair)는 얇은 리본 가닥과 갈라진 끝 때문에 떡진 것처럼 보였다. 여기서는
  - 머리 둘레의 껍질과 앞머리·옆머리·꼬리를 큼직한 덩어리 몇 개로 빚고(두께를 주고, 모서리는 둥글게),
  - 다발 끝은 둥글게 모으고(갈라지지 않게), 덩어리 사이에만 얕은 골을 두며,
  - Cycles AO 를 머리(두상) 모형을 함께 둔 채 구워 머리에 닿는 안쪽이 자연스럽게 어두워지게 한다.
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
BUDGETS = {'_low': 1800, '_mid': 3300, '': 6500}


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


# ---- 스타일 ----

def lobe(a, count, phase=0.0):
    """둘레를 count 개 덩어리로: 덩어리 가운데 1, 덩어리 사이(골) 0. 골은 좁고 덩어리는 넓다."""
    g = abs(math.cos(rad(a) * count / 2.0 + phase))
    return 1.0 - (1.0 - g) ** 3


def groove(count, depth, start=0.12, phase=0.0):
    """덩어리 사이의 좁고 깊은 골 (정수리에서 시작해 아래로 갈수록 뚜렷)."""
    return lambda a, v: 1.0 + depth * (lobe(a, count, phase) - 1.0) * smoothstep(start, 0.85, v)


def notches(count, height, phase=0.0, where=lambda a: 1.0):
    """골 자리의 가장자리를 height 도 만큼 올린다 → 다발 끝이 둥글게 나뉜다."""
    return lambda a: height * (1.0 - lobe(a, count, phase)) * where(a)


def style_bob(bm):
    """청록 히메컷(단발): 일자 앞머리, 턱선에서 똑 자른 옆·뒷머리 (리본은 게임이 단다)."""
    def rim(a):
        f = abs(a)
        # 앞(얼굴)은 이마 위에서 끝나고(앞머리가 덮는다), 귀 앞부터 턱선까지 뚝 떨어진다.
        return 38.0 - (38.0 + 56.0) * smoothstep(52.0, 70.0, f)
    back = lambda a: smoothstep(60.0, 80.0, abs(a))
    shell(bm, rim, bump=groove(14, 0.07), notch=notches(14, 7.0, where=back))
    # 일자 앞머리: 이마를 덮고 눈썹 위에서 똑 자른다. 아래 가장자리는 아주 얕은 물결 (덩어리 다섯).
    def bangs_point(v, s):
        a = (s - 0.5) * 124.0
        # 다섯 덩어리: 덩어리 사이가 살짝 파이고, 아래 끝은 덩어리마다 둥글게.
        k = lobe(a, 7.2, math.pi / 2.0)
        bottom = 12.0 + 5.0 * (1.0 - k)
        e = 58.0 - (58.0 - bottom) * v
        return surface(a, e, (1.045 + 0.014 * math.sin(v * math.pi)) * (1.0 - 0.03 * (1.0 - k) * v))
    grid(bm, 8, 30, bangs_point)
    # 얼굴 옆 히메 다발: 볼 옆으로 곧게 내려와 턱선에서 자른다.
    for side in (-1.0, 1.0):
        panel(bm, [(66.0 * side, 34.0), (64.0 * side, 0.0), (62.0 * side, -50.0)], lambda v: 16.0 - 2.0 * v, rows=9, cols=4, rf=1.04, tip=0.12, bow=0.03)


def style_ponytail(bm):
    """검정 포니테일: 매끈하게 빗어 넘긴 머리, 옆으로 넘긴 앞머리, 뒤통수 위에서 묶어 휘어 내린 꼬리."""
    def rim(a):
        f = abs(a)
        front = 36.0 - 6.0 * math.cos(rad(a) * 2.0)  # 이마 선이 살짝 둥글게
        side = -12.0  # 귀 위
        back = -36.0  # 목덜미
        e = front + (side - front) * smoothstep(48.0, 78.0, f)
        return e + (back - e) * smoothstep(105.0, 160.0, f)
    # 뒤로 빗어 넘긴 결: 얕은 골이 정수리에서 뒤로 흐른다 (묶은 머리라 다발 끝은 나뉘지 않는다).
    shell(bm, rim, rf=0.99, bump=groove(16, 0.035, start=0.05))
    # 옆으로 넘긴 앞머리: 오른쪽 위 가르마에서 왼쪽 눈썹 위로 크게 쓸어 넘긴 덩어리 하나 + 작은 덩어리 하나.
    panel(bm, [(40.0, 74.0), (14.0, 56.0), (-20.0, 36.0), (-50.0, 20.0), (-64.0, 8.0)], lambda v: 40.0 - 16.0 * v, rows=14, cols=8, rf=1.045, tip=0.3, bow=0.07)
    panel(bm, [(50.0, 66.0), (46.0, 44.0), (42.0, 22.0)], lambda v: 20.0, rows=8, cols=5, rf=1.04, tip=0.45, bow=0.05)
    # 귀 앞으로 내려온 짧은 옆머리.
    for side in (-1.0, 1.0):
        panel(bm, [(74.0 * side, 26.0), (76.0 * side, 4.0), (77.0 * side, -18.0)], lambda v: 11.0, rows=6, cols=3, rf=1.025, tip=0.4, bow=0.02)
    # 꼬리: 게임 절차 꼬리와 같은 길 (CharacterModel._add_hair "ponytail").
    def path(u):
        return HAIR_CENTER + Vector((0.1 + 0.28 * math.sin(u * math.pi * 0.6) - 0.1, 0.28 + 0.16 * u - 0.72 * u * u, 0.3 + 0.08 * math.sin(u * math.pi)))

    def radius(u):
        body = 0.12 * (0.7 + 0.3 * min(u * 4.0, 1.0)) * (1.0 - 0.35 * smoothstep(0.35, 1.0, u))
        tip = math.sqrt(max(0.0, 1.0 - smoothstep(0.82, 1.0, u) ** 2))
        return max(0.004, body * tip)
    tube(bm, path, radius, rings=14, sides=10)


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


def build(style, suffix):
    budget = BUDGETS[suffix]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    STYLES[style](bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(style)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(style, me)
    bpy.context.scene.collection.objects.link(ob)
    # 두께 (안쪽으로) → 둥글게 (가장자리가 동그랗게 말린다).
    sol = ob.modifiers.new('thick', 'SOLIDIFY')
    sol.thickness = 0.03
    sol.offset = -1.0
    sol.use_even_offset = True
    apply(ob, sol)
    sub = ob.modifiers.new('smooth', 'SUBSURF')
    sub.levels = 2 if budget > 3000 else 1
    sub.render_levels = sub.levels
    apply(ob, sub)
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
