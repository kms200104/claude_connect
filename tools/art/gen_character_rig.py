#!/usr/bin/env python3
"""game/player/character_rig.tscn 을 만든다 (애니메이션 키 표를 한 곳에서 관리). 사용: python3 tools/art/gen_character_rig.py"""
from pathlib import Path
OUT=str(Path(__file__).resolve().parents[2] / 'game/player/character_rig.tscn')
# v0.13: 허리(Waist)와 목(Neck) 관절. 팔·도구는 허리 위(Upper)에, 머리는 목 위(Head)에 달린다.
UP='Visual/Waist/Upper'
# v0.15 무릎(Knee)·팔꿈치(Elbow) 관절: 정강이·부츠는 무릎 아래, 아래팔·손은 팔꿈치 아래. 손에 쥐는 도구는 팔꿈치 아래(손)에 달린다.
TRACKS=['Visual:position','Visual:rotation','Visual:scale',UP+'/ArmL:rotation',UP+'/ArmR:rotation',
        'Visual/LegL:rotation','Visual/LegR:rotation',UP+'/ArmR/ElbowR/Rod:rotation',UP+'/ArmR/ElbowR/Axe:rotation',
        'Visual/LegL/KneeL:rotation','Visual/LegR/KneeR:rotation',UP+'/ArmL/ElbowL:rotation',UP+'/ArmR/ElbowR:rotation']
KNEE_Y=-0.18   # 무릎 (골반 관절 기준): 허벅지 끝 · 부츠 접은 단
ELBOW_Y=-0.11  # 팔꿈치 (어깨 관절 기준): 소매 가운데
THIGH=0.18; SHIN=0.17  # 골반 → 무릎, 무릎 → 발 앞쪽(페달 밟는 곳)
# 허리 · 목 트랙은 동작 표를 다 만든 뒤 split_spine() 이 Visual:rotation 에서 나눠 만든다.
SPINE_TRACKS=['Visual/Waist:rotation',UP+'/Neck:rotation']
WAIST_Y=-0.34  # 허리 관절 높이 (반바지 허리 · 스웨터 밑단이 겹치는 곳)
NECK_Y=0.06    # 목 관절 높이 (목폴라 위, 머리 밑)
AL=-0.16; AR=0.16  # 팔 벌림(z)
ROD=-0.6; AXE=-0.5
def V(x,y,z): return (x,y,z)
anims={}
def joints(knl, knr, ell, elr):
    """무릎·팔꿈치 키 (x 회전값 목록): 무릎은 굽히면 음수(정강이가 뒤로), 팔꿈치는 굽히면 양수(아래팔이 앞으로)."""
    return [[V(k,0,0) for k in knl],[V(k,0,0) for k in knr],[V(k,0,0) for k in ell],[V(k,0,0) for k in elr]]
# idle: 숨쉬기(가슴이 부풀며 살짝 늘어남)와 좌우로 체중 옮기기. 팔은 숨보다 조금 늦게 따라 흔들린다.
T=[0,0.8,1.6,2.4,3.2]
anims['idle']=dict(length=3.2,loop=True,times=T,keys=[
 [V(0,0,0),V(0.006,-0.012,0),V(0,0,0),V(-0.006,-0.012,0),V(0,0,0)],
 [V(0,0,0),V(0.02,0,-0.015),V(0.01,0,0),V(0.02,0,0.015),V(0,0,0)],
 [V(1,1,1),V(1.02,0.975,1.02),V(0.995,1.012,0.995),V(1.02,0.975,1.02),V(1,1,1)],
 [V(0,0,AL),V(0.03,0,AL-0.03),V(0.05,0,AL-0.05),V(0.02,0,AL-0.02),V(0,0,AL)],
 [V(0,0,AR),V(0.02,0,AR+0.02),V(0.05,0,AR+0.05),V(0.03,0,AR+0.03),V(0,0,AR)],
 [V(0,0,0),V(0,0,0.02),V(0,0,0),V(0,0,-0.01),V(0,0,0)],[V(0,0,0),V(0,0,0.01),V(0,0,0),V(0,0,-0.02),V(0,0,0)],
 [V(ROD,0,0)]*5,[V(AXE,0,0)]*5]+joints([-0.03,-0.05,-0.03,-0.02,-0.03],[-0.03,-0.02,-0.03,-0.05,-0.03],[0.1,0.13,0.15,0.12,0.1],[0.1,0.12,0.15,0.13,0.1]))
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
 [V(ROD,0,0)]*5,[V(AXE,0,0)]*5]+joints([-0.08,-0.1,-0.22,-0.62,-0.08],[-0.22,-0.62,-0.08,-0.1,-0.22],[0.3,0.25,0.35,0.25,0.3],[0.35,0.25,0.3,0.25,0.35]))
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
 [V(ROD,0,0)]*5,[V(AXE,0,0)]*5]+joints([-0.25,-0.32,-0.55,-1.35,-0.25],[-0.55,-1.35,-0.25,-0.32,-0.55],[1.05,0.95,1.15,0.95,1.05],[1.15,0.95,1.05,0.95,1.15]))
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
 [V(AXE,0,0)]*3]+joints([0]*3,[0]*3,[0]*3,[0]*3))
# ---- 동작 표 (v0.11): 12 가지 애니메이션 원칙을 따라 다시 짰다 ----
# - 예비동작(anticipation): 큰 동작 전에 반대 방향으로 살짝 움츠린다.
# - 따라가기·겹치는 동작(follow-through / overlapping action): 몸통이 먼저, 팔이 조금 늦게, 도구·낚싯대는 더 늦게 따라온다
#   (anim(..., lag=) 이 트랙 묶음마다 키를 뒤로 민다). 멈출 때는 목표를 살짝 지나쳤다가(overshoot) 돌아와 자리를 잡는다.
# - 천천히 들어가고 나오기(slow in / slow out): 극점 근처에 키를 하나 더 둬서 머문다.
# - 찌그러짐·늘어남(squash & stretch): 부피를 지키며(가로 ↔ 세로) 몸을 누르고 늘린다.
# 참고: Disney 12 principles (Thomas & Johnston), Mixamo · Rokoko 인사·박수 모캡의 타이밍.
def pose(vp=(0,0,0), vr=(0,0,0), vs=(1,1,1), al=(0,0,AL), ar=(0,0,AR), ll=(0,0,0), lr=(0,0,0), rod=ROD, axe=AXE, kl=0.0, kr=0.0, el=0.0, er=0.0):
    return [V(*vp), V(*vr), V(*vs), V(*al), V(*ar), V(*ll), V(*lr), V(rod,0,0), V(axe,0,0), V(kl,0,0), V(kr,0,0), V(el,0,0), V(er,0,0)]
REST = pose()
def sq(k):
    """k>0 늘어남, k<0 찌그러짐. 부피를 대략 지킨다."""
    y=1.0+k; w=1.0/(y**0.5)
    return (round(w,4), round(y,4), round(w,4))
