#!/usr/bin/env python3
"""game/player/character_rig.tscn 을 만든다 (애니메이션 키 표를 한 곳에서 관리). 사용: python3 tools/art/gen_character_rig.py"""
from pathlib import Path
OUT=str(Path(__file__).resolve().parents[2] / 'game/player/character_rig.tscn')
TRACKS=['Visual:position','Visual:rotation','Visual:scale','Visual/ArmL:rotation','Visual/ArmR:rotation',
        'Visual/LegL:rotation','Visual/LegR:rotation','Visual/ArmR/Rod:rotation','Visual/ArmR/Axe:rotation']
AL=-0.16; AR=0.16  # 팔 벌림(z)
ROD=-0.6; AXE=-0.5
def V(x,y,z): return (x,y,z)
anims={}
# idle
T=[0,1.2,2.4]
anims['idle']=dict(length=2.4,loop=True,times=T,keys=[
 [V(0,0,0),V(0,-0.01,0),V(0,0,0)],
 [V(0,0,0),V(0.02,0,0),V(0,0,0)],
 [V(1,1,1),V(1.02,0.975,1.02),V(1,1,1)],
 [V(0,0,AL),V(0.04,0,AL-0.04),V(0,0,AL)],
 [V(0,0,AR),V(0.04,0,AR+0.04),V(0,0,AR)],
 [V(0,0,0)]*3,[V(0,0,0)]*3,
 [V(ROD,0,0)]*3,[V(AXE,0,0)]*3])
# walk
T=[0,0.15,0.3,0.45,0.6]
s=0.55
anims['walk']=dict(length=0.6,loop=True,times=T,keys=[
 [V(0,0,0),V(0,0.045,0),V(0,0,0),V(0,0.045,0),V(0,0,0)],
 [V(-0.12,0,0.04),V(-0.12,0,0),V(-0.12,0,-0.04),V(-0.12,0,0),V(-0.12,0,0.04)],
 [V(1,1,1)]*5,
 [V(-s,0,AL),V(0,0,AL),V(s,0,AL),V(0,0,AL),V(-s,0,AL)],
 [V(s,0,AR),V(0,0,AR),V(-s,0,AR),V(0,0,AR),V(s,0,AR)],
 [V(s,0,0),V(0,0,0),V(-s,0,0),V(0,0,0),V(s,0,0)],
 [V(-s,0,0),V(0,0,0),V(s,0,0),V(0,0,0),V(-s,0,0)],
 [V(ROD,0,0)]*5,[V(AXE,0,0)]*5])
# run
T=[0,0.1,0.2,0.3,0.4]
a=1.0; l=0.9
anims['run']=dict(length=0.4,loop=True,times=T,keys=[
 [V(0,0,0),V(0,0.09,0),V(0,0,0),V(0,0.09,0),V(0,0,0)],
 [V(-0.26,0,0.07),V(-0.28,0,0),V(-0.26,0,-0.07),V(-0.28,0,0),V(-0.26,0,0.07)],
 [V(1.04,0.96,1.04),V(0.98,1.03,0.98),V(1.04,0.96,1.04),V(0.98,1.03,0.98),V(1.04,0.96,1.04)],
 [V(-a,0,AL-0.15),V(0,0,AL-0.15),V(a,0,AL-0.15),V(0,0,AL-0.15),V(-a,0,AL-0.15)],
 [V(a,0,AR+0.15),V(0,0,AR+0.15),V(-a,0,AR+0.15),V(0,0,AR+0.15),V(a,0,AR+0.15)],
 [V(l,0,0),V(0,0,0),V(-l,0,0),V(0,0,0),V(l,0,0)],
 [V(-l,0,0),V(0,0,0),V(l,0,0),V(0,0,0),V(-l,0,0)],
 [V(ROD,0,0)]*5,[V(AXE,0,0)]*5])
# fishing: 두 손으로 낚싯대를 앞으로 내민다
T=[0,1.0,2.0]
anims['fishing']=dict(length=2.0,loop=True,times=T,keys=[
 [V(0,-0.03,0),V(0,-0.04,0),V(0,-0.03,0)],
 [V(-0.1,0,0),V(-0.13,0,0),V(-0.1,0,0)],
 [V(1,1,1)]*3,
 [V(0.95,0,0.25),V(0.98,0,0.25),V(0.95,0,0.25)],
 [V(1.15,0,-0.12),V(1.18,0,-0.12),V(1.15,0,-0.12)],
 [V(0,0,0)]*3,[V(0,0,0)]*3,
 [V(-2.15,0,0),V(-2.1,0,0.03),V(-2.15,0,0)],
 [V(AXE,0,0)]*3])
