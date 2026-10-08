#!/usr/bin/env python3
"""차고 탈것 데이터(data/vehicles/garage.json)를 만든다: 자전거 · 전기오토바이 모델과 꾸미기 부품.

- 값(솔)은 원과 같은 단위라 실제 시세에 맞춘다 (생활 자전거 20만 원대 · 로드 200만 원대 · 전기 스쿠터 200만 원대 · 125cc급 전기오토바이 600만 원대).
- 성능(top m/s · accel m/s² · brake m/s² · coast m/s² · turn rad/s)은 서버(이동 속도 검사)와 클라이언트(주행)가 같이 쓴다.
- 부품 slot 하나에 하나씩 끼운다. 산 부품은 그 탈것에 남아 다시 끼울 때는 공짜다.
- 액세서리 model 은 PartMesh 도형 목록(game/props/part_mesh.gd)이고 anchor(탈것마다 정한 자리) 기준이다.
  색 자리 "$paint" · "$trim" · "$seat" 는 탈것을 빚을 때 고른 색으로 바뀐다.
- anchors: 탈것 좌표(바닥 y = 0, 앞 = -z). 핸들(bar)은 타는 자세의 손 자리(gen_character_rig.py ride_bike · ride_moto)에 맞췄다.
사용: python3 tools/art/gen_vehicles.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/vehicles/garage.json'


def r3(v):
    return [round(float(x), 4) for x in v]


def part(s, size, at, c, **kw):
    d = {'s': s, 'size': r3(size) if isinstance(size, (list, tuple)) else [size], 'at': r3(at), 'c': c}
    for k, v in kw.items():
        d[k] = r3(v) if isinstance(v, (list, tuple)) else v
    return d


BIKE_ANCHORS = {
    'bar': [0.0, 0.79, -0.31], 'front': [0.0, 0.66, -0.56], 'rear': [0.0, 0.52, 0.4], 'seat': [0.0, 0.48, 0.08],
    'frame': [0.0, 0.47, -0.2], 'head': [0.0, 0.66, -0.47], 'tail': [0.0, 0.44, 0.62], 'axle_f': [0.0, 0.28, -0.6], 'axle_r': [0.0, 0.28, 0.42],
}
MINI_ANCHORS = dict(BIKE_ANCHORS, **{'front': [0.0, 0.64, -0.54], 'rear': [0.0, 0.46, 0.38], 'tail': [0.0, 0.4, 0.56],
                                     'axle_f': [0.0, 0.22, -0.56], 'axle_r': [0.0, 0.22, 0.38]})
SCOOTER_ANCHORS = {
    'bar': [0.0, 0.78, -0.3], 'front': [0.0, 0.6, -0.5], 'rear': [0.0, 0.5, 0.44], 'seat': [0.0, 0.44, 0.14],
    'frame': [0.0, 0.36, -0.36], 'head': [0.0, 0.66, -0.47], 'tail': [0.0, 0.44, 0.7], 'axle_f': [0.0, 0.22, -0.62], 'axle_r': [0.0, 0.22, 0.48],
    'floor': [0.0, 0.2, -0.1],
}
SPORT_ANCHORS = dict(SCOOTER_ANCHORS, **{'bar': [0.0, 0.79, -0.3], 'front': [0.0, 0.64, -0.52], 'rear': [0.0, 0.53, 0.46], 'seat': [0.0, 0.45, 0.16],
                                         'frame': [0.0, 0.5, -0.12], 'head': [0.0, 0.62, -0.56], 'tail': [0.0, 0.5, 0.74],
                                         'axle_f': [0.0, 0.25, -0.68], 'axle_r': [0.0, 0.25, 0.52], 'floor': [0.0, 0.22, -0.1]})

# ---- 모델 ----
# style: 몸체 모양 (VehicleModel 이 빚는다) · wheel: 바퀴 반지름(m) · lift: 타는 동안 캐릭터를 올리는 높이.
# pedal: 바퀴 한 바퀴에 페달이 도는 수의 역수 (기어비) — 페달 빠르기 = 속도 / (2πr) / gear.
MODELS = [
    dict(id='bike_city', kind='bike', style='city', name='솔바람 시티 26', type='생활 자전거', price=239000,
         spec='7단 · 26인치 · 16.4kg', desc='바구니 달기 좋은 낮은 프레임. 장 보러 가기 딱 좋다.',
         top=6.2, accel=2.1, brake=4.6, coast=0.22, turn=2.6, wheel=0.28, gear=2.2, lift=0.16,
         paint='#7EC4C8', trim='#F2EEE4', seat='#5A4636', anchors=BIKE_ANCHORS),
    dict(id='bike_mini', kind='bike', style='mini', name='포켓 미니벨로 20', type='미니벨로', price=459000,
         spec='8단 · 20인치 · 11.2kg', desc='작은 바퀴로 경쾌하게 출발한다. 골목길에서 잘 돈다.',
         top=6.5, accel=2.6, brake=4.8, coast=0.26, turn=3.0, wheel=0.22, gear=2.6, lift=0.16,
         paint='#F2B6A0', trim='#3A3A40', seat='#3A3330', anchors=MINI_ANCHORS),
    dict(id='bike_mtb', kind='bike', style='mtb', name='트레일 MTB 27.5', type='산악 자전거', price=790000,
         spec='12단 · 27.5인치 · 앞 서스펜션 · 13.8kg', desc='굵은 타이어와 서스펜션. 여울과 풀밭에서도 덜 느려진다.',
         top=7.0, accel=2.6, brake=5.4, coast=0.3, turn=2.5, wheel=0.29, gear=2.3, lift=0.17, wade=0.8,
         paint='#3D8F5A', trim='#1F1F22', seat='#232326', anchors=BIKE_ANCHORS),
    dict(id='bike_road', kind='bike', style='road', name='에어로 로드 700C', type='로드 자전거', price=2490000,
         spec='22단 · 카본 프레임 · 8.1kg', desc='가볍고 빠른 카본 자전거. 호수 둘레길을 바람처럼 달린다.',
         top=8.6, accel=2.9, brake=5.0, coast=0.16, turn=2.2, wheel=0.3, gear=2.0, lift=0.17,
         paint='#E0484A', trim='#F7F5F0', seat='#232326', anchors=BIKE_ANCHORS),
    dict(id='moto_scooter', kind='moto', style='scooter', name='솔바람 E-스쿠터', type='전기 스쿠터 (50cc급)', price=2390000,
         spec='1.5kW 허브 모터 · 최고 45km/h · 60V 리튬', desc='발판이 넓은 작은 스쿠터. 조용하고 부드럽게 출발한다.',
         top=11.0, accel=2.9, brake=6.0, coast=0.35, turn=2.3, wheel=0.22, lift=0.12, regen=1.1,
         paint='#F3E6C8', trim='#8C6A4A', seat='#6B4A36', anchors=SCOOTER_ANCHORS),
    dict(id='moto_classic', kind='moto', style='classic', name='레트로 E-클래식', type='클래식 전기 오토바이 (110cc급)', price=4290000,
         spec='3kW 미드 모터 · 최고 65km/h · 72V 리튬', desc='둥근 전조등과 갈색 시트의 옛날 오토바이 모양. 힘이 넉넉하다.',
         top=13.0, accel=3.5, brake=6.4, coast=0.32, turn=2.15, wheel=0.24, lift=0.12, regen=1.3,
         paint='#2F5A4A', trim='#D8B878', seat='#7A4E30', anchors=SPORT_ANCHORS),
    dict(id='moto_sport', kind='moto', style='sport', name='볼트 E-스포츠 125', type='전기 오토바이 (125cc급)', price=6890000,
         spec='5kW 미드 모터 · 최고 90km/h · 72V 리튬 · ABS', desc='날렵한 카울의 125cc급 전기 오토바이. 스로틀을 감으면 쭉 밀어 준다.',
         top=15.0, accel=4.3, brake=7.2, coast=0.3, turn=2.05, wheel=0.25, lift=0.12, regen=1.5,
         paint='#2F62C8', trim='#F2EEE4', seat='#232326', anchors=SPORT_ANCHORS),
]

# ---- 부품 ----
PAINTS = [
    ('cream', '크림', '#F3E6C8', 0), ('mint', '민트', '#8FD8C0', 0), ('sky', '하늘', '#8CC8F0', 0), ('cherry', '체리 레드', '#E0484A', 0),
    ('sunset', '선셋 오렌지', '#F28A3A', 0), ('lemon', '레몬', '#F5D547', 0), ('lavender', '라벤더', '#B49BE0', 0), ('blossom', '벚꽃', '#F5B6C8', 0),
    ('olive', '올리브', '#8A9A4A', 0), ('navy', '네이비', '#2F4A7A', 0), ('charcoal', '차콜', '#3A3A40', 0), ('racing', '레이싱 그린', '#1F5A3A', 0),
    ('pearl', '펄 화이트', '#F7F5F0', 1), ('matte', '무광 블랙', '#232326', 1), ('gold', '샴페인 골드', '#D8B878', 1), ('chrome', '크롬 실버', '#C8CCD4', 1),
]
TRIMS = [('white', '화이트', '#F2EEE4'), ('black', '블랙', '#1F1F22'), ('gold', '골드', '#D8B060'), ('rose', '로즈골드', '#E0A090'),
         ('red', '레드', '#D8402F'), ('blue', '블루', '#3D7BD8'), ('mint', '민트', '#6CC8A8'), ('brown', '브라운', '#7A4E30')]
SEATS_COLOR = [('black', '블랙', '#232326'), ('brown', '브라운', '#7A4E30'), ('cream', '크림', '#EDE0C8'), ('red', '레드', '#B8322A')]

parts = []


def add(**kw):
    kw.setdefault('kinds', ['bike', 'moto'])
    parts.append(kw)


for pid, name, color, premium in PAINTS:
    add(id='paint_' + pid, slot='paint', name=name + (' (특수 도장)' if premium else ''), c=color,
        price={'bike': 69000 if premium else 39000, 'moto': 390000 if premium else 180000},
        desc='프레임 전체를 다시 칠한다.' if not premium else '광택·무광 특수 도장. 빛을 받으면 결이 달라 보인다.')
for pid, name, color in TRIMS:
    add(id='trim_' + pid, slot='trim', name=name + ' 포인트', c=color, price={'bike': 15000, 'moto': 60000},
        desc='림 · 핸들 · 포크 같은 포인트 부분의 색.')

# 조명: light = { range(m), energy, angle(°), color, lens(렌즈 반지름 배율), drl(주간주행등 고리) }. 밤에 SpotLight 로 앞을 비춘다.
add(id='light_led', slot='light', name='LED 전조등', price={'bike': 25000, 'moto': 79000},
    light={'range': 10.0, 'energy': 1.3, 'angle': 34.0, 'color': '#F4F6FF', 'lens': 1.1}, desc='밤길 10m 를 하얗게 비춘다.')
add(id='light_warm', slot='light', name='레트로 전구 램프', price={'bike': 45000, 'moto': 129000},
    light={'range': 12.0, 'energy': 1.4, 'angle': 40.0, 'color': '#FFD08A', 'lens': 1.35}, desc='크고 둥근 전구색 램프. 따뜻한 빛이 넓게 퍼진다.')
add(id='light_hi', slot='light', name='고휘도 LED 1200lm', price={'bike': 59000, 'moto': 189000},
    light={'range': 17.0, 'energy': 2.1, 'angle': 30.0, 'color': '#EEF3FF', 'lens': 1.2}, desc='멀리까지 쭉 뻗는 밝은 빛. 밤에 길이 훨씬 잘 보인다.')
add(id='light_proj', slot='light', kinds=['moto'], name='LED 프로젝션 + 주간주행등', price={'moto': 390000},
    light={'range': 22.0, 'energy': 2.6, 'angle': 28.0, 'color': '#F2F6FF', 'lens': 1.25, 'drl': True},
    desc='또렷한 빛 경계의 프로젝션 램프와 고리 모양 주간주행등.')
# 미등 · 반사.
add(id='tail_led', slot='tail', name='LED 깜빡이 미등', price={'bike': 12000, 'moto': 49000}, tail={'energy': 2.2, 'size': 1.3},
    desc='뒤에서 잘 보이는 밝은 빨간 미등.')
add(id='tail_bar', slot='tail', name='라이트 바 미등', price={'bike': 29000, 'moto': 99000}, tail={'energy': 2.8, 'size': 2.2},
    desc='가로로 긴 빛줄기 미등.')

# 성능: stats = 배율 { top, accel, brake, turn, wade }.
add(id='drive_gear7', slot='drive', kinds=['bike'], name='7단 변속기', price={'bike': 69000}, stats={'top': 1.06, 'accel': 1.04},
    desc='오르막과 내리막에 맞춰 기어를 바꾼다.')
add(id='drive_gear11', slot='drive', kinds=['bike'], name='11단 로드 구동계', price={'bike': 389000}, stats={'top': 1.13, 'accel': 1.07},
    desc='촘촘한 기어로 높은 속도를 오래 낸다.')
add(id='drive_assist', slot='drive', kinds=['bike'], name='전기 보조 키트 (PAS 250W)', price={'bike': 690000}, stats={'top': 1.16, 'accel': 1.45},
    desc='페달을 밟으면 모터가 거든다. 출발이 아주 가볍다.', model=[
        part('rbox', [0.07, 0.2, 0.06], [0.0, -0.06, 0.13], '#2A2A2E', rot=[-28, 0, 0], r=0.4),
        part('box', [0.072, 0.02, 0.062], [0.0, 0.035, 0.08], '#6CC8A8', rot=[-28, 0, 0]),
        part('cyl', [0.055, 0.05], [0.0, -0.18, 0.2], '#3A3A40', rot=[0, 0, 90])], anchor='frame')
add(id='drive_ctrl', slot='drive', kinds=['moto'], name='스포츠 컨트롤러 튜닝', price={'moto': 290000}, stats={'accel': 1.18},
    desc='모터 전류를 키워 출발과 추월이 빨라진다.')
add(id='drive_battery', slot='drive', kinds=['moto'], name='대용량 배터리 (72V 45Ah)', price={'moto': 890000}, stats={'top': 1.06, 'accel': 1.08},
    desc='전압이 높아 최고 속도까지 힘이 덜 빠진다.')
add(id='drive_motor', slot='drive', kinds=['moto'], name='고출력 모터 (+2kW)', price={'moto': 1190000}, stats={'top': 1.12, 'accel': 1.2},
    desc='더 큰 모터로 바꾼다. 최고 속도와 가속이 모두 오른다.')
add(id='brake_disc', slot='brake', kinds=['bike'], name='유압 디스크 브레이크', price={'bike': 159000}, stats={'brake': 1.35},
    desc='살짝 잡아도 확실하게 선다.')
add(id='brake_cbs', slot='brake', kinds=['moto'], name='CBS 연동 브레이크', price={'moto': 249000}, stats={'brake': 1.25},
    desc='앞뒤 브레이크가 함께 잡혀 안정적으로 선다.')
add(id='brake_abs', slot='brake', kinds=['moto'], name='ABS 브레이크', price={'moto': 590000}, stats={'brake': 1.5, 'turn': 1.04},
    desc='바퀴가 잠기지 않아 급제동에도 미끄러지지 않는다.')
# 타이어: tire = { c: 옆면 색, w: 폭 배율, tread: 깍두기 무늬 }.
add(id='tire_slick', slot='tire', name='슬릭 타이어', price={'bike': 59000, 'moto': 189000}, stats={'top': 1.04, 'turn': 1.05},
    tire={'c': '#2A2A2E', 'w': 0.85}, desc='매끈한 타이어. 포장길에서 잘 굴러간다.')
add(id='tire_knobby', slot='tire', name='블록 패턴 타이어', price={'bike': 69000, 'moto': 219000}, stats={'turn': 1.08, 'wade': 1.25},
    tire={'c': '#2A2A2E', 'w': 1.25, 'tread': True}, desc='울퉁불퉁한 블록 무늬. 물가와 풀밭에서 덜 미끄러진다.')
add(id='tire_white', slot='tire', name='화이트월 타이어', price={'bike': 49000, 'moto': 149000}, tire={'c': '#F2EEE4', 'w': 1.0},
    desc='옆면이 하얀 클래식 타이어.')
add(id='tire_sport', slot='tire', kinds=['moto'], name='스포츠 타이어', price={'moto': 239000}, stats={'turn': 1.15, 'accel': 1.03},
    tire={'c': '#2A2A2E', 'w': 1.1}, desc='접지력이 좋아 코너를 빠르게 돈다.')
# 안장 · 시트: seat = { c: 색, shape: soft|sport|quilt }.
for sid, name, color in SEATS_COLOR:
    add(id='seat_' + sid, slot='seat', name=name + ' 가죽 시트', price={'bike': 49000, 'moto': 190000}, seat={'c': color, 'shape': 'soft'},
        desc='부드러운 가죽 안장.')
add(id='seat_gel', slot='seat', kinds=['bike'], name='젤 컴포트 안장', price={'bike': 29000}, seat={'c': '#3A3A40', 'shape': 'wide'},
    desc='넓고 푹신한 안장.')
add(id='seat_quilt', slot='seat', kinds=['moto'], name='퀼팅 시트', price={'moto': 250000}, seat={'c': '#7A4E30', 'shape': 'quilt'},
    desc='누빔 무늬 가죽 시트.')
add(id='seat_sport', slot='seat', kinds=['moto'], name='스포츠 투톤 시트', price={'moto': 230000}, seat={'c': '#232326', 'shape': 'sport', 'c2': '$trim'},
    desc='포인트 색 줄이 들어간 날렵한 시트.')


def basket(c1, c2, flowers=False):
    out = [
        part('rbox', [0.3, 0.2, 0.22], [0.0, -0.02, -0.04], c1, r=0.18),
        part('box', [0.27, 0.02, 0.19], [0.0, 0.085, -0.04], c2),
        part('torus', [0.15, 0.012], [0.0, 0.09, -0.04], c2, rot=[0, 0, 0]),
        part('rod', [0.008, 0.008], [-0.06, 0.08, 0.06], '#3A3A40', to=[-0.05, 0.13, 0.25]),
        part('rod', [0.008, 0.008], [0.06, 0.08, 0.06], '#3A3A40', to=[0.05, 0.13, 0.25]),
    ]
    if flowers:
        for i, (x, z, col) in enumerate([(-0.08, -0.06, '#F5B6C8'), (0.0, -0.02, '#F5D547'), (0.08, -0.07, '#E0484A'), (-0.03, -0.11, '#FFFFFF'), (0.05, 0.02, '#B49BE0')]):
            out.append(part('rod', [0.006, 0.005], [x, 0.08, z], '#5A9A4A', to=[x * 1.2, 0.16 + 0.02 * (i % 2), z * 1.2]))
            out.append(part('sphere', [0.035], [x * 1.2, 0.17 + 0.02 * (i % 2), z * 1.2], col))
        out.append(part('sphere', [0.11, 0.04, 0.08], [0.0, 0.1, -0.04], '#6FAE55'))
    return out


add(id='front_basket', slot='front', kinds=['bike'], name='라탄 바구니', price={'bike': 35000}, anchor='front',
    model=basket(['#B07A45', '#D9A86A'], '#8C5A30'), desc='손으로 엮은 라탄 바구니.')
add(id='front_wire', slot='front', kinds=['bike'], name='철망 바구니', price={'bike': 19000}, anchor='front',
    model=basket('#C8CCD4', '#9AA0A8'), desc='튼튼한 철망 바구니.')
add(id='front_flowers', slot='front', kinds=['bike'], name='꽃 바구니', price={'bike': 49000}, anchor='front',
    model=basket(['#C8955A', '#E8C080'], '#9A6A40', True), desc='꽃을 가득 담은 바구니.')
add(id='front_phone', slot='front', name='휴대폰 거치대', price={'bike': 15000, 'moto': 25000}, anchor='bar', model=[
    part('cyl', [0.012, 0.06], [0.0, 0.02, 0.0], '#1F1F22'),
    part('rbox', [0.12, 0.17, 0.02], [0.0, 0.1, 0.02], '#1F1F22', rot=[-50, 0, 0], r=0.4),
    part('box', [0.1, 0.14, 0.006], [0.0, 0.103, 0.012], '#7CC4EA', rot=[-50, 0, 0])], desc='지도를 보며 달린다.')
add(id='front_screen', slot='front', kinds=['moto'], name='윈드스크린', price={'moto': 149000}, anchor='bar', model=[
    part('rbox', [0.36, 0.3, 0.02], [0.0, 0.14, -0.1], '#CFE8F4', rot=[-22, 0, 0], r=0.6),
    part('rbox', [0.38, 0.03, 0.03], [0.0, 0.0, -0.06], '$trim', rot=[-22, 0, 0], r=0.5)], desc='바람을 막아 주는 투명한 가림막.')
add(id='front_fairing', slot='front', kinds=['moto'], name='카페레이서 카울', price={'moto': 320000}, anchor='head', model=[
    part('sphere', [0.2, 0.17, 0.16], [0.0, 0.03, 0.02], '$paint'),
    part('rbox', [0.3, 0.14, 0.02], [0.0, 0.17, 0.02], '#CFE8F4', rot=[-30, 0, 0], r=0.6),
    part('torus', [0.1, 0.016], [0.0, 0.0, -0.13], '$trim', rot=[90, 0, 0])], desc='전조등을 감싸는 둥근 카울.')

add(id='rear_rack', slot='rear', kinds=['bike'], name='짐받이', price={'bike': 25000}, anchor='rear', model=[
    part('box', [0.16, 0.015, 0.3], [0.0, 0.0, 0.02], '$trim'),
    part('rod', [0.008, 0.008], [-0.07, 0.0, 0.16], '$trim', to=[-0.07, -0.22, 0.02]),
    part('rod', [0.008, 0.008], [0.07, 0.0, 0.16], '$trim', to=[0.07, -0.22, 0.02])], desc='뒤에 짐을 싣는 받침.')
add(id='rear_crate', slot='rear', kinds=['bike'], name='우유 상자', price={'bike': 22000}, anchor='rear', model=[
    part('box', [0.16, 0.015, 0.3], [0.0, 0.0, 0.02], '#3A3A40'),
    part('rbox', [0.26, 0.18, 0.26], [0.0, 0.1, 0.02], '#F5D547', r=0.15),
    part('box', [0.22, 0.02, 0.22], [0.0, 0.19, 0.02], '#E0B830'),
    part('box', [0.27, 0.04, 0.02], [0.0, 0.12, 0.15], '#E0B830')], desc='노란 플라스틱 상자. 뭐든 담긴다.')
add(id='rear_bag', slot='rear', name='사이드 가방', price={'bike': 79000, 'moto': 159000}, anchor='rear', model=[
    part('box', [0.16, 0.015, 0.3], [0.0, 0.0, 0.02], '#3A3A40'),
    part('rbox', [0.07, 0.2, 0.26], [-0.13, -0.09, 0.02], '#7A4E30', r=0.3),
    part('rbox', [0.07, 0.2, 0.26], [0.13, -0.09, 0.02], '#7A4E30', r=0.3),
    part('box', [0.075, 0.06, 0.27], [-0.13, 0.0, 0.02], '#5A3A24'),
    part('box', [0.075, 0.06, 0.27], [0.13, 0.0, 0.02], '#5A3A24')], desc='양쪽에 매다는 가죽 가방.')
add(id='rear_topbox', slot='rear', kinds=['moto'], name='탑박스 30L', price={'moto': 129000}, anchor='rear', model=[
    part('rbox', [0.34, 0.24, 0.3], [0.0, 0.13, 0.04], '#2A2A2E', r=0.35),
    part('box', [0.3, 0.02, 0.02], [0.0, 0.1, 0.195], '#D8402F'),
    part('rbox', [0.35, 0.05, 0.31], [0.0, 0.24, 0.04], '$paint', r=0.4)], desc='헬멧이 들어가는 뒤 상자.')
add(id='rear_delivery', slot='rear', kinds=['moto'], name='배달 박스', price={'moto': 99000}, anchor='rear', model=[
    part('rbox', [0.4, 0.34, 0.36], [0.0, 0.18, 0.04], '#F2EEE4', r=0.12),
    part('box', [0.41, 0.06, 0.37], [0.0, 0.22, 0.04], '#E0484A'),
    part('box', [0.16, 0.1, 0.01], [0.0, 0.2, 0.225], '#FFFFFF')], desc='배달 알바의 든든한 짝.')

add(id='deco_bell', slot='deco', kinds=['bike'], name='황동 벨', price={'bike': 9000}, anchor='bar', model=[
    part('sphere', [0.04, 0.03, 0.04], [-0.14, 0.03, 0.0], '#D8B060'),
    part('cyl', [0.01, 0.03], [-0.14, 0.0, 0.0], '#8C6A30')], desc='따르릉! 맑은 소리.')
add(id='deco_tassel', slot='deco', kinds=['bike'], name='핸들 술 장식', price={'bike': 12000}, anchor='bar', model=[
    part('rod', [0.012, 0.004], [-0.33, 0.0, 0.03], '#F5B6C8', to=[-0.38, -0.12, 0.08]),
    part('rod', [0.012, 0.004], [-0.33, 0.0, 0.03], '#8CC8F0', to=[-0.35, -0.13, 0.1]),
    part('rod', [0.012, 0.004], [0.33, 0.0, 0.03], '#F5D547', to=[0.38, -0.12, 0.08]),
    part('rod', [0.012, 0.004], [0.33, 0.0, 0.03], '#8FD8C0', to=[0.35, -0.13, 0.1])], desc='달리면 살랑이는 리본 술.')
add(id='deco_flag', slot='deco', name='안전 깃발', price={'bike': 15000, 'moto': 29000}, anchor='rear', model=[
    part('rod', [0.008, 0.006], [0.1, 0.0, 0.12], '#F2EEE4', to=[0.1, 0.9, 0.16]),
    part('box', [0.01, 0.12, 0.2], [0.1, 0.82, 0.26], '#F28A3A', rot=[0, 0, 0])], desc='멀리서도 잘 보이는 주황 깃발.')
add(id='deco_mirror', slot='deco', kinds=['moto'], name='원형 미러', price={'moto': 45000}, anchor='bar', model=[
    part('rod', [0.008, 0.008], [-0.26, 0.0, 0.0], '$trim', to=[-0.3, 0.16, 0.02]),
    part('rod', [0.008, 0.008], [0.26, 0.0, 0.0], '$trim', to=[0.3, 0.16, 0.02]),
    part('cyl', [0.055, 0.015], [-0.3, 0.19, 0.02], '$trim', rot=[90, 0, 0]),
    part('cyl', [0.045, 0.017], [-0.3, 0.19, 0.022], '#CFE8F4', rot=[90, 0, 0]),
    part('cyl', [0.055, 0.015], [0.3, 0.19, 0.02], '$trim', rot=[90, 0, 0]),
    part('cyl', [0.045, 0.017], [0.3, 0.19, 0.022], '#CFE8F4', rot=[90, 0, 0])], desc='동글동글 클래식 거울.')
add(id='deco_plush', slot='deco', name='곰인형 마스코트', price={'bike': 25000, 'moto': 25000}, anchor='rear', model=[
    part('sphere', [0.07, 0.075, 0.06], [0.0, 0.07, 0.05], '#C8955A'),
    part('sphere', [0.06], [0.0, 0.18, 0.05], '#C8955A'),
    part('sphere', [0.022], [-0.045, 0.23, 0.05], '#A8753A'),
    part('sphere', [0.022], [0.045, 0.23, 0.05], '#A8753A'),
    part('sphere', [0.025, 0.02, 0.015], [0.0, 0.17, -0.005], '#F2E0C8'),
    part('sphere', [0.008], [-0.02, 0.195, -0.004], '#2A2A2E'),
    part('sphere', [0.008], [0.02, 0.195, -0.004], '#2A2A2E')], desc='뒤에 앉아 같이 달리는 곰.')
add(id='deco_stripe', slot='deco', name='레이싱 줄무늬', price={'bike': 19000, 'moto': 89000}, anchor='frame', paint2='$trim', model=[],
    desc='프레임에 포인트 색 줄무늬를 두른다.')

# 빛나는 장식: glow = { c: 색, where: spoke(바퀴살) | under(차체 밑) | frame(프레임 줄) }. 밤에만 빛난다.
for gid, name, color in [('blue', '블루', '#4AA8FF'), ('pink', '핑크', '#FF6FB0'), ('green', '그린', '#5CFF9A'), ('purple', '퍼플', '#B07CFF'), ('warm', '웜 화이트', '#FFD08A')]:
    add(id='glow_spoke_' + gid, slot='glow', kinds=['bike'], name='바퀴살 LED · ' + name, price={'bike': 39000}, glow={'c': color, 'where': 'spoke'},
        desc='달리면 바퀴에 빛 고리가 그려진다.')
    add(id='glow_under_' + gid, slot='glow', kinds=['moto'], name='언더글로우 · ' + name, price={'moto': 159000}, glow={'c': color, 'where': 'under'},
        desc='차체 아래를 은은하게 밝힌다.')
add(id='glow_frame_rainbow', slot='glow', kinds=['bike'], name='프레임 네온 · 무지개', price={'bike': 59000}, glow={'c': '#FF9AD8', 'where': 'frame'},
    desc='프레임을 따라 빛줄이 흐른다.')

SLOTS = [
    {'id': 'paint', 'name': '도색'}, {'id': 'trim', 'name': '포인트 색'}, {'id': 'light', 'name': '전조등'}, {'id': 'tail', 'name': '미등'},
    {'id': 'glow', 'name': '빛 장식'}, {'id': 'drive', 'name': '구동 · 모터'}, {'id': 'brake', 'name': '브레이크'}, {'id': 'tire', 'name': '타이어'},
    {'id': 'seat', 'name': '안장 · 시트'}, {'id': 'front', 'name': '앞 장착'}, {'id': 'rear', 'name': '뒤 장착'}, {'id': 'deco', 'name': '장식'},
]

for p in parts:
    for k in p['kinds']:
        assert k in p['price'], p['id']
    assert p['slot'] in [s['id'] for s in SLOTS], p['id']

data = {
    'version': 1,
    'max_owned': 6,
    'resale': 0.55,
    # 호출 (v19.1): 주민이 탈것을 타고 와서 곁(park_range 안)에 세워 두고 간다. 오는 데 걸리는 시간 · 올라탈 수 있는 거리.
    'delivery': {'eta_ms': 6500, 'park_range': 4.0, 'ride_range': 3.0, 'speed_grace_ms': 1500},
    'kinds': {
        'bike': {'name': '자전거', 'pose': 'bike', 'turn_speed': 0.55},
        'moto': {'name': '전기오토바이', 'pose': 'moto', 'turn_speed': 0.4,
                 'throttle_rise': 1.6, 'throttle_fall': 3.5, 'brake_rise': 4.0, 'jerk': 7.0},
    },
    'slots': SLOTS,
    'models': MODELS,
    'parts': parts,
}
OUT.parent.mkdir(parents=True, exist_ok=True)
text = json.dumps(data, ensure_ascii=False, indent=1)
OUT.write_text(text + '\n')
print('ok', len(MODELS), 'models', len(parts), 'parts')
