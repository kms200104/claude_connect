#!/usr/bin/env python3
"""캐릭터 머리카락 모형을 Blender(bpy)로 만든다 → assets/models/hair/<스타일>.glb (+ _mid · _low).

참고: art_source/reference/character_sheet.png (모동숲 같은 찰흙 단발 — 앞 · 옆 · 뒤).
  - 머리카락은 조각조각 붙인 다발이 아니라 **매끈한 찰흙 덩어리 하나**: 머리보다 확실히 크고 둥근 종 모양.
  - 겉면에 빗으로 쓸어 놓은 듯한 **가늘고 얕은 결**(골)이 정수리에서 아래로 흐르고, 정수리 쪽은 옅어진다.
  - 아래 끝은 **두툼하고 둥글게 안으로 말려** 끝나고, 일자 앞머리도 아래가 둥글게 말려 이마 쪽으로 들어간다.
얼굴 쪽은 열어 두고(앞머리가 덮는다), 귀 앞 옆머리가 볼을 감싼다.
색은 게임이 입힌다 (머리 색 10가지): 정점 색 R = 그늘(AO), G = 정수리 둘레 윤기 띠, B·A = 1.
리본·머리끈은 색이 따로라 게임(절차)에서 그린다.

좌표: 게임 머리 좌표 (Y 위, 얼굴이 -Z, 머리 가운데 HEAD_CENTER = (0, 0.4, 0), 머리 꼭대기 y 0.77 · 턱 y 0.03).
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

# 화질(촘촘함 0 절약 · 1 중간 · 2 고화질)별 격자: (둘레 칸, 세로 마디, 결 개수). 결은 칸 3개에 하나.
GRID = {0: (60, 10, 18), 1: (90, 14, 28), 2: (132, 20, 40)}
QUALITY = {'_low': 0, '_mid': 1, '': 2}


def rad(d):
    return math.radians(d)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


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
    return out


def combed(a, n, seed, depth):
    """빗으로 쓸어 놓은 결: 둘레 a(도)에서 좁고 얕은 골 (0 ~ -depth). 골마다 깊이·자리가 조금씩 달라 자연스럽다."""
    rnd = random.Random(seed)
    jit = [rnd.uniform(-0.25, 0.25) for _ in range(n)]
    amp = [rnd.uniform(0.55, 1.0) for _ in range(n)]
    x = (a / 360.0 % 1.0) * n
    i = int(x) % n
    f = x - int(x) + jit[i]
    g = max(0.0, 1.0 - abs(f - 0.5) * 2.0 / 0.55)  # 칸 가운데 좁은 골
    return -depth * amp[i] * g * g


def outward(bm):
    """방금 만든 껍질(bm 전체)이 바깥을 보게 맞춘다."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    top = max(bm.faces, key=lambda f: f.calc_center_median().y)
    if top.normal.y < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)


def lathe(bm, cols, column):
    """둘레 cols 칸, column(a) → 그 둘레의 (점, 결 세기) 목록(위 → 아래, 길이 같음). 격자를 잇고 꼭대기를 막는다.
    결 세기는 정점 값 'groove' 로 남겨 굽기에서 결을 조금 어둡게 칠한다 (툰 조명만으로는 얕은 골이 잘 안 보인다)."""
    rings = [column(j / cols * 360.0 - 180.0) for j in range(cols)]
    rows = len(rings[0])
    layer = bm.verts.layers.float.get('groove') or bm.verts.layers.float.new('groove')
    verts = []
    for i in range(rows):
        row = []
        for j in range(cols):
            p, g = rings[j][i]
            v = bm.verts.new(p)
            v[layer] = g
            row.append(v)
        verts.append(row)
    for i in range(rows - 1):
        for j in range(cols):
            j2 = (j + 1) % cols
            bm.faces.new((verts[i][j], verts[i][j2], verts[i + 1][j2], verts[i + 1][j]))
    top = bm.verts.new(sum((v.co for v in verts[0]), Vector()) / cols + Vector((0.0, 0.004, 0.0)))
    for j in range(cols):
        bm.faces.new((top, verts[0][(j + 1) % cols], verts[0][j]))


def lining(bm, cols, column):
    """lathe 와 같은 껍질을 안쪽을 보게 깐다 (따로 만들어 방향을 맞춘 뒤 붙인다)."""
    sb = bmesh.new()
    lathe(sb, cols, column)
    bmesh.ops.recalc_face_normals(sb, faces=sb.faces)
    sb.faces.ensure_lookup_table()
    top = max(sb.faces, key=lambda f: f.calc_center_median().y)
    if top.normal.y > 0.0:
        bmesh.ops.reverse_faces(sb, faces=sb.faces)
    me = bpy.data.meshes.new('lining')
    sb.to_mesh(me)
    sb.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def sheet(bm, cols, column):
    """열린 판 (앞머리처럼 양 끝이 이어지지 않는 것): column(s) → 점 목록, s 0 ~ 1."""
    rings = [column(j / (cols - 1)) for j in range(cols)]
    rows = len(rings[0])
    verts = [[bm.verts.new(rings[j][i]) for j in range(cols)] for i in range(rows)]
    for i in range(rows - 1):
        for j in range(cols - 1):
            bm.faces.new((verts[i][j], verts[i][j + 1], verts[i + 1][j + 1], verts[i + 1][j]))