# chop: 두 손으로 머리 위까지 들었다가 앞으로 내리친다
T=[0,0.15,0.25,0.45]
anims['chop']=dict(length=0.45,loop=False,times=T,keys=[
 [V(0,0,0),V(0,0.02,0),V(0,-0.04,0),V(0,0,0)],
 [V(0,0,0),V(0.15,0,0),V(-0.3,0,0),V(0,0,0)],
 [V(1,1,1),V(1,1,1),V(1.03,0.97,1.03),V(1,1,1)],
 [V(0.2,0,AL),V(2.6,0,0.25),V(0.85,0,0.2),V(0.2,0,AL)],
 [V(0.3,0,AR),V(3.0,0,-0.15),V(0.9,0,-0.15),V(0.3,0,AR)],
 [V(0,0,0),V(0.15,0,0),V(0.2,0,0),V(0,0,0)],
 [V(0,0,0),V(-0.1,0,0),V(-0.15,0,0),V(0,0,0)],
 [V(ROD,0,0)]*4,
 [V(AXE,0,0),V(-1.1,0,0),V(-2.6,0,0),V(AXE,0,0)]])

# cast: 낚싯대를 머리 뒤로 젖혔다가 앞으로 휙 던진다
T=[0,0.18,0.3,0.5]
anims['cast']=dict(length=0.5,loop=False,times=T,keys=[
 [V(0,0,0),V(0,0.02,0),V(0,-0.03,0),V(0,-0.03,0)],
 [V(0,0,0),V(0.18,0,0),V(-0.2,0,0),V(-0.1,0,0)],
 [V(1,1,1)]*4,
 [V(0,0,AL),V(0.4,0,AL),V(0.9,0,0.2),V(0.95,0,0.25)],
 [V(0.3,0,AR),V(2.9,0,-0.1),V(1.3,0,-0.12),V(1.15,0,-0.12)],
 [V(0,0,0),V(-0.15,0,0),V(0.2,0,0),V(0.1,0,0)],
 [V(0,0,0),V(0.1,0,0),V(-0.15,0,0),V(-0.05,0,0)],
 [V(ROD,0,0),V(-0.4,0,0),V(-2.3,0,0),V(-2.15,0,0)],
 [V(AXE,0,0)]*4])

def fmt(v):
    def f(x):
        s=('%.4f'%x).rstrip('0').rstrip('.')
        return '0' if s in ('-0','') else s
    return 'Vector3(%s, %s, %s)'%tuple(f(c) for c in v)

out=[]
out.append('[gd_scene load_steps=27 format=3]\n')
out.append('[ext_resource type="Script" path="res://game/player/character_rig.gd" id="1_rig"]')
out.append('[ext_resource type="Material" path="res://assets/materials/foliage.tres" id="2_clay"]\n')
for name,a in anims.items():
    out.append('[sub_resource type="Animation" id="Animation_%s"]'%name)
    out.append('resource_name = "%s"'%name)
    out.append('length = %s'%a['length'])
    if a['loop']: out.append('loop_mode = 1')
    out.append('step = 0.05')
    for i,(path,keys) in enumerate(zip(TRACKS,a['keys'])):
        assert len(keys)==len(a['times']),(name,path)
        n=len(keys)
        out.append('tracks/%d/type = "value"'%i)
        out.append('tracks/%d/imported = false'%i)
        out.append('tracks/%d/enabled = true'%i)
        out.append('tracks/%d/path = NodePath("%s")'%(i,path))
        out.append('tracks/%d/interp = 2'%i)
        out.append('tracks/%d/loop_wrap = true'%i)
        out.append('tracks/%d/keys = {'%i)
        out.append('"times": PackedFloat32Array(%s),'%', '.join(str(t) for t in a['times']))
        out.append('"transitions": PackedFloat32Array(%s),'%', '.join(['1']*n))
        out.append('"update": 0,')
        out.append('"values": [%s]'%', '.join(fmt(k) for k in keys))
        out.append('}')
    out.append('')
