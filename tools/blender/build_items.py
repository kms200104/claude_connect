#!/usr/bin/env python3
"""가구 모형을 Blender(bpy)로 다시 만든다 → assets/models/items/<아이템>.glb (v0.11).

게임 안 절차 모형(game/props/part_mesh.gd)과 같은 도형 목록(data/items/*.json 의 model)을 쓰되, Blender 에서
  - 모든 모서리를 깎고(bevel) 둥근 부분은 면을 더 잘게 나눠 매끈하게,
  - 각도로 매끄러움을 나눠(50° 넘는 모서리만 각지게) 찰흙 같은 부드러운 면,
  - Cycles 로 주변광 차폐(AO)를 정점 색에 구워 넣어 틈·바닥·겹친 곳이 자연스럽게 어두워지게,
  - 집 기본 가구(TV·에어컨·선풍기·침대·냉장고·옷장·세탁기·소파)는 손잡이·통풍구·이불 주름 같은 디테일을 더하고,
  - 크기별 삼각형 예산(작은 것 300 · 중간 800 · 큰 것 1,500, CLAUDE.md)을 넘으면 줄인다.
게임은 이 파일이 있으면 그것을, 없으면 절차 모형을 쓴다 (PartMesh.get_mesh).

사용: python3 tools/blender/build_items.py [아이템 id …]      (pip install bpy — Blender 5.0 파이썬 모듈)
"""
import glob
import json
import math
import random
import sys
from pathlib import Path

import bpy  # bmesh · mathutils 는 bpy 를 먼저 불러야 보인다
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/items'
BUDGET = {'small': 300, 'medium': 800, 'large': 1500}