# ---- 스타일 ----

def style_bob(bm, q):
    """단발 (참고 그림 그대로): 머리보다 넓은 종 모양, 턱선에서 안으로 둥글게 말린 끝.
    일자 앞머리도 같은 덩어리에서 이어져 내려와(따로 붙인 챙이 아니다) 눈썹 위에서 둥글게 말린다."""
    cols, rows, grooves = GRID[q]
    # 옆·뒤 윤곽 (r = 머리 축에서 바깥으로, y = 높이). 정수리 → 볼록하게 부풀어 → 턱선 끝.
    profile = [(0.0, 0.85), (0.17, 0.84), (0.31, 0.795), (0.41, 0.715), (0.475, 0.605), (0.51, 0.48),
               (0.525, 0.35), (0.52, 0.235), (0.5, 0.155)]
    # 끝에서 안으로 둥글게 말려 들어가 머리 속으로 숨는다 (끝 점 기준 (안쪽, 위)).
    curl = [(0.03, -0.03), (0.07, -0.034), (0.1, -0.014), (0.115, 0.025), (0.12, 0.08), (0.12, 0.17), (0.115, 0.27)]

    def column(a):
        f = abs(a)
        front = 1.0 - smoothstep(48.0, 62.0, f)  # 1 = 앞머리 칸
        # 앞머리는 눈썹 위(물결 조금)에서, 귀 앞부터는 턱선까지.
        brow = 0.515 + 0.006 * math.sin(rad(a) * 9.0) + 0.012 * smoothstep(25.0, 48.0, f)
        y_end = lerp(0.0, brow, front)
        body = resample(cut(profile, y_end), rows)
        end = body[-1]
        k_curl = lerp(1.0, 0.55, front)  # 앞머리 끝은 조금 작게 말린다
        pts = body + [(end[0] - c[0] * k_curl, end[1] + c[1] * k_curl) for c in curl]
        sa, ca = math.sin(rad(a)), math.cos(rad(a))
        # 앞뒤로 납작 (얼굴 쪽은 이마에 더 붙게), 뒤는 머리 뒤로 살짝 나온다.
        sz = lerp(0.78, 0.94, smoothstep(30.0, 160.0, f))
        # 앞머리 끝과 옆머리 사이(관자놀이·볼): 옆머리 앞 가장자리를 볼 쪽으로 당겨 붙인다 — 머리보다 넓은 머리카락이
        # 얼굴 옆에서 떠 있으면 그 틈으로 뒤가 비쳐 보인다 (참고 그림도 옆머리가 볼을 감싼다).
        cheek = smoothstep(46.0, 56.0, f) * (1.0 - smoothstep(62.0, 82.0, f))
        out = []
        for k, (r, y) in enumerate(pts):
            t = k / (rows - 1)
            # 결: 정수리 아래부터 생겨 끝 쪽에서 가장 뚜렷, 말린 끝 안쪽에는 없다.
            fade = smoothstep(0.08, 0.4, t) * (1.0 - smoothstep(0.93, 1.0, t)) if k < rows else 0.0
            # 아주 느린 물결 (머리 다발이 조금씩 부풀었다 들어갔다).
            swell = 1.0 + 0.012 * math.sin(rad(a) * 5.0 + 0.7) * smoothstep(0.3, 0.9, t)
            swell *= 1.0 - 0.2 * cheek * smoothstep(0.66, 0.52, y)
            g = combed(a, grooves, 7, 1.0) * fade
            rr = r * swell + 0.014 * g
            out.append((Vector((rr * sa, y, -rr * ca * sz + 0.035)), -g))
        return out
    lathe(bm, cols, column)
    outward(bm)


STYLES = {'bob': style_bob}


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


def build(style, suffix):
    q = QUALITY[suffix]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    STYLES[style](bm, q)
    # 면 방향은 스타일이 만들 때 맞춘다 (겉면은 바깥, 안감은 안쪽).
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
    bake_shade(ob, head)
    bpy.data.objects.remove(head)
    OUT.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'{style}{suffix}.glb'), export_format='GLB', use_selection=True,
                              export_vertex_color='ACTIVE', export_materials='NONE', export_normals=True, export_apply=True)
    return tri_count(ob)


def bake_shade(ob, head):
    """정점 색 R = 그늘(AO: 결 속 · 앞머리 아래 · 머리에 닿는 안쪽), G = 정수리 둘레 윤기 띠."""
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
            band = smoothstep(0.42, 0.56, d.z) * (1.0 - smoothstep(0.7, 0.84, d.z))
            # AO 는 너무 검지 않게 (찰흙처럼 부드러운 그늘).
            shade = 0.35 + 0.65 * ao.data[li].color[0]
            # 결(빗질 골) 속은 조금 더 어둡게 — 참고 그림의 가는 결이 보이게.
            if groove is not None:
                shade *= 1.0 - 0.38 * groove.data[v.index].value
            col.data[li].color = (shade, band * facing * 0.8, 1.0, 1.0)
    vals = [ao.data[i].color[0] for i in range(len(ao.data))]
    print(f'[hair]   AO {min(vals):.2f}~{max(vals):.2f} (평균 {sum(vals) / max(len(vals), 1):.2f})')
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