GROUP=[0,0,0,1,1,2,2,3,3,2,2,1,1]  # 몸통 · 팔 · 다리 · 도구 · 무릎 · 팔꿈치
def anim(name, length, frames, loop=False, lag=(0.0,0.0,0.0,0.0)):
    times=[t for t,_ in frames]
    keys=[[f[i] for _,f in frames] for i in range(len(TRACKS))]
    ttimes=[]
    n=len(times)
    for i in range(len(TRACKS)):
        d=0.0 if loop else lag[GROUP[i]]
        ts=[]
        for j,t in enumerate(times):
            if j==0 or j==n-1:
                ts.append(t)
            else:
                ts.append(round(min(t+d, length-0.012*(n-1-j)),4))
        ttimes.append(ts)
    anims[name]=dict(length=length, loop=loop, times=times, ttimes=ttimes, keys=keys)
TOOL_LAG=(0.0,0.03,0.015,0.055)
SOFT_LAG=(0.0,0.045,0.02,0.06)

# chop: 무릎을 굽혀 움츠렸다가(예비) → 몸을 젖히며 도끼를 머리 위로 → 잠깐 머물고 → 몸을 접으며 내리친다 →
#       나무에 맞고 살짝 튕긴 뒤 → 숨을 고르며 제자리. 도끼 머리가 팔보다 늦게 따라온다.
anim('chop', 0.62, [
 (0, REST),
 (0.07, pose((0,-0.035,0),(0.05,-0.1,0),sq(-0.05),(-0.25,0,AL-0.05),(-0.2,0,AR+0.05),(0.15,0,0),(-0.1,0,0),axe=AXE+0.25)),
 (0.19, pose((0,0.03,0.02),(0.24,0.14,0),sq(0.05),(2.7,0,0.28),(3.05,0,-0.18),(0.1,0,0),(-0.15,0,0),axe=-0.75)),
 (0.25, pose((0,0.035,0.02),(0.27,0.16,0),sq(0.055),(2.85,0,0.3),(3.2,0,-0.2),(0.1,0,0),(-0.15,0,0),axe=-0.6)),
 (0.32, pose((0,-0.06,-0.03),(-0.36,-0.04,0),sq(-0.07),(0.7,0,0.2),(0.78,0,-0.15),(0.28,0,0),(-0.22,0,0),axe=-2.75)),
 (0.37, pose((0,-0.045,-0.03),(-0.3,0,0),sq(-0.02),(0.98,0,0.2),(1.05,0,-0.14),(0.25,0,0),(-0.2,0,0),axe=-2.45)),
 (0.47, pose((0,-0.02,0),(-0.12,0,0),sq(0.0),(0.45,0,0.0),(0.5,0,0.0),(0.1,0,0),(-0.08,0,0),axe=-1.3)),
 (0.62, REST)], lag=TOOL_LAG)

# cast: 몸을 살짝 앞으로 숙였다가(예비) → 낚싯대를 어깨 뒤로 → 몸을 앞으로 던지며 휙 (0.24초 즈음, 휙 소리와 맞춤) →
#       팔이 지나쳤다가 → 낚시 자세로 자리를 잡는다. 낚싯대는 팔보다 늦게 휘어 나간다(채찍).
anim('cast', 0.62, [
 (0, REST),
 (0.06, pose((0,-0.02,0),(-0.06,0,0),sq(-0.03),(0.15,0,AL),(0.55,0,AR),(0,0,0),(0,0,0),rod=-0.75)),
 (0.17, pose((0,0.025,0.02),(0.22,0.12,0),sq(0.04),(0.35,0,AL),(2.95,0,-0.1),(-0.18,0,0),(0.12,0,0),rod=-0.3)),
 (0.27, pose((0,-0.03,-0.03),(-0.24,-0.05,0),sq(-0.04),(0.85,0,0.2),(1.25,0,-0.12),(0.25,0,0),(-0.18,0,0),rod=-2.45)),
 (0.36, pose((0,-0.035,-0.02),(-0.16,0,0),sq(-0.01),(0.98,0,0.26),(1.05,0,-0.12),(0.15,0,0),(-0.08,0,0),rod=-2.25)),
 (0.48, pose((0,-0.03,0),(-0.1,0,0),sq(0.0),(0.94,0,0.25),(1.18,0,-0.12),(0.02,0,0),(0,0,0),rod=-2.12)),
 (0.62, pose((0,-0.03,0),(-0.1,0,0),(1,1,1),(0.95,0,0.25),(1.15,0,-0.12),(0,0,0),(0,0,0),rod=-2.15))], lag=TOOL_LAG)

# brake: 몸을 뒤로 젖히고 앞발로 버티며 두 팔을 허우적 (미끄러지는 동안 반복)
anim('brake', 0.32, [
 (0, pose((0,-0.07,0.02),(0.34,0,0.05),(1.05,0.94,1.05),(0.95,0,-0.95),(0.8,0,0.85),(0.8,0,0),(-0.35,0,0))),
 (0.08, pose((0,-0.065,0.02),(0.33,0,0.0),(1.045,0.945,1.045),(0.65,0,-1.15),(1.05,0,1.05),(0.78,0,0),(-0.33,0,0))),
 (0.16, pose((0,-0.06,0.02),(0.31,0,-0.05),(1.04,0.95,1.04),(0.8,0,-1.0),(0.7,0,0.8),(0.75,0,0),(-0.3,0,0))),
 (0.24, pose((0,-0.065,0.02),(0.33,0,0.0),(1.045,0.945,1.045),(1.05,0,-0.85),(0.9,0,1.1),(0.78,0,0),(-0.33,0,0))),
 (0.32, pose((0,-0.07,0.02),(0.34,0,0.05),(1.05,0.94,1.05),(0.95,0,-0.95),(0.8,0,0.85),(0.8,0,0),(-0.35,0,0)))], loop=True)
# show: 잡은 물고기를 두 손으로 카메라 앞에 쭉 내밀고 으쓱으쓱 (자랑하는 동안 반복)
SH = lambda y, a, rz, k: pose((0,y,0),(-0.06,0,rz),sq(k),(a,0,0.26),(a,0,-0.26),(0,0,-0.08),(0,0,0.08))
anim('show', 1.0, [(0, SH(0.02,1.75,0.0,0.0)), (0.2, SH(0.07,1.92,0.05,0.035)), (0.36, SH(0.03,1.85,0.03,-0.01)),
 (0.5, SH(0.0,1.75,0.0,-0.02)), (0.7, SH(0.07,1.92,-0.05,0.035)), (0.86, SH(0.03,1.85,-0.03,-0.01)), (1.0, SH(0.02,1.75,0.0,0.0))], loop=True)
# plant: 무릎을 굽혀 쪼그려 앉고(몸이 먼저, 팔이 뒤따름) 흙을 토닥토닥, 일어설 때 살짝 늘어난다
PT = lambda y, a, k: pose((0,y,0),(-0.37,0,0),sq(k),(0.6,0,-0.1),(a,0,0.08),(0.6,0,0),(-0.25,0,0),kl=-0.75,kr=-0.2)
anim('plant', 0.9, [
 (0, REST),
 (0.12, pose((0,-0.14,0),(-0.4,0,0),sq(-0.07),(0.55,0,-0.1),(0.7,0,0.1),(0.65,0,0),(-0.3,0,0),kl=-0.8,kr=-0.25)),
 (0.26, PT(-0.12,1.4,-0.03)), (0.36, PT(-0.135,0.9,-0.05)), (0.46, PT(-0.12,1.35,-0.03)), (0.56, PT(-0.135,0.9,-0.05)),
 (0.72, pose((0,0.02,0),(0.05,0,0),sq(0.03),(0.1,0,AL),(0.2,0,AR),(0,0,0),(0,0,0))),
 (0.9, REST)], lag=SOFT_LAG)