# 집 기본 가구에 더하는 디테일 (같은 도형 언어, 게임 좌표: Y 위, +Z 앞).
EXTRA = {
    'tv': [
        {'s': 'rbox', 'size': [1.5, 0.88, 0.035], 'at': [0, 0.99, -0.1], 'c': '#2A2E34', 'r': 0.2},  # 뒤판
        {'s': 'box', 'size': [1.2, 0.03, 0.02], 'at': [0, 0.36, 0.2], 'c': '#3A3F46'},  # 사운드바
        {'s': 'rbox', 'size': [0.36, 0.1, 0.3], 'at': [-0.55, 0.06, 0.0], 'c': '#D8CFC2', 'r': 0.4},  # 서랍 손잡이 홈
        {'s': 'rbox', 'size': [0.36, 0.1, 0.3], 'at': [0.55, 0.06, 0.0], 'c': '#D8CFC2', 'r': 0.4},
        {'s': 'cap', 'size': [0.012], 'at': [-0.25, 0.22, 0.215], 'to': [0.25, 0.22, 0.215], 'c': '#B8AC9C'},
    ],
    'air_conditioner': [
        {'s': 'box', 'size': [0.32, 0.012, 0.03], 'at': [0, 0.4, 0.175], 'c': '#C2CCD4'},
        {'s': 'box', 'size': [0.32, 0.012, 0.03], 'at': [0, 0.34, 0.175], 'c': '#C2CCD4'},
        {'s': 'box', 'size': [0.32, 0.012, 0.03], 'at': [0, 0.28, 0.175], 'c': '#C2CCD4'},
        {'s': 'box', 'size': [0.32, 0.012, 0.03], 'at': [0, 0.22, 0.175], 'c': '#C2CCD4'},
        {'s': 'rbox', 'size': [0.38, 0.08, 0.04], 'at': [0, 1.76, 0.0], 'c': '#D8DEE2', 'r': 0.5},
    ],
    'electric_fan': [
        {'s': 'sphere', 'size': [0.09, 0.02, 0.17], 'at': [0, 1.06, 0.05], 'c': '#9CD0EC', 'rot': [0, 0, 0]},
        {'s': 'sphere', 'size': [0.09, 0.02, 0.17], 'at': [0.07, 0.94, 0.05], 'c': '#9CD0EC', 'rot': [90, 0, 60]},
        {'s': 'sphere', 'size': [0.09, 0.02, 0.17], 'at': [-0.07, 0.94, 0.05], 'c': '#9CD0EC', 'rot': [90, 0, -60]},
        {'s': 'torus', 'size': [0.21, 0.008], 'at': [0, 0.98, 0.01], 'c': '#C4CDD3', 'rot': [90, 0, 0]},
        {'s': 'rod', 'size': [0.006, 0.006], 'at': [0, 1.19, 0.06], 'to': [0, 0.77, 0.06], 'c': '#C4CDD3'},
        {'s': 'rod', 'size': [0.006, 0.006], 'at': [-0.21, 0.98, 0.06], 'to': [0.21, 0.98, 0.06], 'c': '#C4CDD3'},
        {'s': 'cyl', 'size': [0.03, 0.02], 'at': [0.08, 0.06, 0.1], 'c': '#7EC0E4', 'r': 0.008},
    ],
    'bed_double': [
        {'s': 'rbox', 'size': [1.62, 0.07, 0.4], 'at': [0, 0.57, -0.17], 'c': ['#9AB6D8', '#C2D6EE'], 'r': 0.8},  # 접은 이불 끝
        {'s': 'rbox', 'size': [0.5, 0.1, 0.3], 'at': [0.45, 0.6, 0.55], 'c': '#F2E6C8', 'r': 0.8},  # 담요
        {'s': 'rbox', 'size': [1.5, 0.06, 0.06], 'at': [0, 0.9, -1.04], 'c': '#B48C62', 'r': 0.6},
    ],
    'bed_single': [
        {'s': 'rbox', 'size': [1.12, 0.07, 0.4], 'at': [0, 0.57, -0.16], 'c': ['#EEB6A0', '#F8D4C6'], 'r': 0.8},
        {'s': 'rbox', 'size': [1.0, 0.06, 0.06], 'at': [0, 0.86, -1.03], 'c': '#B48C62', 'r': 0.6},
    ],
    'refrigerator': [
        {'s': 'rbox', 'size': [0.9, 0.04, 0.76], 'at': [0, 1.86, 0], 'c': '#C8CED4', 'r': 0.5},
        {'s': 'box', 'size': [0.4, 0.02, 0.01], 'at': [-0.23, 0.6, 0.392], 'c': '#C2C9D0'},
        {'s': 'box', 'size': [0.4, 0.02, 0.01], 'at': [0.23, 0.6, 0.392], 'c': '#C2C9D0'},
        {'s': 'rbox', 'size': [0.9, 0.06, 0.74], 'at': [0, 0.03, 0.01], 'c': '#9CA4AC', 'r': 0.4},
    ],
    'wardrobe': [
        {'s': 'rbox', 'size': [0.5, 1.6, 0.02], 'at': [-0.29, 1.08, 0.302], 'c': '#EADFCD', 'r': 0.2},
        {'s': 'rbox', 'size': [0.5, 1.6, 0.02], 'at': [0.29, 1.08, 0.302], 'c': '#EADFCD', 'r': 0.2},
        {'s': 'rbox', 'size': [1.24, 0.06, 0.62], 'at': [0, 2.02, 0], 'c': '#D8C8B0', 'r': 0.4},
    ],
    'washing_machine': [
        {'s': 'sphere', 'size': [0.16, 0.16, 0.03], 'at': [0, 0.4, 0.315], 'c': '#BFD6EA'},  # 유리
        {'s': 'cyl', 'size': [0.025, 0.015], 'at': [-0.15, 0.76, 0.31], 'c': '#AEB8C0', 'rot': [90, 0, 0], 'r': 0.006},
        {'s': 'rbox', 'size': [0.14, 0.05, 0.01], 'at': [0.15, 0.08, 0.302], 'c': '#C8D0D6', 'r': 0.5},
    ],
    'fabric_sofa': [
        {'s': 'rbox', 'size': [0.6, 0.42, 0.18], 'at': [-0.6, 0.72, -0.2], 'c': ['#8E949C', '#A8AEB6'], 'r': 0.7},  # 등쿠션
        {'s': 'rbox', 'size': [0.6, 0.42, 0.18], 'at': [0.0, 0.72, -0.2], 'c': ['#8E949C', '#A8AEB6'], 'r': 0.7},
        {'s': 'rbox', 'size': [0.6, 0.42, 0.18], 'at': [0.6, 0.72, -0.2], 'c': ['#8E949C', '#A8AEB6'], 'r': 0.7},
        {'s': 'cyl', 'size': [0.03, 0.08], 'at': [-0.85, 0.04, 0.33], 'c': '#6A4A30', 'r': 0.01},  # 다리
        {'s': 'cyl', 'size': [0.03, 0.08], 'at': [0.85, 0.04, 0.33], 'c': '#6A4A30', 'r': 0.01},
        {'s': 'cyl', 'size': [0.03, 0.08], 'at': [-0.85, 0.04, -0.33], 'c': '#6A4A30', 'r': 0.01},
        {'s': 'cyl', 'size': [0.03, 0.08], 'at': [0.85, 0.04, -0.33], 'c': '#6A4A30', 'r': 0.01},
    ],
}


