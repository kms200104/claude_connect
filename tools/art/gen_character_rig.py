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

# ---- 새 동작 (브레이크·자랑·심기·감정표현) ----
def pose(vp=(0,0,0), vr=(0,0,0), vs=(1,1,1), al=(0,0,AL), ar=(0,0,AR), ll=(0,0,0), lr=(0,0,0)):
    return [V(*vp), V(*vr), V(*vs), V(*al), V(*ar), V(*ll), V(*lr), V(ROD,0,0), V(AXE,0,0)]
REST = pose()
def anim(name, length, frames, loop=False):
    times=[t for t,_ in frames]
    keys=[[f[i] for _,f in frames] for i in range(len(TRACKS))]
    anims[name]=dict(length=length, loop=loop, times=times, keys=keys)

# brake: 몸을 뒤로 젖히고 앞발로 버티며 두 팔을 허우적 (미끄러지는 동안 반복)
anim('brake', 0.24, [
 (0, pose((0,-0.07,0.02),(0.34,0,0.04),(1.05,0.94,1.05),(0.95,0,-0.95),(0.8,0,0.85),(0.8,0,0),(-0.35,0,0))),
 (0.12, pose((0,-0.06,0.02),(0.3,0,-0.04),(1.04,0.95,1.04),(0.75,0,-1.1),(1.0,0,1.0),(0.75,0,0),(-0.3,0,0))),
 (0.24, pose((0,-0.07,0.02),(0.34,0,0.04),(1.05,0.94,1.05),(0.95,0,-0.95),(0.8,0,0.85),(0.8,0,0),(-0.35,0,0)))], loop=True)
# show: 잡은 물고기를 두 손으로 카메라 앞에 쭉 내밀고 으쓱으쓱 (자랑하는 동안 반복)
anim('show', 1.0, [
 (0, pose((0,0.02,0),(-0.06,0,0),(1,1,1),(1.75,0,0.26),(1.75,0,-0.26),(0,0,-0.08),(0,0,0.08))),
 (0.5, pose((0,0.06,0),(-0.04,0,0),(0.98,1.03,0.98),(1.9,0,0.26),(1.9,0,-0.26),(0,0,-0.08),(0,0,0.08))),
 (1.0, pose((0,0.02,0),(-0.06,0,0),(1,1,1),(1.75,0,0.26),(1.75,0,-0.26),(0,0,-0.08),(0,0,0.08)))], loop=True)
# plant: 쪼그려 앉아 흙을 토닥토닥
anim('plant', 0.9, [
 (0, REST),
 (0.15, pose((0,-0.12,0),(-0.35,0,0),(1.03,0.96,1.03),(0.6,0,-0.1),(0.9,0,0.1),(0.55,0,0),(-0.25,0,0))),
 (0.35, pose((0,-0.13,0),(-0.38,0,0),(1.03,0.96,1.03),(0.6,0,-0.1),(1.35,0,0.05),(0.55,0,0),(-0.25,0,0))),
 (0.5, pose((0,-0.12,0),(-0.36,0,0),(1.03,0.96,1.03),(0.6,0,-0.1),(0.95,0,0.1),(0.55,0,0),(-0.25,0,0))),
 (0.65, pose((0,-0.13,0),(-0.38,0,0),(1.03,0.96,1.03),(0.6,0,-0.1),(1.35,0,0.05),(0.55,0,0),(-0.25,0,0))),
 (0.9, REST)])
# hello: 오른손을 번쩍 들어 좌우로 흔든다
anim('hello', 1.2, [
 (0, REST),
 (0.15, pose(vr=(0.04,0,-0.05),ar=(0.25,0,2.6))),
 (0.35, pose(vr=(0.04,0,-0.08),ar=(0.25,0,2.05))),
 (0.55, pose(vr=(0.04,0,-0.05),ar=(0.25,0,2.7))),
 (0.75, pose(vr=(0.04,0,-0.08),ar=(0.25,0,2.05))),
 (0.95, pose(vr=(0.04,0,-0.05),ar=(0.25,0,2.6))),
 (1.2, REST)])
