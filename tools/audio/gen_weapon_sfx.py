#!/usr/bin/env python3
"""v0.28.8 무기 · 직업 기술 소리 합성 (numpy · scipy, gen_creature_sfx 의 도구를 쓴다).

휘두르기 (바람 가르기 — 무기 무게 · 날에 따라):
  swing_light   가벼운 휘두름 (맨손 · 손전등 · 쇠파이프, 짧고 높은 '휙', 0.22초)
  swing_heavy   무거운 휘두름 (몽둥이 · 방망이 · 소방도끼, 낮고 긴 '부웅', 0.38초)
  swing_blade   날붙이 (도끼 · 삽, 날이 공기를 찢는 '쉭', 0.26초)
  swing_thrust  찌르기 (쇠창, 짧게 앞으로 '슉', 0.2초)
  swing_fire    횃불 (불길이 바람에 '화르륵', 0.45초)
맞히기 (무기 재질마다):
  hit_fist      맨주먹 (둔한 '퍽', 0.18초)
  hit_wood      나무 몽둥이 (단단한 '딱 · 퍽', 0.3초)
  hit_metal     쇠파이프 (쇠가 울리는 '깡' + 둔탁함, 0.55초)
  hit_nails     못 박힌 방망이 ('콰직' — 둔탁 + 못이 살을 긁는 소리, 0.42초)
  hit_blade     도끼 · 소방도끼 ('서걱' — 날이 박히는 소리 + 젖은 소리, 0.4초)
  hit_stab      쇠창 ('푹' — 찌르는 소리, 0.3초)
  hit_fire      횃불 ('치익' — 불이 살에 닿는 소리, 0.5초)
  hit_bolt      석궁 화살 ('턱' — 화살이 박히는 소리, 0.25초)
  hit_crit      치명타 위에 얹는 날카로운 '챙' (0.35초)
직업 기술:
  skill_whirl   회전 베기 (한 바퀴 크게 도는 바람 + 쿵, 0.7초)
  skill_ambush  그림자 일격 (어두운 숨 들이킴 · 낮게 울림, 0.8초)
  skill_pierce  관통 사격 (힘껏 당긴 시위 · 길게 찢는 바람, 0.6초)
  skill_mend    치유의 빛 (맑은 종소리 화음이 올라간다, 1.2초)
  guard_block   버티기로 막음 (둔탁한 '텅', 0.3초)

사용: python3 tools/audio/gen_weapon_sfx.py  → assets/audio/sfx/*.wav (44.1kHz 16bit 모노)
"""
import numpy as np
from scipy import signal

from gen_creature_sfx import SR, finish, resonator, room, write


def tt_of(dur):
    n = int(dur * SR)
    return n, np.arange(n) / SR


def band(x, lo, hi):
    b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def whoosh(rng, dur, f0, f1, peak, width=0.5, bw=600):
    """공기를 가르는 소리: 잡음을 움직이는 공명 필터로 깎고, peak 초에 가장 세게 (가우스 모양)."""
    n, tt = tt_of(dur)
    sweep = np.interp(tt, [0, peak, dur], [f0, f1, f0 * 0.6])
    x = resonator(rng.normal(0, 1, n), sweep, bw)
    env = np.exp(-((tt - peak) / (dur * width * 0.5)) ** 2)
    return x * env


def thump(tt, f, decay, drop=0.5):
    return np.sin(2 * np.pi * f * tt * (1 - drop * np.clip(tt * 4, 0, 1) * 0.5)) * np.exp(-tt * decay)


def ring(tt, freqs, decay, amps=None):
    amps = amps or [1.0] * len(freqs)
    return sum(a * np.sin(2 * np.pi * f * tt + i) * np.exp(-tt * decay * (1 + 0.3 * i)) for i, (f, a) in enumerate(zip(freqs, amps)))


def swing_light():
    rng = np.random.default_rng(101)
    return finish(whoosh(rng, 0.22, 900, 2600, 0.09, 0.6, 700), 1.3)


def swing_heavy():
    rng = np.random.default_rng(102)
    x = whoosh(rng, 0.38, 300, 900, 0.17, 0.7, 260)
    n, tt = tt_of(0.38)
    x += 0.4 * np.sin(2 * np.pi * 70 * tt) * np.exp(-((tt - 0.17) / 0.1) ** 2)
    return finish(x, 1.5)