def hex_color(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def paint_of(c):
    if isinstance(c, list) and len(c) >= 2:
        return hex_color(c[0]), hex_color(c[1])
    col = hex_color(c if isinstance(c, str) else '#FFFFFF')
    return col, col


def godot_rotation(rot_deg):
    """Godot Basis.from_euler (YXZ 순서) 와 같은 회전."""
    x, y, z = (math.radians(v) for v in rot_deg)
    return Matrix.Rotation(y, 4, 'Y') @ Matrix.Rotation(x, 4, 'X') @ Matrix.Rotation(z, 4, 'Z')


def bevel_edges(bm, offset, segments, edges=None):
    if offset <= 0.0005:
        return
    bmesh.ops.bevel(bm, geom=list(edges if edges is not None else bm.edges), offset=offset, segments=segments,
                    profile=0.5, affect='EDGES', clamp_overlap=True)


def part_bmesh(part, detail):
    """도형 하나 → bmesh (게임 좌표, 원점 기준, 아직 위치·회전 전). detail: 0(거칠게) ~ 3(곱게)."""
    s = part.get('s', 'box')
    v = part.get('size', [0.5])
    a = float(v[0]) if len(v) > 0 else 0.5
    b = float(v[1]) if len(v) > 1 else a
    c = float(v[2]) if len(v) > 2 else a
    r = float(part.get('r', 0.0))
    bm = bmesh.new()
    seg = [8, 10, 14, 20][detail]
    if s in ('box', 'rbox'):
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(a, b, c), verts=bm.verts)
        small = min(a, b, c)
        if s == 'rbox':
            amount = max(0.15, r if r > 0 else 0.35) * small * 0.5
            bevel_edges(bm, min(amount, small * 0.49), [1, 2, 3, 3][detail])
        else:
            bevel_edges(bm, min(0.012, small * 0.2), 1)
    elif s in ('cyl', 'cone'):
        top = 0.0 if s == 'cone' else a
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=a, radius2=max(top, 0.0005), depth=b)
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, 'X'), verts=bm.verts)
        caps = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-6 and abs(abs(e.verts[0].co.y) - b / 2) < 1e-5]
        amount = r if r > 0 else min(0.008, a * 0.15, b * 0.2)
        bevel_edges(bm, min(amount, b * 0.45, a * 0.45), 2 if r > 0 else 1, caps)
    elif s in ('sphere', 'blob'):
        radii = (a, b, c) if len(v) >= 3 else (a, a, a)
        if s == 'blob':
            bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
            rnd = random.Random(int(part.get('seed', 1)))
            phase = [rnd.uniform(0, 6.28) for _ in range(3)]
            for vert in bm.verts:
                n = vert.co.normalized()
                wob = 1.0 + 0.12 * math.sin(n.x * 4 + phase[0]) * math.sin(n.y * 4 + phase[1]) * math.sin(n.z * 4 + phase[2])
                vert.co = n * wob
        else:
            rings = [5, 6, 8, 12][detail]
            bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
        bmesh.ops.scale(bm, vec=radii, verts=bm.verts)
    elif s == 'torus':
        ring_seg, tube_seg = max(10, seg + 2), 4 if b < 0.03 else (6 if detail < 2 else 8)
        verts = []
        for i in range(ring_seg):
            u = 2 * math.pi * i / ring_seg
            row = []
            for j in range(tube_seg):
                w = 2 * math.pi * j / tube_seg
                rr = a + b * math.cos(w)
                row.append(bm.verts.new((rr * math.cos(u), b * math.sin(w), rr * math.sin(u))))
            verts.append(row)
        for i in range(ring_seg):
            for j in range(tube_seg):
                bm.faces.new((verts[i][j], verts[(i + 1) % ring_seg][j], verts[(i + 1) % ring_seg][(j + 1) % tube_seg], verts[i][(j + 1) % tube_seg]))
    elif s in ('cap', 'rod'):
        start = Vector(part.get('at', [0, 0, 0]))
        end = Vector(part.get('to', [0, 1, 0]))
        length = max((end - start).length, 0.001)
        r0, r1 = (a, a) if s == 'cap' else (a, b)
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=max(8, seg - 4), radius1=r0, radius2=r1, depth=length)
        if s == 'cap':
            caps = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
            bevel_edges(bm, min(a * 0.95, length * 0.45), 3, caps)
        # Z 축 → start→end 방향, 가운데를 원점에.
        direction = (end - start).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(direction).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
        bmesh.ops.translate(bm, vec=(start + end) / 2, verts=bm.verts)
        return bm, True
    else:
        bm.free()
        return None, False
    return bm, False


