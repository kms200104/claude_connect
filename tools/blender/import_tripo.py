#!/usr/bin/env python3
"""Tripo 에서 받은 모형(art_source/tripo/<이름>.glb) → 게임용 assets/models/items/<id>.glb · <id>_low.glb.

Tripo 모형은 UV 와 바탕색 텍스처를 그대로 쓴다 (예전엔 정점 색으로 구웠는데, 정점 2~4천 개로는 창틀·기와 경계가 뭉개졌다). 그래서
  - 바탕색 텍스처 원본(JPEG)을 glb 에서 꺼내 <id>.jpg 로 두고 (노멀·러프니스 맵은 버린다 — 툰 셰이더가 쓰지 않는다),
    게임은 같은 이름의 텍스처가 있으면 툰 셰이더에 그 텍스처를 꽂은 머티리얼로 그린다 (PartMesh.material_for),
  - 게임 좌표(Y 위, +Z 앞)로 돌리고 크기·원점(도구는 쥐는 곳, 건물은 바닥 가운데 또는 앞면)을 맞춘 뒤,
  - 고화질용 <id>.glb 는 원본 폴리곤 그대로, 절약(중사양)용 <id>_low.glb 는 삼각형 예산(CLAUDE.md)까지 줄여서 낸다
    (Decimate — 색은 줄이기 전에 구워야 덜 뭉개진다).
게임은 같은 이름의 glb 가 있으면 코드로 빚은 모형 대신 그것을 쓰고, 절약 화질이면 _low 를 고른다 (PartMesh.load_model).

사용: python3 tools/blender/import_tripo.py [id …]      (pip install bpy — Blender 5.0 파이썬 모듈)
"""
import json
import math
import struct
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

# src: art_source/tripo 의 파일, budget: 절약용(_low) 삼각형 상한,
# turn: 게임 좌표 회전 [(축, 도) …] 또는 'tip_to_bowl'(자루 끝 → 그릇 쪽을 +Y 로),
# fit: (축 'x'|'y', 길이 m) — 그 축 길이에 맞춰 고르게 키운다,
# origin: 'bottom'(바닥 가운데) · 'front'(바닥, 앞면이 z=0 — 상점처럼 문 자리에 맞추는 건물) · 쥐는 곳(자루 끝에서 위로 m).
ASSETS = {
    'tool_pan': {'src': 'pan.glb', 'budget': 300, 'turn': [('X', 90.0)], 'fit': ('y', 0.5), 'origin': 0.06},
    'tool_ladle': {'src': 'ladle.glb', 'budget': 300, 'turn': 'tip_to_bowl', 'fit': ('y', 0.34), 'origin': 0.04},
    'tool_knife': {'src': 'knife.glb', 'budget': 200, 'turn': [('Z', 90.0)], 'fit': ('y', 0.32), 'origin': 0.05},
    'npc_house': {'src': 'house.glb', 'budget': 4000, 'turn': [('Y', -90.0)], 'fit': ('y', 4.2), 'origin': 'bottom'},
    'shop_ext_1': {'src': 'shop_1.glb', 'budget': 4000, 'turn': [], 'fit': ('x', 4.5), 'origin': 'front'},
    'shop_ext_2': {'src': 'shop_2.glb', 'budget': 4000, 'turn': [], 'fit': ('x', 6.5), 'origin': 'front'},
    'shop_ext_3': {'src': 'shop_3.glb', 'budget': 4000, 'turn': [], 'fit': ('x', 9.0), 'origin': 'front'},
    'shop_counter': {'src': 'shop_counter.glb', 'budget': 1500, 'turn': [], 'fit': ('x', 2.0), 'origin': 'bottom'},
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


def extract_base_color(src, dest):
    """glb 안의 바탕색 텍스처 원본 바이트를 그대로 꺼낸다 (다시 압축하지 않아 화질이 그대로)."""
    data = src.read_bytes()
    json_len = struct.unpack('<I', data[12:16])[0]
    gltf = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    tex = gltf['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']
    image = gltf['images'][gltf['textures'][tex]['source']]
    view = gltf['bufferViews'][image['bufferView']]
    start = bin_start + view.get('byteOffset', 0)
    ext = '.png' if image.get('mimeType') == 'image/png' else '.jpg'
    other = '.jpg' if ext == '.png' else '.png'
    for stale in (dest.with_suffix(other), dest.with_suffix(other + '.import')):
        stale.unlink(missing_ok=True)
    out = dest.with_suffix(ext)
    out.write_bytes(data[start:start + view['byteLength']])
    # 3D 텍스처 가져오기 설정: 밉맵 켬(멀리서 반짝이지 않게), 무손실(압축 얼룩 없이). 이미 있으면 그대로 둔다.
    settings = dest.with_suffix(ext + '.import')
    if not settings.exists():
        settings.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                            'compress/mode=0\nmipmaps/generate=true\ndetect_3d/compress_to=0\n', encoding='utf-8')
    return out


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
    axis, length = cfg['fit']
    me.transform(Matrix.Scale(length / np.ptp(v[:, 'xyz'.index(axis)]), 4))
    v = verts(ob)
    lo = v[:, 1].min()
    c = (v.min(axis=0) + v.max(axis=0)) * 0.5
    if cfg['origin'] == 'bottom':
        origin = Vector((c[0], lo, c[2]))
    elif cfg['origin'] == 'front':
        origin = Vector((c[0], lo, v[:, 2].max()))
    else:
        end = v[v[:, 1] < lo + 0.06 * np.ptp(v[:, 1])].mean(axis=0)
        origin = Vector((end[0], lo + cfg['origin'], end[2]))
    me.transform(Matrix.Translation(-origin))
    v = verts(ob)
    print(f'[tripo]   크기 {np.round(np.ptp(v, axis=0), 3).tolist()} m, 범위 y {v[:, 1].min():.3f}~{v[:, 1].max():.3f}')