def swing_blade():
    rng = np.random.default_rng(103)
    x = whoosh(rng, 0.26, 1400, 4200, 0.1, 0.45, 900)
    n, tt = tt_of(0.26)
    # 날이 떨리는 높은 울림이 살짝.
    x += 0.08 * np.sin(2 * np.pi * 5200 * tt) * np.exp(-((tt - 0.1) / 0.05) ** 2)
    return finish(x, 1.4)


def swing_thrust():
    rng = np.random.default_rng(104)
    return finish(whoosh(rng, 0.2, 1800, 3000, 0.06, 0.35, 1100), 1.3)


def swing_fire():
    rng = np.random.default_rng(105)
    n, tt = tt_of(0.45)
    x = whoosh(rng, 0.45, 400, 1200, 0.2, 0.8, 500) * 1.2
    # 불길이 탁탁 튀는 작은 소리들.
    crackle = rng.normal(0, 1, n) * (rng.uniform(0, 1, n) > 0.993) * 1.6
    crackle = band(crackle, 1500, 7000)
    roar = band(rng.normal(0, 1, n), 120, 600) * np.exp(-((tt - 0.22) / 0.16) ** 2) * 0.8
    return finish(x + crackle + roar, 1.6)


def hit_fist():
    rng = np.random.default_rng(111)
    n, tt = tt_of(0.18)
    x = thump(tt, 110, 40) + band(rng.normal(0, 1, n), 300, 1500) * np.exp(-tt * 45) * 0.8
    return finish(x, 2.0)


def hit_wood():
    rng = np.random.default_rng(112)
    n, tt = tt_of(0.3)
    knock = ring(tt, [620, 980, 1450], 38, [1.0, 0.6, 0.35]) * 0.7
    x = thump(tt, 95, 26) + knock + band(rng.normal(0, 1, n), 400, 2500) * np.exp(-tt * 40) * 0.6
    return finish(room(x, rng, 0.12, 0.2), 2.0)


def hit_metal():
    rng = np.random.default_rng(113)
    n, tt = tt_of(0.55)
    # 쇠파이프: 비조화 배음이 길게 울린다.
    clang = ring(tt, [870, 2390, 3510, 5130], 9, [1.0, 0.55, 0.4, 0.2])
    x = thump(tt, 90, 30) * 0.9 + clang * 0.55 + band(rng.normal(0, 1, n), 2000, 8000) * np.exp(-tt * 60) * 0.5
    return finish(room(x, rng, 0.18, 0.3), 1.6)


def hit_nails():
    rng = np.random.default_rng(114)
    n, tt = tt_of(0.42)
    body = thump(tt, 80, 22) * 1.1
    # 못이 긁고 찢는 거친 소리 (잘게 끊긴 잡음).
    tear = band(rng.normal(0, 1, n), 1200, 5000) * (rng.uniform(0, 1, n) > 0.6) * np.exp(-tt * 14) * 0.9
    wet = resonator(rng.normal(0, 1, n), np.interp(tt, [0, 0.42], [1600, 400]), 300) * np.exp(-tt * 15) * 2.2
    return finish(body + tear + wet, 2.4)


def hit_blade():
    rng = np.random.default_rng(115)
    n, tt = tt_of(0.4)
    chop = band(rng.normal(0, 1, n), 2500, 9000) * np.exp(-tt * 70) * 1.4
    bite = thump(tt, 140, 30) * 0.8
    wet = resonator(rng.normal(0, 1, n), np.interp(tt, [0, 0.4], [2200, 500]), 240) * np.exp(-tt * 11) * 2.4
    return finish(chop + bite + wet, 2.2)


def hit_stab():
    rng = np.random.default_rng(116)
    n, tt = tt_of(0.3)
    x = thump(tt, 160, 34) * 0.6 + resonator(rng.normal(0, 1, n), np.interp(tt, [0, 0.3], [900, 300]), 200) * np.exp(-tt * 18) * 2.6
    return finish(x, 2.2)


def hit_fire():
    rng = np.random.default_rng(117)
    n, tt = tt_of(0.5)
    sizzle = band(rng.normal(0, 1, n), 3000, 10000) * np.exp(-tt * 6) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * tt))
    x = thump(tt, 100, 28) * 0.9 + sizzle * 0.9
    return finish(x, 1.8)