out.append('''[sub_resource type="AnimationLibrary" id="AnimationLibrary_rig"]
_data = {
&"cast": SubResource("Animation_cast"),
&"chop": SubResource("Animation_chop"),
&"fishing": SubResource("Animation_fishing"),
&"idle": SubResource("Animation_idle"),
&"run": SubResource("Animation_run"),
&"walk": SubResource("Animation_walk")
}

[sub_resource type="AnimationNodeAnimation" id="AN_idle"]
animation = &"idle"

[sub_resource type="AnimationNodeAnimation" id="AN_walk"]
animation = &"walk"

[sub_resource type="AnimationNodeAnimation" id="AN_run"]
animation = &"run"

[sub_resource type="AnimationNodeAnimation" id="AN_fishing"]
animation = &"fishing"

[sub_resource type="AnimationNodeAnimation" id="AN_chop"]
animation = &"chop"

[sub_resource type="AnimationNodeOneShot" id="OneShot_chop"]
fadein_time = 0.05
fadeout_time = 0.1

[sub_resource type="AnimationNodeAnimation" id="AN_cast"]
animation = &"cast"

[sub_resource type="AnimationNodeOneShot" id="OneShot_cast"]
fadein_time = 0.05
fadeout_time = 0.2

[sub_resource type="AnimationNodeBlendSpace1D" id="BlendSpace_locomotion"]
blend_point_0/node = SubResource("AN_idle")
blend_point_0/pos = 0.0
blend_point_1/node = SubResource("AN_walk")
blend_point_1/pos = 1.0
blend_point_2/node = SubResource("AN_run")
blend_point_2/pos = 2.0
min_space = 0.0
max_space = 2.0

[sub_resource type="AnimationNodeBlend2" id="Blend2_fishing"]

[sub_resource type="AnimationNodeBlendTree" id="BlendTree_rig"]
graph_offset = Vector2(-300, 0)
nodes/Locomotion/node = SubResource("BlendSpace_locomotion")
nodes/Locomotion/position = Vector2(-100, 0)
nodes/Fishing/node = SubResource("AN_fishing")
nodes/Fishing/position = Vector2(-100, 160)
nodes/FishBlend/node = SubResource("Blend2_fishing")
nodes/FishBlend/position = Vector2(120, 40)
nodes/Chop/node = SubResource("AN_chop")
nodes/Chop/position = Vector2(120, 200)
nodes/ChopShot/node = SubResource("OneShot_chop")
nodes/ChopShot/position = Vector2(320, 40)
nodes/Cast/node = SubResource("AN_cast")
nodes/Cast/position = Vector2(320, 200)
nodes/CastShot/node = SubResource("OneShot_cast")
nodes/CastShot/position = Vector2(520, 40)
nodes/output/position = Vector2(720, 40)
node_connections = [&"FishBlend", 0, &"Locomotion", &"FishBlend", 1, &"Fishing", &"ChopShot", 0, &"FishBlend", &"ChopShot", 1, &"Chop", &"CastShot", 0, &"ChopShot", &"CastShot", 1, &"Cast", &"output", 0, &"CastShot"]

[node name="Rig" type="Node3D" node_paths=PackedStringArray("tree", "visual", "body_mesh", "arm_left", "arm_right", "leg_left", "leg_right", "rod", "axe")]
script = ExtResource("1_rig")
tree = NodePath("AnimationTree")
visual = NodePath("Visual")
body_mesh = NodePath("Visual/Body")
arm_left = NodePath("Visual/ArmL")
arm_right = NodePath("Visual/ArmR")
leg_left = NodePath("Visual/LegL")
leg_right = NodePath("Visual/LegR")
rod = NodePath("Visual/ArmR/Rod")
axe = NodePath("Visual/ArmR/Axe")
clay_material = ExtResource("2_clay")

[node name="Visual" type="Node3D" parent="."]

[node name="Body" type="MeshInstance3D" parent="Visual"]

[node name="ArmL" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.23, -0.05, 0)

[node name="ArmR" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.23, -0.05, 0)

[node name="Rod" type="Node3D" parent="Visual/ArmR"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.3, 0)

[node name="Axe" type="Node3D" parent="Visual/ArmR"]
visible = false
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.3, 0)

[node name="LegL" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.1, -0.42, 0)

[node name="LegR" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.1, -0.42, 0)

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {
&"": SubResource("AnimationLibrary_rig")
}

[node name="AnimationTree" type="AnimationTree" parent="."]
tree_root = SubResource("BlendTree_rig")
anim_player = NodePath("../AnimationPlayer")
active = true
parameters/Locomotion/blend_position = 0.0
parameters/FishBlend/blend_amount = 0.0
parameters/ChopShot/active = false
parameters/ChopShot/internal_active = false
parameters/ChopShot/request = 0
parameters/CastShot/active = false
parameters/CastShot/internal_active = false
parameters/CastShot/request = 0
''')
open(OUT,'w').write('\n'.join(out))
print('ok')