def build_mesh(item_id, parts, detail):
    """도형 목록 → 정점 색(sRGB 값을 그대로 넣는다: 게임 셰이더가 정점 색을 sRGB 로 읽는다)을 칠한 메시 오브젝트.
    detail: 0~3 (둥근 도형을 나누는 정도)."""
    out = bmesh.new()
    col_layer = out.loops.layers.float_color.new('Col')
    for p in parts:
        bm, placed = part_bmesh(p, detail)
        if bm is None:
            continue
        if not placed:
            m = godot_rotation(p.get('rot', [0, 0, 0])) if 'rot' in p else Matrix.Identity(4)
            bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(p.get('at', [0, 0, 0]))) @ m, verts=bm.verts)
        low, high = paint_of(p.get('c', '#FFFFFF'))
        ys = [vtx.co.y for vtx in bm.verts]
        y0, y1 = min(ys), max(ys)
        tmp = bpy.data.meshes.new('tmp')
        bm.to_mesh(tmp)
        bm.free()
        vmap = {}
        base = len(out.verts)
        for vtx in tmp.vertices:
            vmap[vtx.index] = out.verts.new(vtx.co)
        out.verts.ensure_lookup_table()
        for poly in tmp.polygons:
            try:
                f = out.faces.new([vmap[i] for i in poly.vertices])
            except ValueError:
                continue
            f.smooth = True
            for loop in f.loops:
                t = 0.0 if y1 - y0 < 1e-6 else (loop.vert.co.y - y0) / (y1 - y0)
                cc = [low[k] + (high[k] - low[k]) * t for k in range(3)]
                loop[col_layer] = (*cc, 1.0)
        bpy.data.meshes.remove(tmp)
        del base
    me = bpy.data.meshes.new(item_id)
    out.to_mesh(me)
    out.free()
    ob = bpy.data.objects.new(item_id, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def fit_budget(ob, budget):
    tris = tri_count(ob)
    print(f"[blender]   {ob.name}: {tris} tri → 예산 {budget}")
    if tris <= budget:
        return
    mod = ob.modifiers.new('fit', 'DECIMATE')
    mod.ratio = budget / tris * 0.97
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)