def export(ob, name):
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'{name}.glb'), export_format='GLB', use_selection=True,
                              export_vertex_color='NONE', export_materials='NONE', export_normals=True,
                              export_texcoords=True, export_apply=True)


def build(asset_id, cfg):
    print(f'[tripo] {asset_id} ← {cfg["src"]}')
    ob = import_mesh(SRC / cfg['src'])
    OUT.mkdir(parents=True, exist_ok=True)
    tex = extract_base_color(SRC / cfg['src'], OUT / asset_id)
    print(f'[tripo]   텍스처 {tex.name} ({tex.stat().st_size // 1024} KB)')
    place(ob, cfg)
    ob.data.materials.clear()
    for name in [a.name for a in ob.data.color_attributes]:
        ob.data.color_attributes.remove(ob.data.color_attributes[name])
    ob.data.transform(G2B)
    OUT.mkdir(parents=True, exist_ok=True)
    # 고화질: 원본 폴리곤 그대로.
    full = tri_count(ob)
    low_ob = ob.copy()
    low_ob.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(low_ob)
    smooth_with_creases(ob)
    export(ob, asset_id)
    # 절약: 예산까지 줄인다. 이미 예산 안이면 따로 내지 않는다 (게임이 고화질 파일을 같이 쓴다).
    low_path = OUT / f'{asset_id}_low.glb'
    for stale in (low_path, low_path.with_suffix('.glb.import')):
        stale.unlink(missing_ok=True)
    if full > cfg['budget']:
        fit_budget(low_ob, cfg['budget'])
        smooth_with_creases(low_ob)
        export(low_ob, f'{asset_id}_low')
    print(f'[tripo] {asset_id}: 고화질 {full} / 절약 {tri_count(low_ob)} (예산 {cfg["budget"]}) tri')


def main():
    wanted = sys.argv[1:] or list(ASSETS)
    for asset_id in wanted:
        build(asset_id, ASSETS[asset_id])


if __name__ == '__main__':
    main()