# happy: 두 팔을 번쩍 들고 깡충깡충
anim('happy', 1.0, [
 (0, REST),
 (0.12, pose((0,-0.05,0),(0,0,0),(1.08,0.9,1.08),(0.3,0,-1.2),(0.3,0,1.2),(0.3,0,0),(0.3,0,0))),
 (0.27, pose((0,0.25,0),(0.06,0,0),(0.95,1.08,0.95),(0.2,0,-2.7),(0.2,0,2.7),(-0.2,0,0),(-0.2,0,0))),
 (0.42, pose((0,-0.04,0),(0,0,0),(1.08,0.9,1.08),(0.3,0,-1.4),(0.3,0,1.4),(0.3,0,0),(0.3,0,0))),
 (0.6, pose((0,0.25,0),(0.06,0,0),(0.95,1.08,0.95),(0.2,0,-2.7),(0.2,0,2.7),(-0.2,0,0),(-0.2,0,0))),
 (0.78, pose((0,-0.04,0),(0,0,0),(1.06,0.92,1.06),(0.3,0,-1.0),(0.3,0,1.0),(0.25,0,0),(0.25,0,0))),
 (1.0, REST)])
# laugh: 뒤로 젖혀 배를 잡고 들썩들썩
LA = lambda y, rx: pose((0,y,0),(rx,0,0),(1.02,0.98,1.02),(0.65,0,0.35),(0.65,0,-0.35))
anim('laugh', 1.2, [
 (0, REST), (0.15, LA(0.0,0.2)), (0.25, LA(0.04,0.24)), (0.35, LA(0.0,0.2)), (0.45, LA(0.04,0.25)),
 (0.55, LA(0.0,0.2)), (0.65, LA(0.04,0.24)), (0.75, LA(0.0,0.2)), (0.85, LA(0.04,0.22)), (1.2, REST)])
# surprise: 깜짝 놀라 뒤로 펄쩍, 두 팔을 번쩍
anim('surprise', 0.9, [
 (0, REST),
 (0.1, pose((0,0.2,0.18),(0.28,0,0),(0.94,1.1,0.94),(0.5,0,-2.3),(0.5,0,2.3),(-0.3,0,0),(0.3,0,0))),
 (0.25, pose((0,0,0.22),(0.22,0,0),(1.06,0.94,1.06),(0.5,0,-2.1),(0.5,0,2.1),(0,0,0),(0,0,0))),
 (0.6, pose((0,0,0.22),(0.18,0,0),(1,1,1),(0.4,0,-1.9),(0.4,0,1.9),(0,0,0),(0,0,0))),
 (0.9, REST)])
# love: 두 손을 가슴에 모으고 살랑살랑
LV = lambda rz, y: pose((0,y,0),(0.05,0,rz),(1,1,1),(1.15,0,0.5),(1.15,0,-0.5))
anim('love', 1.4, [(0, REST), (0.2, LV(0.12,0.02)), (0.5, LV(-0.12,0.0)), (0.8, LV(0.12,0.02)), (1.1, LV(-0.08,0.0)), (1.4, REST)])
# sad: 고개를 푹 숙이고 어깨가 축
SD = lambda rz: pose((0,-0.05,0),(-0.28,0,rz),(1.03,0.95,1.03),(0.12,0,-0.04),(0.12,0,0.04))
anim('sad', 1.6, [(0, REST), (0.35, SD(0.04)), (0.8, SD(-0.04)), (1.25, SD(0.03)), (1.6, REST)])
# angry: 발을 쿵쿵, 두 팔을 아래로 뻗치고 고개를 휙
AG = lambda y, ry, lr: pose((0,y,0),(-0.1,ry,0),(1.04,0.96,1.04),(-0.35,0,-0.3),(-0.35,0,0.3),(0,0,0),(lr,0,0))
anim('angry', 1.0, [(0, REST), (0.1, AG(0.04,0.15,0.6)), (0.22, AG(-0.04,-0.15,0)), (0.34, AG(0.04,0.15,0.6)),
 (0.46, AG(-0.04,-0.15,0)), (0.6, AG(0,0.1,0)), (1.0, REST)])
# think: 손을 턱에 대고 고개를 갸웃
TK = lambda rz: pose((0,0,0),(0.04,0,rz),(1,1,1),(0.9,0,0.65),(2.0,0,-0.55))
anim('think', 1.6, [(0, REST), (0.3, TK(0.14)), (0.8, TK(0.2)), (1.25, TK(0.14)), (1.6, REST)])
# clap: 앞으로 손뼉 짝짝짝
CL = lambda z: pose((0,0.02 if z>0 else 0,0),(0.03,0,0),(1,1,1),(1.3,0,z),(1.3,0,-z))
anim('clap', 1.1, [(0, REST), (0.15, CL(-0.15)), (0.27, CL(0.3)), (0.39, CL(-0.15)), (0.51, CL(0.3)), (0.63, CL(-0.15)),
 (0.75, CL(0.3)), (0.87, CL(-0.15)), (1.1, REST)])