def mark_sharp(ob, angle_deg=50.0):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    limit = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit:
            e.smooth = False
    bm.to_mesh(ob.data)
    bm.free()


def bake_ao(ob):
    """바닥판을 깔고 Cycles 로 AO 를 정점 색 'AO' 에 굽는다."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
    scene.render.bake.target = 'VERTEX_COLORS'
    scene.world = scene.world or bpy.data.worlds.new('World')
    scene.world.light_settings.distance = 0.12
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0, 0, 0))  # 게임 바닥 (Blender 로 돌린 뒤라 Z=0 면)
    ground = bpy.context.active_object
    mat = bpy.data.materials.new('bake')
    ob.data.materials.append(mat)
    ao = ob.data.color_attributes.new('AO', 'FLOAT_COLOR', 'CORNER')
    ob.data.color_attributes.active_color = ao
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='AO')
    bpy.data.objects.remove(ground)
    return ao


def finish_colors(ob):
    """바탕 색 × AO (틈은 어둡게, 너무 검지는 않게: 가장 어두워도 바탕의 65%).
    러그처럼 납작한 것은 겹친 층마다 지저분하게 어두워지니 아주 약하게."""
    strength = 0.1 if ob.dimensions.z < 0.12 else 0.35
    me = ob.data
    col = me.color_attributes['Col']
    ao = me.color_attributes['AO']
    for i in range(len(col.data)):
        c = col.data[i].color
        a = ao.data[i].color[0]
        k = 1.0 - strength + strength * a
        col.data[i].color = (c[0] * k, c[1] * k, c[2] * k, 1.0)
    vals = [ao.data[i].color[0] for i in range(len(ao.data))]
    print(f"[blender]   AO {min(vals):.2f}~{max(vals):.2f} (평균 {sum(vals) / max(len(vals), 1):.2f})")
    me.color_attributes.remove(ao)
    me.color_attributes.active_color = me.color_attributes['Col']
    me.materials.clear()


def size_class(ob):
    """실제 크기(가장 긴 변)로: 0.8m 미만 작은 것 · 1.6m 미만 중간 · 그 이상 큰 것."""
    longest = max(ob.dimensions)
    return 'small' if longest < 0.8 else ('medium' if longest < 1.6 else 'large')


def build(item):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = list(item.get('model', [])) + EXTRA.get(item['id'], [])
    # 예산 안에 드는 가장 고운 나눔을 고른다 (모자라면 마지막에 조금 줄인다 — 많이 줄이면 모양이 뭉개진다).
    for detail in (3, 2, 1, 0):
        ob = build_mesh(item['id'], parts, detail)
        bpy.context.view_layer.update()
        budget = BUDGET[size_class(ob)]
        if tri_count(ob) <= budget * 1.15 or detail == 0:
            break
        bpy.data.objects.remove(ob)
    # 게임 좌표(Y 위) → Blender(Z 위): X 축으로 +90°. glTF 내보내기가 다시 Y 위로 돌린다.
    ob.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
    fit_budget(ob, budget)
    mark_sharp(ob)
    bake_ao(ob)
    finish_colors(ob)
    OUT.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{item['id']}.glb"), export_format='GLB', use_selection=True,
                              export_vertex_color='ACTIVE', export_materials='NONE', export_normals=True, export_apply=True)
    return tri_count(ob), budget


def main():
    wanted = set(sys.argv[1:])
    items = []
    for f in sorted(glob.glob(str(ROOT / 'data/items/*.json'))):
        for it in json.load(open(f)).get('items', []):
            if it.get('kind') == 'furniture' and it.get('model') and (not wanted or it['id'] in wanted):
                items.append(it)
    for it in items:
        tris, budget = build(it)
        print(f"[blender] {it['id']:22s} {tris:5d} / {budget} tri")


if __name__ == '__main__':
    main()