# ---- 감정표현: 예비동작 → 본동작 → 따라가기 → 자리 잡기 ----
# hello: 살짝 몸을 낮췄다가 오른팔을 크게 휘둘러 올리고, 손목·팔이 늦게 따라오며 좌우로 흔든다. 몸도 같이 흔들린다.
HW = lambda z, rz: pose((0,0.01,0),(0.04,0,rz),sq(0.01),(0.05,0,AL-0.05),(0.2,0,z))
anim('hello', 1.3, [
 (0, REST),
 (0.08, pose((0,-0.02,0),(-0.03,0,0.03),sq(-0.03),(0,0,AL),(0.15,0,0.6))),
 (0.22, HW(2.85,-0.08)), (0.38, HW(2.0,-0.03)), (0.54, HW(2.75,-0.08)), (0.7, HW(2.0,-0.03)), (0.86, HW(2.65,-0.07)),
 (1.02, pose((0,0,0),(0.02,0,-0.02),sq(0),(0,0,AL),(0.1,0,1.1))),
 (1.3, REST)], lag=SOFT_LAG)
# happy: 깊게 웅크렸다가(예비) 길게 늘어나며 깡충, 착지에 찌그러지고 다시 한 번
UPV = lambda y, k, a, l: pose((0,y,0),(0.06 if y>0 else -0.04,0,0),sq(k),(0.2,0,-a),(0.2,0,a),(l,0,0),(l,0,0))
anim('happy', 1.1, [
 (0, REST),
 (0.12, UPV(-0.07,-0.1,0.9,0.35)),
 (0.26, UPV(0.24,0.1,2.75,-0.2)),
 (0.34, UPV(0.26,0.03,2.85,-0.15)),
 (0.45, UPV(-0.06,-0.1,1.3,0.32)),
 (0.6, UPV(0.24,0.1,2.75,-0.2)),
 (0.68, UPV(0.26,0.03,2.85,-0.15)),
 (0.8, UPV(-0.05,-0.08,1.0,0.28)),
 (0.92, UPV(0.0,0.02,0.3,0.0)),
 (1.1, REST)], lag=SOFT_LAG)
# laugh: 들이마시며 몸을 젖히고 배를 잡은 채 '하·하·하' 들썩, 점점 잦아든다
LA = lambda y, rx, k: pose((0,y,0),(rx,0,0),sq(k),(0.65,0,0.35),(0.65,0,-0.35))
anim('laugh', 1.3, [
 (0, REST), (0.12, pose((0,-0.02,0),(-0.12,0,0),sq(-0.04),(0.3,0,0.1),(0.3,0,-0.1))),
 (0.26, LA(0.03,0.26,0.04)), (0.34, LA(-0.01,0.2,-0.03)), (0.42, LA(0.035,0.27,0.04)), (0.5, LA(-0.01,0.2,-0.03)),
 (0.6, LA(0.03,0.25,0.03)), (0.7, LA(0.0,0.19,-0.02)), (0.82, LA(0.02,0.2,0.01)), (0.98, LA(0.0,0.12,0.0)), (1.3, REST)], lag=SOFT_LAG)
# surprise: 순간 움찔(움츠림) → 펄쩍 뒤로 뛰며 길게 늘어남 → 착지 찌그러짐 → 굳은 채 떨다가 → 풀린다
SP = lambda y, z, rx, k, a: pose((0,y,z),(rx,0,0),sq(k),(0.5,0,-a),(0.5,0,a),(0,0,0),(0,0,0))
anim('surprise', 1.0, [
 (0, REST),
 (0.05, pose((0,-0.04,0),(-0.08,0,0),sq(-0.07),(0.4,0,0.15),(0.4,0,-0.15),(0.2,0,0),(0.2,0,0))),
 (0.15, pose((0,0.2,0.16),(0.3,0,0),sq(0.12),(0.5,0,-2.4),(0.5,0,2.4),(-0.3,0,0),(0.3,0,0))),
 (0.27, SP(-0.03,0.22,0.24,-0.08,2.0)),
 (0.36, SP(0.0,0.22,0.2,0.01,2.15)), (0.46, SP(0.0,0.22,0.21,-0.005,2.05)), (0.56, SP(0.0,0.22,0.19,0.005,2.1)),
 (0.75, SP(0.0,0.1,0.06,0.0,0.8)),
 (1.0, REST)], lag=SOFT_LAG)
# love: 두 손을 가슴에 모으고 몸을 꼬며 살랑, 마지막에 발끝을 들며 쭉
LV = lambda rz, ry, y, k: pose((0,y,0),(0.05,ry,rz),sq(k),(1.15,0,0.5),(1.15,0,-0.5))
anim('love', 1.5, [(0, REST), (0.18, pose((0,-0.02,0),(-0.04,0,0),sq(-0.03),(0.8,0,0.3),(0.8,0,-0.3))),
 (0.36, LV(0.13,0.1,0.02,0.02)), (0.6, LV(-0.13,-0.1,0.0,-0.01)), (0.84, LV(0.13,0.1,0.02,0.02)), (1.06, LV(-0.08,-0.05,0.04,0.04)),
 (1.24, LV(0.0,0.0,0.03,0.02)), (1.5, REST)], lag=SOFT_LAG)
# sad: 한숨(살짝 들렸다가) → 어깨가 축 처지고 고개를 숙인 채 천천히 흔들 → 무겁게 돌아온다
SD = lambda rz, rx: pose((0,-0.05,0),(rx,0,rz),sq(-0.04),(0.1,0,-0.02),(0.1,0,0.02))
anim('sad', 1.8, [(0, REST), (0.2, pose((0,0.02,0),(0.06,0,0),sq(0.02),(0.1,0,AL-0.05),(0.1,0,AR+0.05))),
 (0.55, SD(0.04,-0.3)), (0.9, SD(-0.04,-0.32)), (1.25, SD(0.03,-0.3)), (1.5, SD(0.0,-0.22)), (1.8, REST)], lag=SOFT_LAG)
# angry: 숨을 들이켜 부풀었다가 발을 쿵·쿵 구르며(찌그러짐) 팔을 아래로 뻗치고, 마지막에 홱 고개를 돌린다
AG = lambda y, ry, lr, k: pose((0,y,0),(-0.1,ry,0),sq(k),(-0.35,0,-0.3),(-0.35,0,0.3),(0,0,0),(lr,0,0))
anim('angry', 1.1, [(0, REST), (0.1, pose((0,0.03,0),(0.08,0,0),sq(0.05),(0.2,0,AL-0.2),(0.2,0,AR+0.2))),
 (0.2, AG(0.03,0.12,0.6,0.02)), (0.28, AG(-0.05,0.0,0.0,-0.08)), (0.38, AG(0.03,-0.12,0.6,0.02)), (0.46, AG(-0.05,0.0,0.0,-0.08)),
 (0.6, AG(0.0,0.42,0.0,0.0)), (0.82, AG(0.0,0.38,0.0,0.0)), (1.1, REST)], lag=SOFT_LAG)
