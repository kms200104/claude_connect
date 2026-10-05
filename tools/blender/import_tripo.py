#!/usr/bin/env python3
"""Tripo 에서 받은 모형(art_source/tripo/<이름>.glb) → 게임용 assets/models/items/<id>.glb.

게임 모형은 텍스처 없이 정점 색 + 흰 툰 머티리얼 하나로 그린다 (build_items.py 와 같은 방식). 그래서
  - 바탕색 텍스처를 모서리(corner)마다 읽어 정점 색 'Col' 에 굽고 (노멀·러프니스 맵은 버린다),
  - 삼각형 예산(CLAUDE.md)에 맞게 줄이고 (Decimate — 색은 줄이기 전에 구워야 덜 뭉개진다),
  - 게임 좌표(Y 위, +Z 앞)로 돌리고 크기·원점(도구는 쥐는 곳, 건물은 바닥 가운데)을 맞춘다.
게임은 같은 이름의 glb 가 있으면 코드로 빚은 모형 대신 그것을 쓴다 (PartMesh.load_model).

사용: python3 tools/blender/import_tripo.py [id …]      (pip install bpy — Blender 5.0 파이썬 모듈)
"""
import math
import sys
from pathlib import Path

import bpy  # bmesh · mathutils 는 bpy 를 먼저 불러야 보인다
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'art_source/tripo'
OUT = ROOT / 'assets/models/items'

# 게임 좌표 (x, y, z) ↔ Blender (x, -z, y). 모든 손질은 게임 좌표에서 한다.
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
B2G = G2B.inverted()

# src: art_source/tripo 의 파일, budget: 삼각형 상한,
# turn: 게임 좌표 회전 [(축, 도) …] 또는 'tip_to_bowl'(자루 끝 → 그릇 쪽을 +Y 로),
# span: 세로(Y) 길이 m, origin: 'bottom'(바닥 가운데) 또는 쥐는 곳(자루 끝에서 위로 m).
ASSETS = {
    'tool_pan': {'src': 'pan.glb', 'budget': 300, 'turn': [('X', 90.0)], 'span': 0.5, 'origin': 0.06},
    'tool_ladle': {'src': 'ladle.glb', 'budget': 300, 'turn': 'tip_to_bowl', 'span': 0.42, 'origin': 0.05},
    'npc_house': {'src': 'house.glb', 'budget': 4000, 'turn': [('Y', -90.0)], 'span': 4.2, 'origin': 'bottom'},
}


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def import_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # 텍스처 이음매에서 갈라진 정점을 합쳐야 줄일 때 틈이 벌어지지 않는다.
    bpy.ops.import_scene.gltf(filepath=str(path), merge_vertices=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.data.transform(ob.matrix_world)
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)
    ob.data.transform(B2G)
    return ob


def base_color_image(ob):
    for mat in ob.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                link = node.inputs['Base Color'].links
                if link and link[0].from_node.type == 'TEX_IMAGE':
                    return link[0].from_node.image
    return None


def bake_texture_colors(ob):
    """바탕색 텍스처 → 모서리 정점 색 (sRGB 값 그대로, 게임 셰이더가 선형으로 바꾼다). 5×5 평균으로 잔무늬를 누른다."""
    img = base_color_image(ob)
    me = ob.data
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    me.color_attributes.active_color = col
    if img is None:
        print('[tripo]   바탕색 텍스처 없음 → 흰색')
        for d in col.data:
            d.color = (1.0, 1.0, 1.0, 1.0)
        return
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    pad = np.pad(px, ((2, 2), (2, 2), (0, 0)), mode='edge')
    blur = sum(pad[dy:dy + h, dx:dx + w] for dy in range(5) for dx in range(5)) / 25.0
    # img.pixels 는 선형 값이다. 게임 정점 색은 sRGB 로 칠하는 약속이라 되돌린다.
    lin = np.clip(blur[..., :3], 0.0, 1.0)
    blur[..., :3] = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)
    uv = me.uv_layers.active.data
    for i, d in enumerate(col.data):
        u, v = uv[i].uv
        x = min(max(int(round((u % 1.0) * (w - 1))), 0), w - 1)
        y = min(max(int(round((v % 1.0) * (h - 1))), 0), h - 1)
        r, g, b, _a = blur[y, x]
        d.color = (float(r), float(g), float(b), 1.0)
    print(f'[tripo]   텍스처 {img.name} {w}x{h} → 정점 색')


