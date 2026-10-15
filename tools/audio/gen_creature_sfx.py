#!/usr/bin/env python3
"""v0.28.3 크리처 소리 합성 (numpy · scipy): 성대 펄스(떨리고 갈라지는 음정 · 보컬 프라이) → 모음 포먼트 공명 → 꾸르륵거리는
진폭 흔들림 · 숨소리 · 일그러짐 · 짧은 울림. 사람 목소리 같지만 망가진 소리가 나도록.

  creature_groan_1..3  낮게 끄는 신음 (1.4~2.2초)
  creature_snarl       덮칠 때 으르렁 (0.7초)
  creature_shriek      비명이의 찢어지는 비명 (1.3초)
  creature_hit         맞을 때 살 터지는 소리 (0.3초)
  creature_die         쓰러질 때 꺼져 가는 꾸르륵 (1.7초)
  heartbeat            v0.28.4 공포 연출 심장 박동 한 번 (쿵-쿵, 0.5초)
  fear_sting           v0.28.4 크리처가 처음 다가올 때 섬뜩한 소리 (불협 화음이 부풀다 긁히는 소리, 2.4초)

사용: python3 tools/audio/gen_creature_sfx.py  → assets/audio/sfx/*.wav (44.1kHz 16bit 모노)
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")


def glottal(f0, rng, jitter=0.04, fry=0.0):
    """음정 곡선 f0 (Hz, 표본마다) 를 따라가는 성대 펄스. jitter 만큼 주기가 흔들리고, fry 만큼 한 주기 걸러 약해진다 (갈라짐)."""
    n = len(f0)
    out = np.zeros(n)
    t = 0.0
    k = 0
    while True:
        i = int(t)
        if i >= n:
            break
        period = SR / max(f0[i], 20.0) * (1.0 + rng.normal(0.0, jitter))
        amp = 1.0 - fry * (k % 2) * rng.uniform(0.4, 1.0)
        # 한 주기: 빠르게 열렸다 닫히는 펄스 (Rosenberg 근사).
        L = int(period)
        if L < 4:
            L = 4
        u = np.arange(L) / L
        pulse = np.where(u < 0.6, 0.5 * (1 - np.cos(np.pi * u / 0.6)), np.cos(np.pi * (u - 0.6) / 0.8))
        pulse = np.diff(np.concatenate([[0.0], pulse]))
        end = min(n, i + L)
        out[i:end] += amp * pulse[: end - i]
        t += period
        k += 1
    return out


def resonator(x, freq, bw):
    """2극 공명 필터 (포먼트 하나). freq 는 상수 또는 표본마다 바뀌는 배열."""
    freq = np.broadcast_to(np.asarray(freq, dtype=float), x.shape)
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    r = np.exp(-np.pi * bw / SR)
    for i in range(len(x)):
        c = 2 * r * np.cos(2 * np.pi * freq[i] / SR)
        v = x[i] + c * y1 - r * r * y2
        y[i] = v
        y2, y1 = y1, v
    return y * (1 - r)


def vowel(src, f1, f2, f3, gains=(1.0, 0.6, 0.25), bws=(90, 120, 200)):
    return gains[0] * resonator(src, f1, bws[0]) + gains[1] * resonator(src, f2, bws[1]) + gains[2] * resonator(src, f3, bws[2])


def smooth_noise(n, rate, rng):
    """rate Hz 쯤으로 천천히 바뀌는 잡음 (-1~1)."""
    m = max(2, int(n * rate / SR) + 2)
    pts = rng.uniform(-1, 1, m)
    return np.interp(np.linspace(0, m - 1, n), np.arange(m), pts)


def envelope(n, attack, release, curve=1.0):
    e = np.ones(n)
    a = int(attack * SR)
    r = int(release * SR)
    if a > 0:
        e[:a] = np.linspace(0, 1, a) ** curve
    if r > 0:
        e[-r:] *= np.linspace(1, 0, r) ** 1.5
    return e


def room(x, rng, mix=0.2, length=0.35):
    n = int(length * SR)
    ir = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 7, n))
    ir[0] = 0
    wet = signal.fftconvolve(x, ir)[: len(x)]
    wet /= np.max(np.abs(wet)) + 1e-9
    return x * (1 - mix) + wet * mix * np.max(np.abs(x))


def finish(x, drive=2.0):
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-9) * drive)
    b, a = signal.butter(2, 40 / (SR / 2), "high")
    x = signal.lfilter(b, a, x)
    return x / (np.max(np.abs(x)) + 1e-9) * 0.89


def write(name, x):
    path = os.path.join(OUT, name + ".wav")
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(path, f"{len(x) / SR:.2f}s")


def groan(seed, dur, f_start, f_end):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f0 = np.linspace(f_start, f_end, n) * (1 + 0.08 * smooth_noise(n, 4, rng) + 0.03 * np.sin(2 * np.pi * 5.5 * t * dur))
    src = glottal(f0, rng, jitter=0.06, fry=0.55)
    # 숨소리 (갈라진 바람).
    breath = signal.lfilter(*signal.butter(2, [300 / (SR / 2), 3000 / (SR / 2)], "band"), rng.normal(0, 1, n)) * 0.35
    src = src / (np.max(np.abs(src)) + 1e-9) + breath * (0.4 + 0.4 * t)
    # 입 모양: '어' → '오' → '우' 쯤으로 천천히.
    f1 = np.interp(t, [0, 0.5, 1], [620, 520, 380]) * (1 + 0.05 * smooth_noise(n, 3, rng))
    f2 = np.interp(t, [0, 0.5, 1], [1050, 880, 760])
    f3 = np.full(n, 2350.0)
    x = vowel(src, f1, f2, f3)
    # 꾸르륵: 목에 고인 것을 통과하는 듯한 빠른 진폭 흔들림.
    gurgle = 1 - 0.55 * np.clip(smooth_noise(n, 26, rng) * 1.6, 0, 1)
    x *= gurgle * envelope(n, 0.18, 0.5)
    return room(finish(x, 2.6), rng, 0.18)


def snarl():
    rng = np.random.default_rng(41)
    dur = 0.75
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f0 = np.interp(t, [0, 0.25, 1], [95, 150, 110]) * (1 + 0.15 * smooth_noise(n, 30, rng))
    src = glottal(f0, rng, jitter=0.12, fry=0.8)
    noise = rng.normal(0, 1, n) * 0.9
    src = src / (np.max(np.abs(src)) + 1e-9) + noise
    x = vowel(src, np.interp(t, [0, 1], [780, 650]), np.full(n, 1250.0), np.full(n, 2600.0), gains=(1.0, 0.8, 0.4), bws=(160, 200, 300))
    # 이빨 사이로 끓는 소리: 30Hz 진폭 흔들림.
    x *= (0.55 + 0.45 * np.abs(np.sin(2 * np.pi * 31 * t * dur + smooth_noise(n, 8, rng)))) * envelope(n, 0.03, 0.3)
    return room(finish(x, 3.5), rng, 0.15, 0.25)


def shriek():
    rng = np.random.default_rng(77)
    dur = 1.3
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f0 = np.interp(t, [0, 0.15, 0.6, 1], [420, 1150, 980, 640]) * (1 + 0.04 * smooth_noise(n, 12, rng) + 0.03 * np.sin(2 * np.pi * 9 * t * dur))
    src = glottal(f0, rng, jitter=0.03, fry=0.2)
    src = src / (np.max(np.abs(src)) + 1e-9) + rng.normal(0, 1, n) * 0.45
    x = vowel(src, np.full(n, 950.0), np.interp(t, [0, 1], [1700, 1400]), np.full(n, 3200.0), gains=(1.0, 0.9, 0.6), bws=(150, 180, 260))
    # 사람이 아닌 소리: 링 모듈레이션으로 비튼다.
    ring = np.sin(2 * np.pi * np.cumsum(np.full(n, 173.0)) / SR)
    x = x * (0.6 + 0.4 * ring) * envelope(n, 0.05, 0.6)
    return room(finish(x, 4.0), rng, 0.3, 0.6)


def hit():
    rng = np.random.default_rng(13)
    dur = 0.32
    n = int(dur * SR)
    tt = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (75 * tt - 60 * tt * tt)) * np.exp(-tt * 22)
    wet = rng.normal(0, 1, n)
    sweep = np.interp(tt, [0, dur], [1800, 350])
    wet = resonator(wet, sweep, 260) * np.exp(-tt * 16) * 3.0
    crack = rng.normal(0, 1, n) * (rng.uniform(0, 1, n) > 0.985) * np.exp(-tt * 30) * 0.8
    x = thump * 0.9 + wet + crack
    return finish(x, 2.2)


def die():
    rng = np.random.default_rng(99)
    dur = 1.7
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f0 = np.interp(t, [0, 0.3, 1], [85, 62, 34]) * (1 + 0.12 * smooth_noise(n, 9, rng))
    src = glottal(f0, rng, jitter=0.15, fry=0.9)
    src = src / (np.max(np.abs(src)) + 1e-9) + rng.normal(0, 1, n) * (0.2 + 0.6 * t)
    x = vowel(src, np.interp(t, [0, 1], [560, 330]), np.interp(t, [0, 1], [900, 700]), np.full(n, 2200.0))
    rattle = 1 - 0.75 * np.clip(smooth_noise(n, 34, rng) * 2.0, 0, 1)
    x *= rattle * envelope(n, 0.08, 0.9)
    return room(finish(x, 2.8), rng, 0.2)


def heartbeat():
    rng = np.random.default_rng(5)
    dur = 0.5
    n = int(dur * SR)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for start, amp, f in [(0.0, 1.0, 52.0), (0.16, 0.7, 46.0)]:
        u = tt - start
        m = u >= 0
        env = np.where(m, np.exp(-np.maximum(u, 0) * 24) * (1 - np.exp(-np.maximum(u, 0) * 400)), 0)
        x += amp * env * np.sin(2 * np.pi * f * np.maximum(u, 0) * (1 - 0.3 * np.maximum(u, 0)))
        # 가슴 안의 둔한 울림 (낮게 거른 잡음).
        noise = signal.lfilter(*signal.butter(2, 180 / (SR / 2), "low"), rng.normal(0, 1, n))
        x += 0.25 * amp * env * noise / (np.max(np.abs(noise)) + 1e-9)
    return finish(x, 1.6)


def fear_sting():
    rng = np.random.default_rng(66)
    dur = 2.4
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    tt = np.arange(n) / SR
    # 낮은 불협 화음 (반음 · 증4도) 이 부풀어 오른다.
    x = np.zeros(n)
    for f, a in [(55.0, 1.0), (58.3, 0.8), (77.8, 0.6), (110.0, 0.4), (116.5, 0.35)]:
        x += a * np.sin(2 * np.pi * f * tt * (1 + 0.004 * np.sin(2 * np.pi * 0.7 * tt)))
    swell = np.clip(t / 0.55, 0, 1) ** 2.5 * np.exp(-np.maximum(t - 0.55, 0) * 3.0)
    x *= swell
    # 쇠를 긁는 듯한 높은 소리 (줄 긁기).
    scrape = resonator(rng.normal(0, 1, n), np.interp(t, [0, 0.5, 1], [2400, 3100, 1900]), 60) * 6
    scrape *= np.clip((t - 0.38) / 0.12, 0, 1) * np.exp(-np.maximum(t - 0.5, 0) * 4.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * tt))
    x = x / (np.max(np.abs(x)) + 1e-9) + 0.45 * scrape / (np.max(np.abs(scrape)) + 1e-9)
    return room(finish(x, 1.8), rng, 0.35, 0.9)


def main():
    write("creature_groan_1", groan(1, 1.9, 82, 64))
    write("creature_groan_2", groan(2, 1.5, 96, 72))
    write("creature_groan_3", groan(3, 2.2, 70, 58))
    write("creature_snarl", snarl())
    write("creature_shriek", shriek())
    write("creature_hit", hit())
    write("creature_die", die())
    write("heartbeat", heartbeat())
    write("fear_sting", fear_sting())


if __name__ == "__main__":
    main()