# think: 고개를 갸웃하며 손을 턱으로, 잠시 '음…' 하고 다시 반대로 갸웃
TK = lambda rz, ry: pose((0,0,0),(0.04,ry,rz),(1,1,1),(0.9,0,0.65),(2.0,0,-0.55))
anim('think', 1.7, [(0, REST), (0.25, pose((0,-0.01,0),(0.02,0,0.05),(1,1,1),(0.5,0,0.3),(1.5,0,-0.3))),
 (0.42, TK(0.17,0.05)), (0.8, TK(0.2,0.06)), (1.0, TK(-0.06,-0.04)), (1.3, TK(-0.08,-0.05)), (1.7, REST)], lag=SOFT_LAG)
# clap: 손을 벌렸다가 짝(맞닿는 순간 몸이 살짝 튀고 손이 튕김), 점점 빠르게
CL = lambda z, y, k: pose((0,y,0),(0.03,0,0),sq(k),(1.3,0,z),(1.3,0,-z))
anim('clap', 1.15, [(0, REST), (0.14, CL(-0.35,0,0)),
 (0.24, CL(0.32,0.02,0.03)), (0.3, CL(0.2,0.015,0)), (0.4, CL(-0.3,0,-0.01)),
 (0.48, CL(0.32,0.02,0.03)), (0.53, CL(0.2,0.015,0)), (0.62, CL(-0.25,0,-0.01)),
 (0.69, CL(0.32,0.02,0.03)), (0.74, CL(0.2,0.015,0)), (0.88, CL(-0.05,0,0)), (1.15, REST)], lag=(0,0.02,0.01,0.03))
# bow: 손을 모으고 허리를 천천히 굽혀 잠시 멈췄다가, 올라올 땐 조금 더 빠르게 (팔이 늦게 따라옴)
BW = lambda rx, y: pose((0,y,0),(rx,0,0),(1,1,1),(0.25,0,0.1),(0.25,0,-0.1))
anim('bow', 1.4, [(0, REST), (0.15, BW(0.05,0.0)), (0.45, BW(-0.58,-0.03)), (0.62, BW(-0.62,-0.035)), (0.85, BW(-0.6,-0.03)),
 (1.05, BW(0.04,0.01)), (1.4, REST)], lag=SOFT_LAG)
# sleepy: 크게 기지개(늘어남) → 축 처짐 → 꾸벅 졸다 화들짝(작은 움찔) → 다시 꾸벅
anim('sleepy', 2.0, [
 (0, REST),
 (0.2, pose((0,-0.02,0),(-0.05,0,0),sq(-0.03),(0.3,0,-0.6),(0.3,0,0.6))),
 (0.5, pose((0,0.04,0),(0.16,0,0),sq(0.06),(0.3,0,-2.65),(0.3,0,2.65))),
 (0.78, pose((0,0.045,0),(0.19,0,0),sq(0.065),(0.3,0,-2.75),(0.3,0,2.75))),
 (1.05, pose((0,-0.03,0),(-0.2,0,0.06),sq(-0.03),(0.05,0,-0.08),(0.05,0,0.08))),
 (1.3, pose((0,-0.045,0),(-0.3,0,0.08),sq(-0.04),(0.05,0,-0.06),(0.05,0,0.06))),
 (1.38, pose((0,0.0,0),(0.02,0,0.0),sq(0.03),(0.15,0,-0.2),(0.15,0,0.2))),
 (1.62, pose((0,-0.04,0),(-0.26,0,-0.06),sq(-0.03),(0.05,0,-0.08),(0.05,0,0.08))),
 (2.0, REST)], lag=SOFT_LAG)
# tada (v0.15 탈의소): 갈아입고 나와서 "짜잔!" — 웅크렸다가(예비) 콩 뛰며 (이때 몸이 한 바퀴 도는 건 OutfitBooth 가 Visual 을 돌린다)
#       착지에 찌그러지고, 두 팔을 양옆으로 쫙 (머리가 커서 어깨보다 높이 들면 머리에 가린다), 왼발 뒤꿈치를 들고 몸을 살짝 기울여 잠깐 멈춘다.
TD = lambda y, k, rz: pose((0,y,0),(0.05,0,rz),sq(k),(0.4,0,-1.5),(0.4,0,1.65),(0.12,0,-0.12),(0,0,0.06),kl=-0.55,el=0.3,er=0.3)
anim('tada', 1.5, [
 (0, REST),
 (0.12, pose((0,-0.07,0),(-0.06,0,0),sq(-0.09),(0.35,0,0.2),(0.35,0,-0.2),(0.3,0,0),(0.3,0,0),kl=-0.6,kr=-0.6)),
 (0.3, pose((0,0.2,0),(0.05,0,0),sq(0.09),(0.2,0,-0.5),(0.2,0,0.5),(-0.25,0,0),(-0.25,0,0),kl=-0.5,kr=-0.5)),
 (0.48, pose((0,0.12,0),(0.0,0,0),sq(0.03),(0.3,0,-0.9),(0.25,0,1.4),(-0.1,0,0),(-0.1,0,0),kl=-0.3,kr=-0.3)),
 (0.6, pose((0,-0.05,0),(0.02,0,-0.04),sq(-0.07),(0.4,0,-1.35),(0.4,0,1.5),(0.1,0,-0.1),(0,0,0.05),kl=-0.5,kr=-0.2,el=0.2,er=0.2)),
 (0.72, TD(0.02,0.03,-0.1)),
 (1.15, TD(0.01,0.02,-0.08)),
 (1.5, REST)], lag=SOFT_LAG)
EMOTES=['hello','happy','laugh','surprise','love','sad','angry','think','clap','bow','sleepy','tada']

# ---- 식당 (v0.8): 요리 동작 다섯 가지와 의자에 앉기 (반복 동작이라 극점마다 짧게 머무른다) ----
# cook_chop: 왼손으로 재료를 누르고 오른손 칼로 탁탁 (썰기 박자 0.48초에 맞춘다). 칼이 닿을 때 몸이 살짝 눌린다.
CC = lambda a, y, k: pose((0,y,0),(-0.14,0,0),sq(k),(0.75,0,0.3),(a,0,-0.12))
anim('cook_chop', 0.48, [(0, CC(1.32,-0.03,0.01)), (0.12, CC(1.0,-0.03,0)), (0.16, CC(0.8,-0.04,-0.025)), (0.22, CC(0.86,-0.035,-0.01)),
 (0.34, CC(1.25,-0.03,0.01)), (0.48, CC(1.32,-0.03,0.01))], loop=True)