# bow: 꾸벅 인사
BW = pose((0,-0.03,0),(-0.55,0,0),(1,1,1),(0.15,0,-0.05),(0.15,0,0.05))
anim('bow', 1.2, [(0, REST), (0.35, BW), (0.75, BW), (1.2, REST)])
# sleepy: 기지개를 켜며 하품, 그리고 꾸벅꾸벅
anim('sleepy', 1.8, [
 (0, REST),
 (0.45, pose((0,0.03,0),(0.16,0,0),(0.97,1.04,0.97),(0.3,0,-2.6),(0.3,0,2.6))),
 (0.8, pose((0,0.03,0),(0.18,0,0),(0.97,1.04,0.97),(0.3,0,-2.65),(0.3,0,2.65))),
 (1.15, pose((0,-0.03,0),(-0.18,0,0.06),(1.02,0.97,1.02),(0.05,0,-0.08),(0.05,0,0.08))),
 (1.45, pose((0,-0.04,0),(-0.24,0,-0.06),(1.02,0.97,1.02),(0.05,0,-0.08),(0.05,0,0.08))),
 (1.8, REST)])
EMOTES=['hello','happy','laugh','surprise','love','sad','angry','think','clap','bow','sleepy']

# ---- 식당 (v0.8): 요리 동작 다섯 가지와 의자에 앉기 ----
# cook_chop: 왼손으로 재료를 누르고 오른손 칼로 탁탁 (썰기 박자 0.48초에 맞춘다)
CC = lambda up: pose((0,-0.03,0),(-0.14,0,0),(1,1,1),(0.75,0,0.3),(1.3 if up else 0.82,0,-0.12))
anim('cook_chop', 0.48, [(0, CC(True)), (0.16, CC(False)), (0.24, CC(False)), (0.48, CC(True))], loop=True)
# cook_stir: 왼손으로 팬(냄비) 손잡이를 잡고 오른손으로 휘휘 젓는다
ST = lambda z, y: pose((0,y,0),(-0.08,0,0),(1,1,1),(0.85,0,0.2),(1.0,0.25*z,-0.1+0.3*z))
anim('cook_stir', 0.8, [(0, ST(-1,0)), (0.2, ST(0,0.01)), (0.4, ST(1,0)), (0.6, ST(0,0.01)), (0.8, ST(-1,0))], loop=True)
# cook_flip: 두 손으로 팬을 들어 휙 뒤집는다
FL = lambda up, y: pose((0,y,0),(-0.05 if up else -0.12,0,0),(1,1,1),(1.35 if up else 0.85,0,0.18),(1.35 if up else 0.85,0,-0.18))
anim('cook_flip', 0.7, [(0, FL(False,0)), (0.18, FL(True,0.05)), (0.32, FL(True,0.06)), (0.5, FL(False,0)), (0.7, FL(False,0))], loop=True)
# cook_mix: 왼팔로 그릇을 안고 오른손으로 빠르게 섞는다
MX = lambda z: pose((0,0,0),(-0.1,0,0.03*z),(1,1,1),(0.95,0,0.42),(1.05,0,-0.2+0.28*z))
anim('cook_mix', 0.3, [(0, MX(-1)), (0.15, MX(1)), (0.3, MX(-1))], loop=True)
# cook_plate: 두 손으로 접시를 받쳐 살며시 내려놓는다
PL = lambda x, y: pose((0,y,0),(-0.1,0,0),(1,1,1),(x,0,0.22),(x,0,-0.22))
anim('cook_plate', 1.0, [(0, PL(1.25,0)), (0.5, PL(0.95,-0.02)), (1.0, PL(1.25,0))], loop=True)
COOKS=['cook_chop','cook_stir','cook_flip','cook_mix','cook_plate']
# dig: 삽을 땅에 꽂고(몸을 숙여) 발로 밟은 듯 들썩, 흙을 퍼 올린다 (v0.9)
DG = lambda vy, rx, a, ll: pose((0,vy,0),(rx,0,0),(1,1,1),(a,0,0.15),(a+0.15,0,-0.12),(ll,0,0),(0,0,0))
anim('dig', 0.7, [(0, REST), (0.18, DG(-0.06,-0.32,0.55,0.3)), (0.32, DG(-0.1,-0.42,0.35,0.0)), (0.5, DG(0.0,-0.1,1.25,0.0)), (0.7, REST)])
# sit: 의자에 앉아 두 다리를 앞으로 쭉 (작은 몸이라 발이 바닥에 안 닿는다), 가끔 몸을 흔든다
SI = lambda rz, y: pose((0,y,0),(0.04,0,rz),(1,1,1),(0.5,0,0.08),(0.5,0,-0.08),(1.5,0,0.05),(1.5,0,-0.05))
anim('sit', 2.4, [(0, SI(0,0)), (0.6, SI(0.04,0.008)), (1.2, SI(0,0)), (1.8, SI(-0.04,0.008)), (2.4, SI(0,0))], loop=True)

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
&"walk": SubResource("Animation_walk"),
''' + ',\n'.join('&"%s": SubResource("Animation_%s")'%(n,n) for n in ['brake','show','plant']+EMOTES+COOKS+['sit','dig']) + '''
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

