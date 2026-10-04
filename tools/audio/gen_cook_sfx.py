#!/usr/bin/env python3
"""식당 효과음 (v0.8)을 합성한다: 칼질 · 지글지글 · 보글보글 · 접시 · 주문 벨 · 손님 계산.
gen_audio.py 의 도구를 그대로 쓴다. 사용: python3 tools/audio/gen_cook_sfx.py
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_audio import SR, biquad_bp, env_ad, onepole_lp, save_wav, t_axis  # noqa: E402

rng = np.random.default_rng(31)


def cook_chop() -> np.ndarray:
    """도마 위 칼: 짧은 나무 "톡" + 칼날의 높은 울림."""
    n = int(0.16 * SR)
    t = t_axis(0.16)
    knock = biquad_bp(rng.standard_normal(n), 900, 3.0) * env_ad(n, 0.001, 0.025)
    body = np.sin(2 * np.pi * 210 * t) * env_ad(n, 0.001, 0.04) * 0.6
    ring = np.sin(2 * np.pi * 3100 * t) * env_ad(n, 0.001, 0.03) * 0.12
    return knock + body + ring


def cook_sizzle() -> np.ndarray:
    """팬 위 지글지글 (1.4초, 이어 붙여 반복해도 티가 덜 나게 앞뒤를 둥글게)."""
    dur = 1.4
    n = int(dur * SR)
    hiss = biquad_bp(rng.standard_normal(n), 5200, 0.7) * 0.5
    crackle = np.zeros(n)
    for _ in range(90):
        i = rng.integers(0, n - 400)
        crackle[i:i + 400] += biquad_bp(rng.standard_normal(400), rng.uniform(2500, 6500), 4.0) * env_ad(400, 0.0005, 0.004) * rng.uniform(0.4, 1.0)
    fade = np.minimum(1, np.minimum(np.arange(n), n - np.arange(n)) / (0.12 * SR))
    return (hiss * (0.7 + 0.3 * np.sin(2 * np.pi * 3 * t_axis(dur))) + crackle) * fade


def cook_bubble() -> np.ndarray:
    """냄비 보글보글: 위로 미끄러지는 작은 방울 소리들."""
    dur = 1.2
    n = int(dur * SR)
    out = np.zeros(n)
    for _ in range(14):
        i = rng.integers(0, n - 2600)
        m = 2600
        t = np.arange(m) / SR
        f = rng.uniform(260, 520) * (1 + 2.5 * t / t[-1])
        out[i:i + m] += np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.002, 0.03) * rng.uniform(0.3, 0.8)
    low = onepole_lp(rng.standard_normal(n), 300) * 0.25
    fade = np.minimum(1, np.minimum(np.arange(n), n - np.arange(n)) / (0.1 * SR))
    return (out + low) * fade


def cook_plate() -> np.ndarray:
    """사기 접시를 내려놓는 "딸깍" + 맑은 울림."""
    n = int(0.5 * SR)
    t = t_axis(0.5)
    tap = biquad_bp(rng.standard_normal(n), 2400, 2.0) * env_ad(n, 0.0005, 0.012)
    tone = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(1870, 0.5), (2950, 0.3), (4410, 0.15)]) * env_ad(n, 0.001, 0.16)
    return tap + tone * 0.6


def order_bell() -> np.ndarray:
    """카운터 종 "띵" (주문 들어옴 / 요리 완성)."""
    n = int(1.1 * SR)
    t = t_axis(1.1)
    partials = [(1568, 1.0), (1568 * 2.76, 0.35), (1568 * 5.4, 0.12), (1568 * 0.5, 0.2)]
    tone = sum(np.sin(2 * np.pi * f * t) * a * np.exp(-t * (2.2 + k)) for k, (f, a) in enumerate(partials))
    strike = biquad_bp(rng.standard_normal(n), 4000, 2.0) * env_ad(n, 0.0005, 0.006) * 0.4
    return tone + strike


def cash_in() -> np.ndarray:
    """계산: 짤랑 동전 두 번 + 서랍 "팅"."""
    n = int(0.7 * SR)
    t = t_axis(0.7)
    out = np.zeros(n)
    for start, f in [(0.0, 2637), (0.09, 3136), (0.2, 3951)]:
        i = int(start * SR)
        m = n - i
        tt = t[:m]
        out[i:] += (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2.4 * tt)) * env_ad(m, 0.001, 0.09)
    return out * 0.6


if __name__ == "__main__":
    for name, fn in [("cook_chop", cook_chop), ("cook_sizzle", cook_sizzle), ("cook_bubble", cook_bubble),
                     ("cook_plate", cook_plate), ("order_bell", order_bell), ("cash_in", cash_in)]:
        save_wav(name, fn())