# cook_stir: 왼손으로 손잡이를 잡고 오른손으로 휘휘 젓는다. 몸이 손을 따라 조금 늦게 원을 그린다.
ST = lambda z, w, y: pose((0,y,0),(-0.08,0,0.03*w),(1,1,1),(0.85,0,0.2),(1.0+0.08*w,0.25*z,-0.1+0.3*z))
anim('cook_stir', 0.8, [(0, ST(-1,0,0)), (0.2, ST(0,-1,0.01)), (0.4, ST(1,0,0)), (0.6, ST(0,1,0.01)), (0.8, ST(-1,0,0))], loop=True)
# cook_flip: 무릎을 살짝 굽혔다가(예비) 팬을 휙 들어 올리고, 잠깐 기다렸다(뒤집힌 재료가 떨어짐) 받아 낸다
FL = lambda a, y, rx, k: pose((0,y,0),(rx,0,0),sq(k),(a,0,0.18),(a,0,-0.18))
anim('cook_flip', 0.7, [(0, FL(0.85,0,-0.12,0)), (0.1, FL(0.75,-0.02,-0.15,-0.03)), (0.2, FL(1.45,0.05,-0.03,0.04)),
 (0.32, FL(1.38,0.05,-0.05,0.02)), (0.44, FL(0.8,-0.01,-0.13,-0.02)), (0.56, FL(0.88,0,-0.12,0)), (0.7, FL(0.85,0,-0.12,0))], loop=True)
# cook_mix: 왼팔로 그릇을 안고 오른손으로 빠르게 섞는다
MX = lambda z: pose((0,0,0),(-0.1,0,0.03*z),(1,1,1),(0.95,0,0.42),(1.05,0,-0.2+0.28*z))
anim('cook_mix', 0.3, [(0, MX(-1)), (0.08, MX(-0.2)), (0.15, MX(1)), (0.23, MX(0.2)), (0.3, MX(-1))], loop=True)
# cook_plate: 두 손으로 접시를 받쳐 살며시 내려놓는다
PL = lambda x, y: pose((0,y,0),(-0.1,0,0),(1,1,1),(x,0,0.22),(x,0,-0.22))
anim('cook_plate', 1.0, [(0, PL(1.25,0)), (0.35, PL(1.0,-0.015)), (0.5, PL(0.95,-0.02)), (0.65, PL(1.0,-0.015)), (1.0, PL(1.25,0))], loop=True)
COOKS=['cook_chop','cook_stir','cook_flip','cook_mix','cook_plate']
# dig: 삽을 들어(예비) 땅에 꽂고 → 발로 밟아 깊이(몸이 눌림) → 허리를 펴며 흙을 퍼 올림(늘어남) → 털어 내고 제자리
# 삽은 도끼 자리(Axe)에 들고 다녀서(날이 위·앞) 손목 트랙(axe)으로 삽을 뒤집어 날을 땅에 꽂고, 퍼 올릴 때 수평으로 눕힌다.
DG = lambda vy, rx, a, ll, k, t: pose((0,vy,0),(rx,0,0),sq(k),(a,0,0.15),(a+0.15,0,-0.12),(ll,0,0),(0,0,0),axe=t)
anim('dig', 0.8, [(0, REST), (0.08, DG(0.02,0.08,1.0,0.0,0.03,-1.6)), (0.2, DG(-0.06,-0.34,0.5,0.35,-0.04,-2.9)), (0.32, DG(-0.11,-0.44,0.33,0.0,-0.07,-2.85)),
 (0.48, DG(0.02,-0.06,1.3,0.0,0.05,-3.0)), (0.56, DG(0.0,-0.1,1.15,0.0,0.0,-2.7)), (0.8, REST)], lag=TOOL_LAG)
# sit: 의자에 앉아 두 다리를 앞으로 쭉 (작은 몸이라 발이 바닥에 안 닿는다), 다리를 번갈아 달랑달랑
SI = lambda rz, y, a, b: pose((0,y,0),(0.04,0,rz),(1,1,1),(0.5,0,0.08),(0.5,0,-0.08),(1.5+a,0,0.05),(1.5+b,0,-0.05))
anim('sit', 2.4, [(0, SI(0,0,0,0)), (0.6, SI(0.04,0.008,0.15,-0.1)), (1.2, SI(0,0,0,0)), (1.8, SI(-0.04,0.008,-0.1,0.15)), (2.4, SI(0,0,0,0))], loop=True)
# rummage (v0.12): 가방을 열면 주머니를 뒤진다. 고개를 숙여 오른쪽 주머니를 내려다보며 오른손을 넣어 휘적휘적,
#                  왼손은 옆구리 주머니를 툭툭 두드려 본다. 가끔 고개를 들어 갸웃 (반복).
RM = lambda y, rx, ry, rz, k, al, ar: pose((0,y,0),(rx,ry,rz),sq(k),al,ar,(0,0,0.03),(0,0,-0.03))
anim('rummage', 1.6, [
 (0, RM(-0.015,-0.2,-0.28,0.06,-0.01,(0.12,0,-0.05),(0.12,0,0.02))),
 (0.2, RM(-0.025,-0.24,-0.3,0.07,-0.02,(0.2,0,-0.02),(0.32,0,-0.08))),
 (0.4, RM(-0.015,-0.21,-0.26,0.05,-0.01,(0.08,0,-0.08),(0.05,0,0.06))),
 (0.6, RM(-0.025,-0.25,-0.31,0.07,-0.02,(0.18,0,-0.03),(0.36,0,-0.1))),
 (0.8, RM(-0.015,-0.2,-0.27,0.06,-0.01,(0.1,0,-0.06),(0.1,0,0.04))),
 (1.05, RM(0.0,-0.1,-0.12,-0.04,0.01,(0.15,0,-0.1),(0.42,0,-0.14))),
 (1.3, RM(-0.01,-0.14,-0.18,-0.02,0.0,(0.12,0,-0.08),(0.38,0,-0.12))),
 (1.6, RM(-0.015,-0.2,-0.28,0.06,-0.01,(0.12,0,-0.05),(0.12,0,0.02)))], loop=True)

# phone (v0.14): 휴대폰을 오른손에 들고 가슴 앞에서 내려다본다. 왼손은 화면 위에 띄워 두고(누를 준비),
#               숨 쉬듯 살짝 오르내리며 가끔 고개를 갸웃.
PH = lambda y, rx, rz, k, al, ar: pose((0,y,0),(rx,0,rz),sq(k),al,ar,(0,0,0.02),(0,0,-0.02))
PH_AL=(1.2,0,0.55); PH_AR=(1.42,0,-0.66)
anim('phone', 2.8, [
 (0, PH(0,-0.3,0,0,PH_AL,PH_AR)),
 (0.7, PH(-0.006,-0.31,0.015,-0.01,(1.22,0,0.56),(1.44,0,-0.66))),
 (1.4, PH(0,-0.29,0.03,0.006,(1.18,0,0.54),(1.41,0,-0.65))),
 (2.1, PH(-0.006,-0.31,0.012,-0.01,(1.21,0,0.56),(1.43,0,-0.67))),
 (2.8, PH(0,-0.3,0,0,PH_AL,PH_AR))], loop=True)