[sub_resource type="AnimationNodeAnimation" id="AN_brake"]
animation = &"brake"

[sub_resource type="AnimationNodeBlend2" id="Blend2_brake"]

[sub_resource type="AnimationNodeAnimation" id="AN_plant"]
animation = &"plant"

[sub_resource type="AnimationNodeOneShot" id="OneShot_plant"]
fadein_time = 0.08
fadeout_time = 0.15

[sub_resource type="AnimationNodeAnimation" id="AN_show"]
animation = &"show"

[sub_resource type="AnimationNodeBlend2" id="Blend2_show"]

''' + ''.join('[sub_resource type="AnimationNodeAnimation" id="AN_%s"]\nanimation = &"%s"\n\n'%(e,e) for e in EMOTES) + '''[sub_resource type="AnimationNodeTransition" id="Transition_emote"]
xfade_time = 0.0
''' + ''.join('input_%d/name = "%s"\ninput_%d/auto_advance = false\ninput_%d/break_loop_at_end = false\ninput_%d/reset = true\n'%(i,e,i,i,i) for i,e in enumerate(EMOTES)) + '''
''' + ''.join('[sub_resource type="AnimationNodeAnimation" id="AN_%s"]\nanimation = &"%s"\n\n'%(e,e) for e in COOKS+['sit','dig']) + '''[sub_resource type="AnimationNodeOneShot" id="OneShot_dig"]
fadein_time = 0.06
fadeout_time = 0.12

[sub_resource type="AnimationNodeTransition" id="Transition_cook"]
xfade_time = 0.12
''' + ''.join('input_%d/name = "%s"\ninput_%d/auto_advance = false\ninput_%d/break_loop_at_end = false\ninput_%d/reset = true\n'%(i,e,i,i,i) for i,e in enumerate(COOKS)) + '''
[sub_resource type="AnimationNodeBlend2" id="Blend2_cook"]

[sub_resource type="AnimationNodeBlend2" id="Blend2_sit"]