def fit_budget(ob, budget):
    tris = tri_count(ob)
    if tris <= budget:
        return
    mod = ob.modifiers.new('fit', 'DECIMATE')
    mod.ratio = budget / tris * 0.97
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f'[tripo]   삼각형 {tris} → {tri_count(ob)} (예산 {budget})')


def smooth_with_creases(ob, angle_deg=50.0):
    """찰흙처럼 매끈하게, 이 각도보다 꺾인 모서리만 각지게."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    limit = math.radians(angle_deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    bm.to_mesh(ob.data)
    bm.free()


def verts(ob):
    co = np.zeros(len(ob.data.vertices) * 3, dtype=np.float64)
    ob.data.vertices.foreach_get('co', co)
    return co.reshape(-1, 3)


def place(ob, cfg):
    me = ob.data
    turn = cfg['turn']
    if turn == 'tip_to_bowl':
        v = verts(ob)
        # 자루 끝 = 가장 위·뒤쪽 점, 그릇 = 아래쪽 점들의 가운데.
        tip = Vector(v[np.argmax(v[:, 1] - v[:, 2])])
        low = v[v[:, 1] < v[:, 1].min() + 0.4 * np.ptp(v[:, 1])]
        bowl = Vector(low.mean(axis=0))
        me.transform((bowl - tip).normalized().rotation_difference(Vector((0, 1, 0))).to_matrix().to_4x4())
    else:
        for axis, deg in turn:
            me.transform(Matrix.Rotation(math.radians(deg), 4, axis))
    v = verts(ob)
    me.transform(Matrix.Scale(cfg['span'] / np.ptp(v[:, 1]), 4))
    v = verts(ob)
    lo = v[:, 1].min()
    if cfg['origin'] == 'bottom':
        c = (v.min(axis=0) + v.max(axis=0)) * 0.5
        origin = Vector((c[0], lo, c[2]))
    else:
        end = v[v[:, 1] < lo + 0.06 * np.ptp(v[:, 1])].mean(axis=0)
        origin = Vector((end[0], lo + cfg['origin'], end[2]))
    me.transform(Matrix.Translation(-origin))
    v = verts(ob)
    print(f'[tripo]   크기 {np.round(np.ptp(v, axis=0), 3).tolist()} m, 범위 y {v[:, 1].min():.3f}~{v[:, 1].max():.3f}')


def build(asset_id, cfg):
    print(f'[tripo] {asset_id} ← {cfg["src"]}')
    ob = import_mesh(SRC / cfg['src'])
    bake_texture_colors(ob)
    fit_budget(ob, cfg['budget'])
    place(ob, cfg)
    smooth_with_creases(ob)
    ob.data.materials.clear()
    for name in [a.name for a in ob.data.color_attributes if a.name != 'Col']:
        ob.data.color_attributes.remove(ob.data.color_attributes[name])
    ob.data.transform(G2B)
    OUT.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'{asset_id}.glb'), export_format='GLB', use_selection=True,
                              export_vertex_color='ACTIVE', export_materials='NONE', export_normals=True,
                              export_texcoords=False, export_apply=True)
    print(f'[tripo] {asset_id}: {tri_count(ob)} / {cfg["budget"]} tri')


def main():
    wanted = sys.argv[1:] or list(ASSETS)
    for asset_id in wanted:
        build(asset_id, ASSETS[asset_id])


if __name__ == '__main__':
    main()