# phone_tap: 화면을 톡 — 왼손 검지가 앞으로 찌르고, 휴대폰을 든 오른손이 눌린 만큼 살짝 밀렸다가 파르르 떨며 제자리.
#            고개도 아주 조금 끄덕 (0.26초).
anim('phone_tap', 0.26, [
 (0, PH(0,-0.3,0,0,PH_AL,PH_AR)),
 (0.05, PH(-0.003,-0.31,0,-0.005,(1.32,0,0.63),(1.4,0,-0.65))),
 (0.08, PH(-0.006,-0.32,0,-0.01,(1.38,0,0.66),(1.32,0,-0.62))),
 (0.12, PH(-0.003,-0.31,0.008,-0.004,(1.3,0,0.61),(1.47,0,-0.7))),
 (0.16, PH(0,-0.3,-0.006,0,(1.24,0,0.57),(1.39,0,-0.64))),
 (0.2, PH(0,-0.3,0.003,0,(1.21,0,0.56),(1.435,0,-0.67))),
 (0.26, PH(0,-0.3,0,0,PH_AL,PH_AR))], lag=(0.0,0.0,0.0,0.0))

# ---- 탈것 (v0.15) ----
# ride_bike: 안장에 앉아 몸을 앞으로 숙이고 두 손은 핸들, 발은 페달 원을 따라 돈다 (한 바퀴 = 1초, 리그가 빠르기를 바퀴 속도에 맞춘다).
#            허벅지·정강이 각도는 페달 자리에서 두 마디 역기구학(IK)으로 구해 12 칸으로 나눈다 → 무릎이 자연스럽게 오르내린다.
import math
CRANK=(-0.26,-0.07)   # 골반 관절 기준 크랭크 가운데 (y, z) — z 가 음수면 앞
CRANK_R=0.075
def leg_ik(y, z):
    d=math.hypot(y,z)
    phi=math.atan2(-z,-y)  # 아래에서 앞으로 잰 각
    a=math.acos(max(-1.0,min(1.0,(THIGH*THIGH+d*d-SHIN*SHIN)/(2*THIGH*d))))
    b=math.acos(max(-1.0,min(1.0,(THIGH*THIGH+SHIN*SHIN-d*d)/(2*THIGH*SHIN))))
    return phi+a, -(math.pi-b)
def pedal(angle):
    return CRANK[0]+CRANK_R*math.cos(angle), CRANK[1]+CRANK_R*math.sin(angle)
# 검산: 허벅지 · 정강이로 되짚어 페달 자리에 닿는지.
for k in range(8):
    py,pz=pedal(k*math.pi/4)
    t1,t2=leg_ik(py,pz)
    ky,kz=-THIGH*math.cos(t1),-THIGH*math.sin(t1)
    fy,fz=ky-SHIN*math.cos(t1+t2),kz-SHIN*math.sin(t1+t2)
    assert abs(fy-py)<1e-6 and abs(fz-pz)<1e-6,(k,fy,py,fz,pz)
N=12
bike=[]
for i in range(N+1):
    ang=2*math.pi*i/N
    l1,l2=leg_ik(*pedal(ang)); r1,r2=leg_ik(*pedal(ang+math.pi))
    bob=0.006*math.cos(2*ang)
    rock=0.035*math.sin(ang)
    bike.append((round(i/N,4), pose((0,bob,0),(-0.34,0,rock),(1,1,1),(1.12,0,AL-0.12),(1.12,0,AR+0.12),(round(l1,4),0,0),(round(r1,4),0,0),
                                    kl=round(l2,4),kr=round(r2,4),el=0.42,er=0.42)))
anim('ride_bike', 1.0, bike, loop=True)
# ride_moto: 시트에 앉아 발은 발판, 두 손은 핸들. 모터 진동처럼 아주 작게 떨리고 숨 쉬듯 오르내린다.
MO = lambda y, rz: pose((0,y,0),(-0.18,0,rz),(1,1,1),(1.05,0,AL-0.2),(1.05,0,AR+0.2),(1.2,0,0.08),(1.2,0,-0.08),kl=-1.3,kr=-1.3,el=0.5,er=0.5)
anim('ride_moto', 1.6, [(0, MO(0,0)), (0.4, MO(0.004,0.01)), (0.8, MO(0,0)), (1.2, MO(0.004,-0.01)), (1.6, MO(0,0))], loop=True)
# ---- 킥보드 (v0.16) ----
# 발판(바닥 위 DECK_H) 위에 왼발을 앞, 오른발을 뒤에 두고 서서 두 손은 핸들. 발 자리는 골반 관절 기준 (y 아래가 음수, z 앞이 음수)으로
# 정하고 두 마디 IK 로 허벅지 · 정강이 각도를 푼다. 몸(Visual)을 LIFT 만큼 올리면 발판 위, 내리면 무릎이 굽는다.
DECK_H=0.095
LEG=THIGH+SHIN
def on_deck(lift, z):
    """몸을 lift 만큼 올렸을 때 발판 위 z 자리의 발 (골반 관절 기준)."""
    return (round(-LEG+(DECK_H-lift),4), z)
def on_ground(lift, z):
    return (round(-LEG-lift,4), z)
def KB(lift, rx, rz, lfoot, rfoot, el=0.5, er=0.5, ry=0.0, lr_out=0.0, al=None, ar=None):
    l1,l2=leg_ik(*lfoot); r1,r2=leg_ik(*rfoot)
    return pose((0,lift,0),(rx,ry,rz),(1,1,1),al or (1.12,0,0.1),ar or (1.12,0,-0.1),(round(l1,4),0,0),(round(r1,4),0,lr_out),
                kl=round(l2,4),kr=round(r2,4),el=el,er=er)
KL=0.075  # 발판 위에 선 몸 높이 (무릎을 살짝 굽힌다)
FRONT=-0.07; BACK=0.11  # 앞발 · 뒷발 자리
# ride_kick: 발판 위에서 미끄러져 가는 자세. 숨 쉬듯 살짝 오르내리고 몸이 좌우로 아주 조금 흔들린다.
anim('ride_kick', 2.0, [(round(t,3), KB(KL+0.006*math.sin(t*math.pi), -0.12, 0.015*math.sin(t*math.pi), on_deck(KL+0.006*math.sin(t*math.pi),FRONT), on_deck(KL+0.006*math.sin(t*math.pi),BACK)))
                        for t in [0.0,0.5,1.0,1.5,2.0]], loop=True)
# ride_kick_brake: 뒷발 뒤꿈치로 뒷바퀴 흙받이를 꾹 밟고 몸을 살짝 뒤로 젖힌다 (잘게 떨리며 멈춘다).
FENDER=(0.13, 0.25)  # 흙받이 높이 · 자리
BK = lambda d: KB(0.06, 0.04+d, 0.0, on_deck(0.06,FRONT-0.02), (round(-LEG+(FENDER[0]-0.06),4), FENDER[1]), el=0.3, er=0.3)
anim('ride_kick_brake', 0.3, [(0, BK(0)), (0.1, BK(0.012)), (0.2, BK(-0.006)), (0.3, BK(0))], loop=True)
# kick: 한 번 땅 차기 (0.62초). 서 있는 무릎을 굽혀 몸을 낮추며(예비) 뒷발을 앞쪽 땅에 디뎌 →
#       뒤로 쭉 밀고(이때 앞으로 나간다 · vehicles.json kick_push) → 발끝으로 차고 들어 올려 → 발판 위로 돌아온다.
#       미는 동안 몸을 더 숙이고 팔꿈치가 굽는다.
KK=[(0.0, KL, -0.12, on_deck(KL,BACK), 0.5, 0.0),
    (0.1, 0.05, -0.15, (-0.27, 0.0), 0.55, 0.14),
    (0.2, -0.005, -0.2, on_ground(-0.005,-0.02), 0.7, 0.15),
    (0.31, -0.012, -0.22, on_ground(-0.012,0.11), 0.72, 0.13),
    (0.42, 0.01, -0.2, (-0.31, 0.24), 0.65, 0.11),
    (0.5, 0.045, -0.16, (-0.22, 0.25), 0.55, 0.09),
    (0.62, KL, -0.12, on_deck(KL,BACK), 0.5, 0.0)]