[sub_resource type="AnimationNodeOneShot" id="OneShot_emote"]
fadein_time = 0.1
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
nodes/Locomotion/position = Vector2(-300, 0)
nodes/Brake/node = SubResource("AN_brake")
nodes/Brake/position = Vector2(-300, 160)
nodes/BrakeBlend/node = SubResource("Blend2_brake")
nodes/BrakeBlend/position = Vector2(-100, 0)
nodes/Fishing/node = SubResource("AN_fishing")
nodes/Fishing/position = Vector2(-100, 160)
nodes/FishBlend/node = SubResource("Blend2_fishing")
nodes/FishBlend/position = Vector2(120, 40)
''' + ''.join('nodes/K_%s/node = SubResource("AN_%s")\nnodes/K_%s/position = Vector2(-100, %d)\n'%(e,e,e,320+i*60) for i,e in enumerate(COOKS)) + '''nodes/CookSwitch/node = SubResource("Transition_cook")
nodes/CookSwitch/position = Vector2(120, 320)
nodes/CookBlend/node = SubResource("Blend2_cook")
nodes/CookBlend/position = Vector2(220, 40)
nodes/Sit/node = SubResource("AN_sit")
nodes/Sit/position = Vector2(220, 200)
nodes/SitBlend/node = SubResource("Blend2_sit")
nodes/SitBlend/position = Vector2(270, 40)
nodes/Chop/node = SubResource("AN_chop")
nodes/Chop/position = Vector2(120, 200)
nodes/ChopShot/node = SubResource("OneShot_chop")
nodes/ChopShot/position = Vector2(320, 40)
nodes/Cast/node = SubResource("AN_cast")
nodes/Cast/position = Vector2(320, 200)
nodes/CastShot/node = SubResource("OneShot_cast")
nodes/CastShot/position = Vector2(520, 40)
nodes/Plant/node = SubResource("AN_plant")
nodes/Plant/position = Vector2(520, 200)
nodes/PlantShot/node = SubResource("OneShot_plant")
nodes/PlantShot/position = Vector2(720, 40)
nodes/Dig/node = SubResource("AN_dig")
nodes/Dig/position = Vector2(720, 200)
nodes/DigShot/node = SubResource("OneShot_dig")
nodes/DigShot/position = Vector2(820, 40)
''' + ''.join('nodes/E_%s/node = SubResource("AN_%s")\nnodes/E_%s/position = Vector2(520, %d)\n'%(e,e,e,360+i*60) for i,e in enumerate(EMOTES)) + '''nodes/EmoteSwitch/node = SubResource("Transition_emote")
nodes/EmoteSwitch/position = Vector2(720, 300)
nodes/EmoteShot/node = SubResource("OneShot_emote")
nodes/EmoteShot/position = Vector2(920, 40)
nodes/Show/node = SubResource("AN_show")
nodes/Show/position = Vector2(920, 200)
nodes/ShowBlend/node = SubResource("Blend2_show")
nodes/ShowBlend/position = Vector2(1120, 40)
nodes/output/position = Vector2(1320, 40)
node_connections = [&"BrakeBlend", 0, &"Locomotion", &"BrakeBlend", 1, &"Brake", &"FishBlend", 0, &"BrakeBlend", &"FishBlend", 1, &"Fishing", ''' + ''.join('&"CookSwitch", %d, &"K_%s", '%(i,e) for i,e in enumerate(COOKS)) + '''&"CookBlend", 0, &"FishBlend", &"CookBlend", 1, &"CookSwitch", &"SitBlend", 0, &"CookBlend", &"SitBlend", 1, &"Sit", &"ChopShot", 0, &"SitBlend", &"ChopShot", 1, &"Chop", &"CastShot", 0, &"ChopShot", &"CastShot", 1, &"Cast", &"PlantShot", 0, &"CastShot", &"PlantShot", 1, &"Plant", ''' + ''.join('&"EmoteSwitch", %d, &"E_%s", '%(i,e) for i,e in enumerate(EMOTES)) + '''&"DigShot", 0, &"PlantShot", &"DigShot", 1, &"Dig", &"EmoteShot", 0, &"DigShot", &"EmoteShot", 1, &"EmoteSwitch", &"ShowBlend", 0, &"EmoteShot", &"ShowBlend", 1, &"Show", &"output", 0, &"ShowBlend"]

[node name="Rig" type="Node3D" node_paths=PackedStringArray("tree", "visual", "body_mesh", "arm_left", "arm_right", "leg_left", "leg_right", "rod", "axe", "tool")]
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
tool = NodePath("Visual/ArmR/Tool")
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

[node name="Tool" type="Node3D" parent="Visual/ArmR"]
visible = false
transform = Transform3D(1, 0, 0, 0, -0.5885011, -0.8084964, 0, 0.8084964, -0.5885011, 0, -0.3, 0)

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
parameters/BrakeBlend/blend_amount = 0.0
parameters/ShowBlend/blend_amount = 0.0
parameters/PlantShot/active = false
parameters/PlantShot/internal_active = false
parameters/PlantShot/request = 0
parameters/DigShot/active = false
parameters/DigShot/internal_active = false
parameters/DigShot/request = 0
parameters/EmoteShot/active = false
parameters/EmoteShot/internal_active = false
parameters/EmoteShot/request = 0
parameters/EmoteSwitch/current_state = "hello"
parameters/EmoteSwitch/transition_request = ""
parameters/EmoteSwitch/current_index = 0
parameters/CookBlend/blend_amount = 0.0
parameters/CookSwitch/current_state = "cook_chop"
parameters/CookSwitch/transition_request = ""
parameters/CookSwitch/current_index = 0
parameters/SitBlend/blend_amount = 0.0
''')
open(OUT,'w').write('\n'.join(out))
print('ok')
