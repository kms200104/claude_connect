#!/usr/bin/env python3
"""물놀이 체험 데이터(data/aqua/aqua.json)를 만든다: 성성호수 선착장의 바나나 보트 · 유람선 (v21).

- 노선은 성성호수 윤곽(data/fish/spots.json seongseong.outline) 안에서 손으로 고른 길목을 Catmull-Rom 으로 이은 닫힌 고리다.
  윤곽에서 margin m 안쪽인지 1m 마다 검사하고, 2m 간격으로 다시 찍어 path 로 쓴다 (서버 aqua.js · 클라이언트 AquaRules 가 같은 길을 쓴다).
- 길 0 m = 선착장 곁 대기 자리, 한 바퀴 돌아 같은 자리로 돌아온다.
- 바나나 보트 turns: 바나나가 지나는 급회전 자리 (s, 방향). 그 앞에서 "꽉 잡아!" — 시간 안에 누르면 버티고, 놓치면 물에 빠진다.
- 유람선 stops: 선장 안내 방송 자리 (s, 말).
사용: python3 tools/art/gen_aqua.py [--png=미리보기.png]
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/aqua/aqua.json'


def find_spot(o, sid):
    if isinstance(o, dict):
        if o.get('id') == sid:
            return o
        for v in o.values():
            r = find_spot(v, sid)
            if r:
                return r
    if isinstance(o, list):
        for v in o:
            r = find_spot(v, sid)
            if r:
                return r
    return None


LAKE = find_spot(json.loads((ROOT / 'data/fish/spots.json').read_text()), 'seongseong')
POLY = [tuple(p) for p in LAKE['outline']]
LAYOUT = json.loads((ROOT / 'data/world/village_layout.json').read_text())


def inside(x, z):
    c = False
    n = len(POLY)
    for i in range(n):
        x1, z1 = POLY[i]
        x2, z2 = POLY[(i + 1) % n]
        if (z1 > z) != (z2 > z) and x < (x2 - x1) * (z - z1) / (z2 - z1) + x1:
            c = not c
    return c


def edge_dist(x, z):
    best = 1e9
    n = len(POLY)
    for i in range(n):
        x1, z1 = POLY[i]
        x2, z2 = POLY[(i + 1) % n]
        dx, dz = x2 - x1, z2 - z1
        L = dx * dx + dz * dz
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((x - x1) * dx + (z - z1) * dz) / L))
        best = min(best, math.hypot(x - (x1 + dx * t), z - (z1 + dz * t)))
    return best


def signed(x, z):
    d = edge_dist(x, z)
    return -d if inside(x, z) else d


def catmull(pts, step=0.25):
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        seg = math.dist(p1, p2)
        k = max(2, int(seg / step))
        for j in range(k):
            t = j / k
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[a]) + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2
                                    + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3) for a in (0, 1)))
    out.append(out[0])
    return out


def resample(line, spacing):
    cum = [0.0]
    for a, b in zip(line, line[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    total = cum[-1]
    n = max(2, round(total / spacing))
    out = []
    j = 0
    for i in range(n + 1):
        s = total * i / n
        while j < len(cum) - 2 and cum[j + 1] < s:
            j += 1
        seg = cum[j + 1] - cum[j]
        t = 0.0 if seg == 0 else (s - cum[j]) / seg
        a, b = line[j], line[j + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out, total


def check(name, line, margin):
    worst = (1e9, None)
    for i in range(0, len(line), 4):
        x, z = line[i]
        d = -signed(x, z)
        if d < worst[0]:
            worst = (d, (round(x, 1), round(z, 1)))
    if worst[0] < margin:
        sys.exit(f'{name}: 물가에서 {worst[0]:.2f}m ({worst[1]}) — {margin}m 안쪽이어야 한다')
    return worst[0]


def heading(path, i, w):
    a = path[max(0, i - w)]
    b = path[min(len(path) - 1, i + w)]
    return math.atan2(b[0] - a[0], b[1] - a[1])


def find_turns(path, spacing, min_deg, gap_m):
    """급회전: 앞뒤 w 칸의 방향 차가 min_deg 넘는 자리 가운데 가장 꺾이는 곳 (서로 gap_m 넘게 떨어진)."""
    w = 3
    cands = []
    for i in range(w, len(path) - w):
        h0 = math.atan2(path[i][0] - path[i - w][0], path[i][1] - path[i - w][1])
        h1 = math.atan2(path[i + w][0] - path[i][0], path[i + w][1] - path[i][1])
        d = (h1 - h0 + math.pi) % (2 * math.pi) - math.pi
        if abs(math.degrees(d)) >= min_deg:
            cands.append((abs(d), i, d))
    cands.sort(reverse=True)
    picked = []
    for mag, i, d in cands:
        s = i * spacing
        if all(abs(s - p['s']) > gap_m for p in picked):
            # + = 왼쪽(반시계, 게임 좌표 위에서 본 x→z), - = 오른쪽.
            picked.append({'s': round(s, 1), 'dir': -1 if d > 0 else 1, 'deg': round(math.degrees(mag))})
    return sorted(picked, key=lambda p: p['s'])


# 물놀이 선착장: 호수 서쪽 물가 (e편한세상 단지 앞, 둘레길 바로 곁). 매표소는 땅 위, 잔교는 물 위로 뻗은 장식 (걸어 들어가지 않는다).
PIER = {'root': (-7.4, -1.0), 'tip': (-1.6, -1.0), 'width': 1.6}
BOOTH = (-12.0, 1.4)
LAND = (-10.6, -0.6)
OPERATOR = (-10.4, 0.9)
# 대기 자리: 유람선은 잔교 북쪽(뱃머리 동쪽), 바나나 보트는 남쪽.
CRUISE_DOCK = (1.2, -4.9)
BANANA_DOCK = (0.6, 2.8)

BANANA_WAYS = [
    BANANA_DOCK, (11.0, 3.0), (21.0, -3.0), (28.0, -12.0), (20.0, -19.0), (26.0, -26.0), (16.0, -31.0),
    (8.0, -22.0), (-3.0, -19.0), (-5.0, -11.0), (5.0, -9.0), (12.0, 5.0), (6.0, 14.0), (-8.0, 17.0),
    (-20.0, 24.0), (-31.0, 29.0), (-25.0, 31.0), (-14.0, 23.0), (-4.0, 11.0), (-5.0, 4.5),
]
CRUISE_WAYS = [
    CRUISE_DOCK, (10.0, -3.0), (14.0, 7.0), (6.0, 15.0), (-8.0, 17.5), (-20.0, 23.5), (-30.0, 28.5),
    (-26.0, 31.0), (-16.0, 25.5), (-4.0, 20.0), (8.0, 11.0), (20.0, 0.0), (28.0, -12.0), (24.0, -24.0),
    (15.0, -28.0), (4.0, -20.0), (-4.0, -14.0), (-4.0, -8.5),
]

BANANA_SPACING = 2.0
CRUISE_SPACING = 2.0

banana_line = catmull(BANANA_WAYS)
cruise_line = catmull(CRUISE_WAYS)
bm = check('banana', banana_line, float(next((a.split('=')[1] for a in sys.argv if a.startswith('--margin=')), 3.0)))
cm = check('cruise', cruise_line, float(next((a.split('=')[1] for a in sys.argv if a.startswith('--margin=')), 3.0)))
banana_path, banana_len = resample(banana_line, BANANA_SPACING)
cruise_path, cruise_len = resample(cruise_line, CRUISE_SPACING)
turns = [t for t in find_turns(banana_path, banana_len / (len(banana_path) - 1), 42, 22.0) if 25.0 < t['s'] < banana_len - 20.0]


def near_s(path, spacing, x, z):
    best = min(range(len(path)), key=lambda i: math.dist(path[i], (x, z)))
    return round(best * spacing, 1)


cs = cruise_len / (len(cruise_path) - 1)
STOPS = [
    (CRUISE_DOCK[0], CRUISE_DOCK[1], '성성호 유람선에 오신 것을 환영해요! 구명조끼 단단히 매셨죠? 천천히 한 바퀴 돌아요.'),
    (6.0, 15.0, '남쪽 언덕 위가 호수 정자예요. 해 질 녘에 앉아 있으면 바람이 정말 좋아요.'),
    (-28.0, 29.5, '이 물굽이 끝이 성성호수 여울이에요. 얕은 물에서 피라미 · 납자루가 반짝여요.'),
    (8.0, 11.0, '서쪽으로 보이는 단지가 e편한세상 성성호수공원이에요. 호수 전망 집은 늘 인기랍니다.'),
    (28.0, -12.0, '동쪽 둘레길이에요. 아침마다 주민들이 이 길을 따라 산책해요. 손 흔들어 주세요!'),
    (15.0, -28.0, '호수 북쪽이에요. 이쪽은 물이 깊어서 큰 잉어 · 배스가 산대요. 낚시꾼들 명당!'),
    (-5.0, -15.0, '이제 선착장으로 돌아가요. 오늘 함께해 주셔서 고마워요. 내릴 때 발밑 조심하세요!'),
]
stops = [{'s': near_s(cruise_path, cs, x, z), 'line': line} for x, z, line in STOPS]
stops.sort(key=lambda s: s['s'])

data = {
    'version': 1,
    '_comment': '성성호수 물놀이 체험 (v21, tools/art/gen_aqua.py 가 만든다). 선착장(dock) 곁 board_range 안에서 요금을 내고 탄다. '
                'board_ms 동안 같이 탈 사람을 기다렸다가 출발해 path(닫힌 고리, 2m 간격)를 speed 로 돌고 제자리로 돌아온다 '
                '(처음 · 끝 ease_s 초는 천천히). 끝나면 land 로 내려선다. 바나나 보트는 turns 마다 "꽉 잡아!" '
                '(prompt_s 초 앞에서 띄우고 window_ms 안에 누르면 버팀 — 서버가 클라이언트 경과 시간으로 판정).',
    'dock': {'x': PIER['root'][0], 'z': PIER['root'][1], 'board_range': 6.0, 'land': list(LAND),
             'pier': [list(PIER['root']), list(PIER['tip'])], 'pier_width': PIER['width'], 'booth': list(BOOTH),
             'operator': 'haerang', 'operator_at': list(OPERATOR)},
    'board_ms': 8000,
    'rides': [
        {
            'id': 'banana', 'name': '바나나 보트', 'fee': 15000, 'seats': 4, 'speed': 6.2, 'ease_s': 3.0, 'tow': 9.0,
            'driver': 'mujin', 'prompt_s': 1.3, 'window_ms': 1500,
            'desc': '모터보트가 끄는 바나나 튜브! 급회전마다 "꽉 잡아!" — 제때 누르면 버티고, 놓치면 첨벙! 친구와 같이 타요.',
            'length': round(banana_len, 2), 'turns': [{'s': t['s'], 'dir': t['dir']} for t in turns],
            'path': [[round(x, 2), round(z, 2)] for x, z in banana_path],
        },
        {
            'id': 'cruise', 'name': '성성호 유람선', 'fee': 6000, 'seats': 8, 'speed': 2.8, 'ease_s': 4.0,
            'driver': 'tongtong',
            'desc': '느긋하게 호수를 한 바퀴. 선장님이 호숫가 이야기를 들려줘요. 사진 찍기 좋은 자리!',
            'length': round(cruise_len, 2), 'stops': stops,
            'path': [[round(x, 2), round(z, 2)] for x, z in cruise_path],
        },
    ],
}
OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')
print(f'ok banana {banana_len:.0f}m ({banana_len / 6.2 + 3:.0f}s, 물가 {bm:.1f}m) turns {len(turns)} {[(t["s"], t["dir"], t["deg"]) for t in turns]}')
print(f'ok cruise {cruise_len:.0f}m ({cruise_len / 2.8 + 4:.0f}s, 물가 {cm:.1f}m) stops {[s["s"] for s in stops]}')

png = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--png=')), '')
if png:
    from PIL import Image, ImageDraw
    S = 8
    img = Image.new('RGB', (100 * S, 100 * S), (200, 220, 180))
    dr = ImageDraw.Draw(img)
    T = lambda p: ((p[0] + 50) * S, (p[1] + 50) * S)
    dr.polygon([T(p) for p in POLY], fill=(120, 170, 220))
    for g in range(-50, 51, 10):
        dr.line([T((g, -50)), T((g, 50))], fill=(90, 120, 90), width=1)
        dr.line([T((-50, g)), T((50, g))], fill=(90, 120, 90), width=1)
        dr.text(T((g + 0.3, -49.5)), str(g), fill=(0, 0, 0))
        dr.text(T((-49.5, g + 0.3)), str(g), fill=(0, 0, 0))
    dr.line([T(PIER['root']), T(PIER['tip'])], fill=(140, 100, 60), width=int(PIER['width'] * S))
    dr.rectangle([T((BOOTH[0] - 1, BOOTH[1] - 1)), T((BOOTH[0] + 1, BOOTH[1] + 1))], fill=(200, 60, 60))
    dr.line([T(p) for p in banana_path], fill=(240, 210, 40), width=3)
    dr.line([T(p) for p in cruise_path], fill=(255, 255, 255), width=2)
    for t in turns:
        i = round(t['s'] / (banana_len / (len(banana_path) - 1)))
        x, y = T(banana_path[i])
        dr.ellipse([x - 6, y - 6, x + 6, y + 6], outline=(220, 40, 40), width=3)
    for s in stops:
        i = round(s['s'] / cs)
        x, y = T(cruise_path[i])
        dr.rectangle([x - 5, y - 5, x + 5, y + 5], outline=(40, 40, 160), width=3)
    x, y = T(banana_path[0])
    dr.text((x + 6, y), 'B0', fill=(0, 0, 0))
    x, y = T(cruise_path[0])
    dr.text((x + 6, y), 'C0', fill=(0, 0, 0))
    img.save(png)