anim('kick', 0.62, [(t, KB(lift, rx, 0.0, on_deck(lift,FRONT), rf, el=e, er=e, lr_out=out)) for t,lift,rx,rf,e,out in KK])
RIDES=['ride_bike','ride_moto','ride_kick','ride_kick_brake']

# ---- 허리 · 목 나누기 (v0.13) ----
# 예전에는 몸 전체(Visual)가 한 덩어리로 기울어 뻣뻣해 보였다. 몸통 회전을 골반(Visual) · 허리 · 목에 나눠 맡긴다:
# 숙이기·젖히기(x) 는 골반 45% · 허리 35% · 목 20%, 비틀기(y) 는 40 · 40 · 20, 갸웃(z) 은 50 · 30 · 20.
# 목은 허리보다 조금 늦게(따라가기), 허리는 골반보다 조금 늦게 움직여 끝동작이 부드럽게 흐른다.
SHARE=((0.45,0.4,0.5),(0.35,0.4,0.3),(0.2,0.2,0.2))
SPINE_LAG=(0.02,0.055)  # 허리 · 목이 골반보다 늦는 시간 (반복 동작은 늦추지 않는다)
# 걷기·달리기: 팔과 반대로 허리를 비틀고(어깨가 앞으로 나온 팔 쪽으로) 목은 반대로 돌려 시선을 앞에 둔다.
TWIST={'walk':0.07,'run':0.11}
def split_spine():
    for name,a in anims.items():
        R=a['keys'][1]
        a['keys'][1]=[V(r[0]*SHARE[0][0],r[1]*SHARE[0][1],r[2]*SHARE[0][2]) for r in R]
        waist=[V(r[0]*SHARE[1][0],r[1]*SHARE[1][1],r[2]*SHARE[1][2]) for r in R]
        neck=[V(r[0]*SHARE[2][0],r[1]*SHARE[2][1],r[2]*SHARE[2][2]) for r in R]
        if name in TWIST:
            # ArmR 가 앞으로(+x) 나온 만큼 오른쪽 어깨가 앞으로 (+y).
            arm=a['keys'][4]
            m=max(abs(k[0]) for k in arm) or 1.0
            waist=[V(w[0],w[1]+TWIST[name]*k[0]/m,w[2]) for w,k in zip(waist,arm)]
            neck=[V(n[0],n[1]-0.6*TWIST[name]*k[0]/m,n[2]) for n,k in zip(neck,arm)]
        if name=='idle':
            # 숨 쉴 때 고개가 살짝 끄덕인다.
            neck=[V(n[0]+d,n[1],n[2]) for n,d in zip(neck,[0,0.03,0.0,0.03,0])]
        a['keys'].append(waist)
        a['keys'].append(neck)
        if 'ttimes' in a:
            n=len(a['times'])
            for lag in SPINE_LAG:
                ts=[]
                for j,t in enumerate(a['times']):
                    ts.append(t if (j==0 or j==n-1 or a['loop']) else round(min(t+lag,a['length']-0.012*(n-1-j)),4))
                a['ttimes'].append(ts)
split_spine()
TRACKS=TRACKS+SPINE_TRACKS

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
        ts=a['ttimes'][i] if 'ttimes' in a else a['times']
        out.append('"times": PackedFloat32Array(%s),'%', '.join(str(t) for t in ts))
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
''' + ',\n'.join('&"%s": SubResource("Animation_%s")'%(n,n) for n in ['brake','show','plant']+EMOTES+COOKS+['sit','dig','rummage','phone','phone_tap']+RIDES+['kick']) + '''
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
''' + ''.join('[sub_resource type="AnimationNodeAnimation" id="AN_%s"]\nanimation = &"%s"\n\n'%(e,e) for e in COOKS+['sit','dig','rummage','phone','phone_tap']+RIDES+['kick']) + '''[sub_resource type="AnimationNodeTransition" id="Transition_ride"]
xfade_time = 0.15
''' + ''.join('input_%d/name = "%s"\ninput_%d/auto_advance = false\ninput_%d/break_loop_at_end = false\ninput_%d/reset = false\n'%(i,e,i,i,i) for i,e in enumerate(RIDES)) + '''
[sub_resource type="AnimationNodeTimeScale" id="TimeScale_ride"]

[sub_resource type="AnimationNodeBlend2" id="Blend2_ride"]

[sub_resource type="AnimationNodeOneShot" id="OneShot_dig"]
fadein_time = 0.06
fadeout_time = 0.12

[sub_resource type="AnimationNodeOneShot" id="OneShot_kick"]
fadein_time = 0.08
fadeout_time = 0.1

[sub_resource type="AnimationNodeTransition" id="Transition_cook"]
xfade_time = 0.12
''' + ''.join('input_%d/name = "%s"\ninput_%d/auto_advance = false\ninput_%d/break_loop_at_end = false\ninput_%d/reset = true\n'%(i,e,i,i,i) for i,e in enumerate(COOKS)) + '''
[sub_resource type="AnimationNodeBlend2" id="Blend2_cook"]

[sub_resource type="AnimationNodeBlend2" id="Blend2_sit"]

[sub_resource type="AnimationNodeBlend2" id="Blend2_rummage"]

[sub_resource type="AnimationNodeBlend2" id="Blend2_phone"]