def hit_bolt():
    rng = np.random.default_rng(118)
    n, tt = tt_of(0.25)
    x = thump(tt, 210, 45) * 0.9 + band(rng.normal(0, 1, n), 800, 3000) * np.exp(-tt * 60) + ring(tt, [420], 30) * 0.3
    return finish(x, 2.0)


def hit_crit():
    rng = np.random.default_rng(119)
    n, tt = tt_of(0.35)
    x = ring(tt, [1760, 2640, 3960], 12, [1.0, 0.6, 0.3]) + band(rng.normal(0, 1, n), 4000, 10000) * np.exp(-tt * 50) * 0.6
    return finish(x, 1.3) * 0.8


def skill_whirl():
    rng = np.random.default_rng(121)
    n, tt = tt_of(0.7)
    x = whoosh(rng, 0.7, 300, 1600, 0.3, 0.9, 400) * 1.4
    x += whoosh(rng, 0.7, 800, 2800, 0.42, 0.4, 800) * 0.6
    slam = np.where(tt > 0.42, thump(np.clip(tt - 0.42, 0, None), 60, 12), 0) * 0.9
    return finish(room(x + slam, rng, 0.2, 0.35), 1.6)


def skill_ambush():
    rng = np.random.default_rng(122)
    n, tt = tt_of(0.8)
    breath = band(rng.normal(0, 1, n), 300, 2500) * np.clip(tt / 0.4, 0, 1) * np.exp(-((tt - 0.4) / 0.25) ** 2) * 0.9
    drone = sum(np.sin(2 * np.pi * f * tt) for f in (55, 82.4, 110.5)) * np.clip(tt / 0.2, 0, 1) * np.exp(-tt * 3.5) * 0.5
    return finish(room(breath + drone, rng, 0.35, 0.5), 1.4)


def skill_pierce():
    rng = np.random.default_rng(123)
    n, tt = tt_of(0.6)
    creak = band(rng.normal(0, 1, n), 200, 900) * (rng.uniform(0, 1, n) > 0.97) * np.clip(1 - tt / 0.2, 0, 1) * 2
    twang = np.where(tt > 0.18, np.sin(2 * np.pi * 150 * (tt - 0.18)) * np.exp(-np.clip(tt - 0.18, 0, None) * 18), 0)
    tear = np.where(tt > 0.18, 1.0, 0.0) * whoosh(rng, 0.6, 4200, 1200, 0.3, 0.8, 900) * 1.4
    return finish(creak + twang + tear, 1.5)


def skill_mend():
    rng = np.random.default_rng(124)
    n, tt = tt_of(1.2)
    x = np.zeros(n)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        t0 = 0.12 * i
        u = np.clip(tt - t0, 0, None)
        x += np.where(tt >= t0, (np.sin(2 * np.pi * f * u) + 0.3 * np.sin(2 * np.pi * f * 2.01 * u)) * np.exp(-u * 3.2), 0)
    shimmer = band(rng.normal(0, 1, n), 6000, 12000) * np.exp(-((tt - 0.5) / 0.35) ** 2) * 0.15
    return finish(room(x * 0.5 + shimmer, rng, 0.35, 0.6), 1.1) * 0.85


def guard_block():
    rng = np.random.default_rng(125)
    n, tt = tt_of(0.3)
    x = thump(tt, 120, 30) + ring(tt, [300, 470], 25, [0.6, 0.3]) + band(rng.normal(0, 1, n), 500, 3000) * np.exp(-tt * 50) * 0.5
    return finish(x, 1.8)


def main():
    for name, fn in [
        ("swing_light", swing_light), ("swing_heavy", swing_heavy), ("swing_blade", swing_blade), ("swing_thrust", swing_thrust), ("swing_fire", swing_fire),
        ("hit_fist", hit_fist), ("hit_wood", hit_wood), ("hit_metal", hit_metal), ("hit_nails", hit_nails), ("hit_blade", hit_blade),
        ("hit_stab", hit_stab), ("hit_fire", hit_fire), ("hit_bolt", hit_bolt), ("hit_crit", hit_crit),
        ("skill_whirl", skill_whirl), ("skill_ambush", skill_ambush), ("skill_pierce", skill_pierce), ("skill_mend", skill_mend), ("guard_block", guard_block),
    ]:
        write(name, fn())


if __name__ == "__main__":
    main()