[sub_resource type="AnimationNodeOneShot" id="OneShot_phone_tap"]
fadein_time = 0.03
fadeout_time = 0.05

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
''' + ''.join('nodes/R_%s/node = SubResource("AN_%s")\nnodes/R_%s/position = Vector2(-300, %d)\n'%(e,e,e,320+i*60) for i,e in enumerate(RIDES)) + '''nodes/RideSwitch/node = SubResource("Transition_ride")
nodes/RideSwitch/position = Vector2(-200, 320)
nodes/RideScale/node = SubResource("TimeScale_ride")
nodes/RideScale/position = Vector2(-150, 320)
nodes/RideBlend/node = SubResource("Blend2_ride")
nodes/RideBlend/position = Vector2(-50, 0)
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
nodes/Rummage/node = SubResource("AN_rummage")
nodes/Rummage/position = Vector2(270, 200)
nodes/RummageBlend/node = SubResource("Blend2_rummage")
nodes/RummageBlend/position = Vector2(295, 40)
nodes/Phone/node = SubResource("AN_phone")
nodes/Phone/position = Vector2(295, 200)
nodes/PhoneBlend/node = SubResource("Blend2_phone")
nodes/PhoneBlend/position = Vector2(305, 40)
nodes/PhoneTap/node = SubResource("AN_phone_tap")
nodes/PhoneTap/position = Vector2(305, 200)
nodes/PhoneTapShot/node = SubResource("OneShot_phone_tap")
nodes/PhoneTapShot/position = Vector2(312, 40)
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
nodes/Kick/node = SubResource("AN_kick")
nodes/Kick/position = Vector2(-120, 420)
nodes/KickShot/node = SubResource("OneShot_kick")
nodes/KickShot/position = Vector2(-60, 320)
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
node_connections = [&"BrakeBlend", 0, &"Locomotion", &"BrakeBlend", 1, &"Brake", ''' + ''.join('&"RideSwitch", %d, &"R_%s", '%(i,e) for i,e in enumerate(RIDES)) + '''&"RideScale", 0, &"RideSwitch", &"RideBlend", 0, &"BrakeBlend", &"KickShot", 0, &"RideScale", &"KickShot", 1, &"Kick", &"RideBlend", 1, &"KickShot", &"FishBlend", 0, &"RideBlend", &"FishBlend", 1, &"Fishing", ''' + ''.join('&"CookSwitch", %d, &"K_%s", '%(i,e) for i,e in enumerate(COOKS)) + '''&"CookBlend", 0, &"FishBlend", &"CookBlend", 1, &"CookSwitch", &"SitBlend", 0, &"CookBlend", &"SitBlend", 1, &"Sit", &"RummageBlend", 0, &"SitBlend", &"RummageBlend", 1, &"Rummage", &"PhoneBlend", 0, &"RummageBlend", &"PhoneBlend", 1, &"Phone", &"PhoneTapShot", 0, &"PhoneBlend", &"PhoneTapShot", 1, &"PhoneTap", &"ChopShot", 0, &"PhoneTapShot", &"ChopShot", 1, &"Chop", &"CastShot", 0, &"ChopShot", &"CastShot", 1, &"Cast", &"PlantShot", 0, &"CastShot", &"PlantShot", 1, &"Plant", ''' + ''.join('&"EmoteSwitch", %d, &"E_%s", '%(i,e) for i,e in enumerate(EMOTES)) + '''&"DigShot", 0, &"PlantShot", &"DigShot", 1, &"Dig", &"EmoteShot", 0, &"DigShot", &"EmoteShot", 1, &"EmoteSwitch", &"ShowBlend", 0, &"EmoteShot", &"ShowBlend", 1, &"Show", &"output", 0, &"ShowBlend"]

[node name="Rig" type="Node3D" node_paths=PackedStringArray("tree", "visual", "body_mesh", "hips_mesh", "head_mesh", "waist", "upper", "neck", "head", "arm_left", "arm_right", "leg_left", "leg_right", "elbow_left", "elbow_right", "knee_left", "knee_right", "rod", "axe", "tool")]
script = ExtResource("1_rig")
tree = NodePath("AnimationTree")
visual = NodePath("Visual")
body_mesh = NodePath("Visual/Waist/Upper/Body")
hips_mesh = NodePath("Visual/Hips")
head_mesh = NodePath("Visual/Waist/Upper/Neck/Head/HeadMesh")
waist = NodePath("Visual/Waist")
upper = NodePath("Visual/Waist/Upper")
neck = NodePath("Visual/Waist/Upper/Neck")
head = NodePath("Visual/Waist/Upper/Neck/Head")
arm_left = NodePath("Visual/Waist/Upper/ArmL")
arm_right = NodePath("Visual/Waist/Upper/ArmR")
leg_left = NodePath("Visual/LegL")
leg_right = NodePath("Visual/LegR")
elbow_left = NodePath("Visual/Waist/Upper/ArmL/ElbowL")
elbow_right = NodePath("Visual/Waist/Upper/ArmR/ElbowR")
knee_left = NodePath("Visual/LegL/KneeL")
knee_right = NodePath("Visual/LegR/KneeR")
rod = NodePath("Visual/Waist/Upper/ArmR/ElbowR/Rod")
axe = NodePath("Visual/Waist/Upper/ArmR/ElbowR/Axe")
tool = NodePath("Visual/Waist/Upper/ArmR/ElbowR/Tool")
clay_material = ExtResource("2_clay")

[node name="Visual" type="Node3D" parent="."]

[node name="Hips" type="MeshInstance3D" parent="Visual"]

[node name="Waist" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(WAIST_Y) + ''', 0)

[node name="Upper" type="Node3D" parent="Visual/Waist"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(-WAIST_Y) + ''', 0)

[node name="Body" type="MeshInstance3D" parent="Visual/Waist/Upper"]

[node name="Neck" type="Node3D" parent="Visual/Waist/Upper"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(NECK_Y) + ''', 0)

[node name="Head" type="Node3D" parent="Visual/Waist/Upper/Neck"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(-NECK_Y) + ''', 0)

[node name="HeadMesh" type="MeshInstance3D" parent="Visual/Waist/Upper/Neck/Head"]

[node name="ArmL" type="Node3D" parent="Visual/Waist/Upper"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.23, -0.05, 0)

[node name="ArmR" type="Node3D" parent="Visual/Waist/Upper"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.23, -0.05, 0)

[node name="ElbowL" type="Node3D" parent="Visual/Waist/Upper/ArmL"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(ELBOW_Y) + ''', 0)

[node name="ElbowR" type="Node3D" parent="Visual/Waist/Upper/ArmR"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(ELBOW_Y) + ''', 0)

[node name="Rod" type="Node3D" parent="Visual/Waist/Upper/ArmR/ElbowR"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(round(-0.3-ELBOW_Y,4)) + ''', 0)

[node name="Axe" type="Node3D" parent="Visual/Waist/Upper/ArmR/ElbowR"]
visible = false
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(round(-0.3-ELBOW_Y,4)) + ''', 0)

[node name="Tool" type="Node3D" parent="Visual/Waist/Upper/ArmR/ElbowR"]
visible = false
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(round(-0.3-ELBOW_Y,4)) + ''', 0)

[node name="LegL" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.1, -0.42, 0)

[node name="KneeL" type="Node3D" parent="Visual/LegL"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(KNEE_Y) + ''', 0)

[node name="LegR" type="Node3D" parent="Visual"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.1, -0.42, 0)

[node name="KneeR" type="Node3D" parent="Visual/LegR"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ''' + str(KNEE_Y) + ''', 0)

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
parameters/KickShot/active = false
parameters/KickShot/internal_active = false
parameters/KickShot/request = 0
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
parameters/RummageBlend/blend_amount = 0.0
parameters/PhoneBlend/blend_amount = 0.0
parameters/PhoneTapShot/active = false
parameters/PhoneTapShot/internal_active = false
parameters/PhoneTapShot/request = 0
parameters/RideBlend/blend_amount = 0.0
parameters/RideScale/scale = 1.0
parameters/RideSwitch/current_state = "ride_bike"
parameters/RideSwitch/transition_request = ""
parameters/RideSwitch/current_index = 0
''')
open(OUT,'w').write('\n'.join(out))
print('ok')
