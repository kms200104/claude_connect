#!/usr/bin/env python3
"""솔바람 마을의 효과음과 배경음악을 합성한다 (외부 음원 없음, 모두 이 스크립트로 만든 오리지널).

  assets/audio/sfx/*.wav     22.05kHz 모노 16bit — 발소리, 달리기, 낚시, 도끼질, 주민 말소리, 비·천둥, 새·풀벌레, UI
  assets/audio/music/*.ogg   32kHz 스테레오 Vorbis — title_theme(오르골 왈츠), village_theme(느긋한 칼림바 로파이)
사용: python3 tools/audio/gen_audio.py   (numpy, scipy, ffmpeg 필요)
"""
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets/audio/sfx"
MUSIC_DIR = ROOT / "assets/audio/music"
SR = 22050
MSR = 32000
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- 공용 도구

def t_axis(seconds: float, sr: int = SR) -> np.ndarray:
    return np.arange(int(seconds * sr)) / sr


def env_ad(n: int, attack: float, decay: float, sr: int = SR) -> np.ndarray:
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))


def onepole_lp(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
    a = np.exp(-2 * np.pi * cutoff / sr)
    return lfilter([1 - a], [1, -a], x)


def biquad_bp(x: np.ndarray, f0: float, q: float, sr: int = SR) -> np.ndarray:
    """대역 통과 (RBJ). f0 는 배열이어도 된다 (스윕)."""
    if np.isscalar(f0):
        w = 2 * np.pi * min(f0, sr * 0.45) / sr
        alpha = np.sin(w) / (2 * q)
        return lfilter([alpha, 0, -alpha], [1 + alpha, -2 * np.cos(w), 1 - alpha], x)
    f0 = np.broadcast_to(np.asarray(f0, dtype=float), x.shape)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w = 2 * np.pi * min(f0[i], sr * 0.45) / sr
        alpha = np.sin(w) / (2 * q)
        b0, b2 = alpha, -alpha
        a0, a1, a2 = 1 + alpha, -2 * np.cos(w), 1 - alpha
        v = (b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, v
        y[i] = v
    return y


def highpass(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
    return x - onepole_lp(x, cutoff, sr)


def noise(n: int) -> np.ndarray:
    return rng.uniform(-1, 1, n)


def normalize(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x / m * peak


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01, sr: int = SR) -> np.ndarray:
    x = x.copy()
    a = min(int(fin * sr), len(x))
    b = min(int(fout * sr), len(x))
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def save_wav(name: str, x: np.ndarray, peak: float = 0.9) -> None:
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    data = (normalize(x, peak) * 32767).astype(np.int16)
    with wave.open(str(SFX_DIR / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("sfx", name, f"{len(x) / SR:.2f}s")


def loop_crossfade(x: np.ndarray, seconds: float, sr: int = SR) -> np.ndarray:
    """끝을 앞에 겹쳐 이음매 없이 반복되는 루프로."""
    n = int(seconds * sr)
    head = x[:n].copy()
    body = x[n:].copy()
    ramp = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * (1 - ramp) + head * ramp
    return body


def tone(freq: float, seconds: float, partials=((1, 1.0),), decay: float = 0.3, attack: float = 0.004, sr: int = SR) -> np.ndarray:
    t = t_axis(seconds, sr)
    x = np.zeros_like(t)
    for mult, amp in partials:
        x += amp * np.sin(2 * np.pi * freq * mult * t) * np.exp(-t / (decay / max(mult, 1) ** 0.5))
    return x * env_ad(len(t), attack, 10.0, sr)


def mix_at(dst: np.ndarray, src: np.ndarray, start: int, gain: float = 1.0) -> None:
    end = min(len(dst), start + len(src))
    if end > start:
        dst[start:end] += src[: end - start] * gain


# ---------------------------------------------------------------- 효과음

def footsteps() -> None:
    for i in range(3):
        # 풀: 사각사각한 잎 소리 (중고역 노이즈를 짧게).
        n = int(0.11 * SR)
        x = biquad_bp(noise(n), 2400 + 400 * i, 0.9) * env_ad(n, 0.008, 0.035)
        x += 0.4 * biquad_bp(noise(n), 5200, 1.5) * env_ad(n, 0.004, 0.02)
        save_wav(f"step_grass_{i + 1}", fade(x), 0.55)
        # 흙길: 서걱 + 자잘한 모래 알갱이.
        n = int(0.12 * SR)
        x = biquad_bp(noise(n), 1500 + 250 * i, 0.7) * env_ad(n, 0.004, 0.04)
        grains = (rng.random(n) > 0.985) * noise(n) * env_ad(n, 0.002, 0.05)
        x += 0.9 * highpass(grains, 2500)
        x += 0.5 * tone(110 + 10 * i, 0.12, decay=0.03)
        save_wav(f"step_dirt_{i + 1}", fade(x), 0.6)
        # 달리기: 더 세고 짧은 착지 + 옷자락 스치는 소리.
        n = int(0.14 * SR)
        x = biquad_bp(noise(n), 1900 + 300 * i, 0.8) * env_ad(n, 0.003, 0.03)
        x += 0.8 * tone(90 + 12 * i, 0.14, decay=0.04)
        swish = biquad_bp(noise(n), np.linspace(900, 3000, n), 2.0) * env_ad(n, 0.04, 0.05)
        x += 0.35 * swish
        save_wav(f"step_run_{i + 1}", fade(x), 0.72)
    for i in range(2):
        # 나무 선착장: 통통 울리는 판자.
        n = int(0.16 * SR)
        x = tone(190 + 25 * i, 0.16, ((1, 1.0), (2.7, 0.4)), decay=0.05)
        x += 0.5 * biquad_bp(noise(n), 900, 1.2) * env_ad(n, 0.002, 0.015)
        save_wav(f"step_wood_{i + 1}", fade(x), 0.6)


def fishing() -> None:
    # 던지기: 휙 (노이즈 대역이 올라갔다 내려온다).
    n = int(0.42 * SR)
    sweep = np.concatenate([np.linspace(700, 3200, n // 2), np.linspace(3200, 1200, n - n // 2)])
    x = biquad_bp(noise(n), sweep, 3.0) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
    save_wav("fish_cast", fade(x), 0.6)
    # 퐁당: 물방울 (음높이가 빠르게 오르는 사인) + 물보라.
    n = int(0.35 * SR)
    t = t_axis(0.35)
    f = 500 + 1400 * (1 - np.exp(-t * 30))
    drop = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.002, 0.06)
    splash = biquad_bp(noise(n), 2500, 0.8) * env_ad(n, 0.002, 0.08)
    save_wav("fish_plop", fade(drop + 0.5 * splash), 0.7)
    # 입질: 작고 맑은 퐁.
    n = int(0.12 * SR)
    t = t_axis(0.12)
    f = 900 + 900 * (1 - np.exp(-t * 60))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.002, 0.03)
    save_wav("fish_nibble", fade(x), 0.45)
    # 물었다!: 첨벙 + 거품.
    n = int(0.7 * SR)
    x = biquad_bp(noise(n), np.linspace(3000, 900, n), 0.7) * env_ad(n, 0.003, 0.18)
    for k in range(9):
        start = int(rng.uniform(0.05, 0.5) * SR)
        bt = t_axis(0.06)
        bf = rng.uniform(700, 1600) * (1 + 2 * bt)
        mix_at(x, np.sin(2 * np.pi * np.cumsum(bf) / SR) * env_ad(len(bt), 0.002, 0.02), start, 0.35)
    save_wav("fish_bite", fade(x), 0.8)
    # 릴 감기: 촤르륵 톱니 소리.
    x = np.zeros(int(0.9 * SR))
    pos = 0.0
    k = 0
    while pos < 0.85:
        click = biquad_bp(noise(int(0.012 * SR)), 3500, 2.0) * env_ad(int(0.012 * SR), 0.0005, 0.004)
        mix_at(x, click, int(pos * SR), 0.8 if k % 2 == 0 else 0.5)
        pos += 0.028 - 0.01 * (pos / 0.9)
        k += 1
    save_wav("fish_reel", fade(x), 0.55)
    # 잡았다: 칼림바 아르페지오.
    x = np.zeros(int(1.2 * SR))
    for i, semi in enumerate([0, 4, 7, 12, 16]):
        mix_at(x, kalimba(523.25 * 2 ** (semi / 12), 0.8, SR), int(i * 0.09 * SR), 0.7)
    save_wav("fish_catch", fade(x, fout=0.05), 0.75)
    # 놓쳤다: 내려가는 두 음.
    x = np.zeros(int(0.8 * SR))
    mix_at(x, kalimba(392.0, 0.5, SR), 0, 0.7)
    mix_at(x, kalimba(311.1, 0.6, SR), int(0.16 * SR), 0.7)
    save_wav("fish_escape", fade(x, fout=0.05), 0.6)


def chopping() -> None:
    # 도끼질: 통! 나무에 박히는 둔탁한 소리.
    n = int(0.3 * SR)
    t = t_axis(0.3)
    body = np.sin(2 * np.pi * (150 * t - 40 * t * t)) * env_ad(n, 0.001, 0.07)
    knock = tone(420, 0.3, ((1, 1.0), (2.3, 0.5)), decay=0.03)
    crack = highpass(noise(n), 2000) * env_ad(n, 0.0005, 0.012)
    save_wav("chop", fade(body + 0.6 * knock + 0.5 * crack), 0.85)
    # 쓰러짐: 우지끈 + 잎 흔들림 + 쿵.
    n = int(1.3 * SR)
    x = np.zeros(n)
    for k in range(18):
        start = int(rng.uniform(0.0, 0.45) * SR)
        mix_at(x, highpass(noise(int(0.02 * SR)), 1500) * env_ad(int(0.02 * SR), 0.0005, 0.006), start, rng.uniform(0.3, 0.8))
    leaves = biquad_bp(noise(n), 4000, 0.8) * np.exp(-((t_axis(1.3) - 0.5) ** 2) / 0.06)
    x += 0.5 * leaves
    thud_t = t_axis(0.6)
    thud = np.sin(2 * np.pi * (70 * thud_t - 25 * thud_t ** 2)) * env_ad(len(thud_t), 0.003, 0.14)
    mix_at(x, thud, int(0.62 * SR), 1.3)
    save_wav("tree_fall", fade(x, fout=0.08), 0.85)
    # 아이템 얻음: 뽀옹.
    n = int(0.22 * SR)
    t = t_axis(0.22)
    f = 520 * (1 + 1.2 * (1 - np.exp(-t * 25)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.003, 0.07)
    x += 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR) * env_ad(n, 0.003, 0.04)
    save_wav("pickup", fade(x), 0.6)


def voices() -> None:
    """주민 말소리 '웅앵': 성대 펄스(톱니)를 모음 포먼트 두 개로 거른 짧은 음절. 재생할 때 주민마다 음높이를 바꾼다."""
    formants = {"a": (800, 1250), "e": (480, 2000), "i": (320, 2500), "o": (520, 900), "u": (370, 780)}
    for vowel, (f1, f2) in formants.items():
        dur = 0.12
        n = int(dur * SR)
        t = t_axis(dur)
        f0 = 240 * (1 + 0.12 * np.sin(np.pi * t / dur)) * (1 - 0.1 * t / dur)
        phase = np.cumsum(f0) / SR
        saw = 2 * (phase % 1.0) - 1
        x = biquad_bp(saw, f1, 5.0) + 0.6 * biquad_bp(saw, f2, 7.0)
        # 앞쪽은 콧소리(ㅇ/ㅁ)처럼 뭉툭하게.
        nasal = onepole_lp(saw, 500) * np.exp(-t / 0.02)
        x = x + 0.6 * nasal
        x *= np.sin(np.clip(t / dur, 0, 1) * np.pi) ** 0.6
        save_wav(f"voice_{vowel}", fade(x, 0.004, 0.02), 0.6)


def weather() -> None:
    # 빗소리: 쏴아 (분홍빛 노이즈) + 톡톡 떨어지는 빗방울. 이음매 없이 반복.
    seconds = 4.0 + 0.5
    n = int(seconds * SR)
    white = noise(n)
    hiss = onepole_lp(white, 3500) - onepole_lp(white, 300)
    x = 0.6 * hiss
    for k in range(int(seconds * 45)):
        start = int(rng.uniform(0, seconds - 0.05) * SR)
        dt = t_axis(0.03)
        f = rng.uniform(1800, 4200)
        drop = np.sin(2 * np.pi * f * dt) * env_ad(len(dt), 0.0005, 0.006)
        mix_at(x, drop, start, rng.uniform(0.15, 0.5))
    save_wav("rain_loop", loop_crossfade(x, 0.5), 0.5)
    # 천둥: 우르릉 (낮은 노이즈가 천천히 사라진다).
    for i in range(2):
        seconds = 3.2
        n = int(seconds * SR)
        t = t_axis(seconds)
        rumble = onepole_lp(onepole_lp(noise(n), 120 + 40 * i), 160)
        crack = highpass(noise(n), 1200) * np.exp(-t / 0.08) * (0.6 if i == 0 else 0.25)
        swell = (1 - np.exp(-t / 0.15)) * np.exp(-t / (1.1 + 0.4 * i))
        wobble = 1 + 0.5 * np.sin(2 * np.pi * (2.5 + i) * t)
        save_wav(f"thunder_{i + 1}", fade(rumble * swell * wobble * 4 + crack, 0.001, 0.3), 0.95)
    # 새소리 (맑은 낮): 짧은 휘파람 지저귐 몇 번, 이음매 없이 반복.
    seconds = 8.5
    x = np.zeros(int(seconds * SR))
    for k in range(9):
        start = rng.uniform(0.2, seconds - 1.0)
        base = rng.uniform(2600, 3800)
        for j in range(rng.integers(2, 5)):
            dur = rng.uniform(0.05, 0.1)
            ct = t_axis(dur)
            f = base * (1 + 0.25 * np.sin(np.pi * ct / dur)) * (1.0 + 0.1 * j)
            chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * ct / dur) ** 2
            mix_at(x, chirp, int((start + j * 0.11) * SR), rng.uniform(0.3, 0.6))
    save_wav("birds_loop", loop_crossfade(x, 0.5), 0.35)
    # 풀벌레 (밤): 찌르르 떨리는 고음.
    seconds = 6.5
    n = int(seconds * SR)
    t = t_axis(seconds)
    x = np.zeros(n)
    for f, rate, ph in ((4200, 18, 0.0), (4700, 23, 1.3), (3900, 15, 2.1)):
        trill = (np.sin(2 * np.pi * rate * t + ph) > 0.2).astype(float)
        trill = onepole_lp(trill, 200)
        gate = (np.sin(2 * np.pi * 0.35 * t + ph * 2) > -0.3).astype(float)
        x += np.sin(2 * np.pi * f * t) * trill * onepole_lp(gate, 5)
    save_wav("crickets_loop", loop_crossfade(x, 0.5), 0.25)


def ui() -> None:
    n = int(0.06 * SR)
    save_wav("ui_click", fade(tone(1250, 0.06, ((1, 1.0), (2, 0.3)), decay=0.015)), 0.45)
    # 가방 열기·닫기: 부스럭 + 똑딱.
    for name, sweep in (("ui_open", (1500, 3500)), ("ui_close", (3200, 1400))):
        n = int(0.2 * SR)
        x = biquad_bp(noise(n), np.linspace(*sweep, n), 1.5) * env_ad(n, 0.01, 0.06)
        x += 0.5 * tone(880 if name == "ui_open" else 660, 0.2, decay=0.03)
        save_wav(name, fade(x), 0.5)
    for name, notes in (("ui_confirm", (659.3, 987.8)), ("ui_cancel", (523.3, 392.0))):
        x = np.zeros(int(0.35 * SR))
        for i, f in enumerate(notes):
            mix_at(x, kalimba(f, 0.3, SR), int(i * 0.07 * SR), 0.7)
        save_wav(name, fade(x, fout=0.03), 0.5)
    # 동전: 짤랑 (높은 종소리 두 개).
    x = np.zeros(int(0.5 * SR))
    for i, f in enumerate((1975.5, 2637.0)):
        mix_at(x, tone(f, 0.45, ((1, 1.0), (2.76, 0.3), (5.4, 0.1)), decay=0.12), int(i * 0.06 * SR), 0.6)
    save_wav("coin", fade(x, fout=0.05), 0.55)
    # 상점 문 종: 딩동.
    x = np.zeros(int(1.0 * SR))
    mix_at(x, tone(1318.5, 0.9, ((1, 1.0), (2.76, 0.4), (5.4, 0.15)), decay=0.35), 0, 0.7)
    mix_at(x, tone(1046.5, 0.9, ((1, 1.0), (2.76, 0.4), (5.4, 0.15)), decay=0.35), int(0.18 * SR), 0.7)
    save_wav("door_bell", fade(x, fout=0.1), 0.55)
    # 부탁 완료: 짧은 축하 멜로디.
    x = np.zeros(int(1.4 * SR))
    for i, semi in enumerate([0, 4, 7, 9, 7, 12]):
        mix_at(x, kalimba(587.3 * 2 ** (semi / 12), 0.6, SR), int(i * 0.11 * SR), 0.65)
    save_wav("quest_done", fade(x, fout=0.08), 0.7)
    # 상점 성장: 팡파레 (화음 세 번).
    x = np.zeros(int(2.2 * SR))
    for i, chord in enumerate(([0, 4, 7], [2, 5, 9], [4, 7, 12, 16])):
        for semi in chord:
            mix_at(x, kalimba(523.25 * 2 ** (semi / 12), 1.2 if i == 2 else 0.5, SR), int(i * 0.22 * SR), 0.45)
    save_wav("level_up", fade(x, fout=0.2), 0.75)


# ---------------------------------------------------------------- 악기 (음악·효과음 공용)

def kalimba(freq: float, seconds: float, sr: int) -> np.ndarray:
    t = t_axis(seconds, sr)
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.5)
    x += 0.25 * np.sin(2 * np.pi * freq * 2.01 * t) * np.exp(-t / 0.18)
    x += 0.12 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t / 0.04)
    return x * env_ad(len(t), 0.002, 10.0, sr)


def music_box(freq: float, seconds: float, sr: int) -> np.ndarray:
    t = t_axis(seconds, sr)
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.9)
    x += 0.35 * np.sin(2 * np.pi * freq * 3.0 * t) * np.exp(-t / 0.3)
    x += 0.15 * np.sin(2 * np.pi * freq * 6.2 * t) * np.exp(-t / 0.08)
    return x * env_ad(len(t), 0.001, 10.0, sr)


def epiano(freq: float, seconds: float, sr: int) -> np.ndarray:
    t = t_axis(seconds, sr)
    index = 1.4 * np.exp(-t / 0.25)
    x = np.sin(2 * np.pi * freq * t + index * np.sin(2 * np.pi * freq * t))
    return x * env_ad(len(t), 0.005, 0.9, sr) * (1 - np.exp(-(seconds - t) / 0.05))


def bass(freq: float, seconds: float, sr: int) -> np.ndarray:
    t = t_axis(seconds, sr)
    x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    return x * env_ad(len(t), 0.008, 0.45, sr) * (1 - np.exp(-(seconds - t) / 0.03))


def pad(freqs, seconds: float, sr: int) -> np.ndarray:
    t = t_axis(seconds, sr)
    x = np.zeros_like(t)
    for f in freqs:
        for det in (-0.6, 0.6):
            x += np.sin(2 * np.pi * (f + det) * t + rng.uniform(0, 6))
    attack = np.clip(t / 0.6, 0, 1)
    release = np.clip((seconds - t) / 0.6, 0, 1)
    return x * attack * release / (len(freqs) * 2)


def shaker(sr: int, accent: float) -> np.ndarray:
    n = int(0.05 * sr)
    return highpass(noise(n), 6000, sr) * env_ad(n, 0.004, 0.012, sr) * accent


def soft_kick(sr: int) -> np.ndarray:
    t = t_axis(0.25, sr)
    f = 45 + 70 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / sr) * env_ad(len(t), 0.002, 0.09, sr)


def woodblock(sr: int) -> np.ndarray:
    return tone(820, 0.08, ((1, 1.0), (2.4, 0.4)), decay=0.02, sr=sr)


def reverb(x: np.ndarray, sr: int, mix: float = 0.25) -> np.ndarray:
    """간단한 슈뢰더 잔향 (빗살 4개 + 올패스 2개)."""
    out = np.zeros_like(x)
    for delay_ms, g in ((29.7, 0.8), (37.1, 0.78), (41.1, 0.76), (43.7, 0.74)):
        d = int(delay_ms * sr / 1000)
        a = np.zeros(d + 1)
        a[0], a[d] = 1.0, -g
        out += onepole_lp(lfilter([1.0], a, x), 4500, sr)
    out /= 4
    for delay_ms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = int(delay_ms * sr / 1000)
        b = np.zeros(d + 1)
        a = np.zeros(d + 1)
        b[0], b[d] = -g, 1.0
        a[0], a[d] = 1.0, -g
        out = lfilter(b, a, out)
    return x * (1 - mix) + out * mix


def midi(n: int) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- 작곡

MAJOR = [0, 2, 4, 5, 7, 9, 11]


def make_melody(chords, beats_per_bar: int, key: int, seed: int, low: int, high: int):
    """화음 진행 위에 선율을 짓는다: 센박은 화음음, 여린박은 음계 순차 진행, 4마디마다 긴 화음음으로 맺는다."""
    r = np.random.default_rng(seed)
    scale = [key + s + 12 * o for o in range(-1, 4) for s in MAJOR]
    scale = [n for n in scale if low <= n <= high]
    rhythms4 = [[1, 1, 2], [0.5, 0.5, 1, 1, 1], [1.5, 0.5, 2], [1, 0.5, 0.5, 2], [2, 1, 1], [0.5, 0.5, 0.5, 0.5, 2]]
    rhythms3 = [[1, 1, 1], [2, 1], [1, 0.5, 0.5, 1], [1.5, 0.5, 1]]
    notes = []
    current = scale[len(scale) // 2]
    phrase_rhythms = {}
    for bar, chord in enumerate(chords):
        tones = [n for n in scale if (n - chord[0]) % 12 in [(c - chord[0]) % 12 for c in chord]]
        end_of_phrase = bar % 4 == 3
        if end_of_phrase:
            rhythm = [beats_per_bar]
        else:
            # 같은 자리의 마디는 같은 리듬을 다시 써서 노래처럼 들리게.
            slot = bar % 8
            if slot not in phrase_rhythms:
                pool = rhythms4 if beats_per_bar == 4 else rhythms3
                phrase_rhythms[slot] = pool[r.integers(len(pool))]
            rhythm = phrase_rhythms[slot]
        beat = 0.0
        for k, dur in enumerate(rhythm):
            strong = beat == 0 or (beats_per_bar == 4 and beat == 2)
            if strong or end_of_phrase:
                target = min(tones, key=lambda n: abs(n - current) + r.uniform(0, 3))
            else:
                idx = min(range(len(scale)), key=lambda i: abs(scale[i] - current))
                step = r.choice([-1, 1, 1, -2, 2]) if r.random() < 0.85 else r.choice([-3, 3])
                idx = int(np.clip(idx + step, 0, len(scale) - 1))
                target = scale[idx]
            current = target
            notes.append((bar * beats_per_bar + beat, dur, target))
            beat += dur
    return notes


def render_song(name: str, bpm: float, beats_per_bar: int, chords, key: int, lead, seed: int, groove: str) -> None:
    beat_s = 60.0 / bpm
    bars = len(chords)
    length = bars * beats_per_bar * beat_s
    tail = 3.0
    n = int((length + tail) * MSR)
    left = np.zeros(n)
    right = np.zeros(n)

    def put(sig, at_beats, gain, pan=0.0):
        start = int(at_beats * beat_s * MSR)
        mix_at(left, sig, start, gain * (1 - max(pan, 0)))
        mix_at(right, sig, start, gain * (1 + min(pan, 0)))

    melody = make_melody(chords, beats_per_bar, key, seed, key + 5, key + 26)
    for at, dur, note in melody:
        put(lead(midi(note), dur * beat_s + 0.6, MSR), at, 0.32, 0.1)
        # 두 번째 반복부터 옥타브 위 메아리.
        if at >= bars * beats_per_bar / 2:
            put(lead(midi(note + 12), dur * beat_s + 0.3, MSR), at + 0.5 * (beats_per_bar == 4), 0.08, -0.4)
    for bar, chord in enumerate(chords):
        start = bar * beats_per_bar
        root = chord[0]
        put(pad([midi(c) for c in chord], beats_per_bar * beat_s + 0.4, MSR), start, 0.12)
        if groove == "waltz":
            put(bass(midi(root - 12), beat_s * 1.0, MSR), start, 0.32)
            for b in (1, 2):
                for c in chord[1:]:
                    put(music_box(midi(c), beat_s * 0.9, MSR), start + b, 0.07, 0.3)
        else:
            put(bass(midi(root - 12), beat_s * 1.6, MSR), start, 0.34)
            put(bass(midi(root - 12 + 7), beat_s * 0.9, MSR), start + 2.5, 0.22)
            for b, length_beats in ((0, 1.2), (1.5, 0.8), (3, 0.9)):
                for c in chord:
                    put(epiano(midi(c), beat_s * length_beats, MSR), start + b, 0.06, -0.2)
            for half in range(beats_per_bar * 2):
                put(shaker(MSR, 1.0 if half % 2 else 0.55), start + half * 0.5, 0.05, 0.5)
            put(soft_kick(MSR), start, 0.22)
            put(soft_kick(MSR), start + 2, 0.15)
            put(woodblock(MSR), start + 1, 0.05, -0.5)
            put(woodblock(MSR), start + 3, 0.05, -0.5)

    left = reverb(left, MSR, 0.28)
    right = reverb(right, MSR, 0.28)
    # 이음매 없는 반복: 곡 끝을 넘어간 잔향을 처음에 겹친다.
    loop_n = int(length * MSR)
    for ch in (left, right):
        ch[: n - loop_n] += ch[loop_n:]
    stereo = np.stack([left[:loop_n], right[:loop_n]], axis=1)
    stereo = stereo / np.max(np.abs(stereo)) * 0.85
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    raw = (stereo * 32767).astype(np.int16).tobytes()
    out = MUSIC_DIR / f"{name}.ogg"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(MSR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "3", str(out)], input=raw, check=True)
    print("music", name, f"{length:.1f}s", out.stat().st_size // 1024, "KB")


def music() -> None:
    # 첫 화면: C장조 오르골 왈츠 (3/4, 96bpm).
    C, Am, F, G, Em, Dm = [60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 55, 59], [50, 53, 57]
    title = [C, Am, F, G, C, Em, F, G, F, G, Em, Am, Dm, G, C, C]
    render_song("title_theme", 96, 3, title * 2, 60, music_box, 11, "waltz")
    # 마을: F장조 느긋한 칼림바 (4/4, 84bpm). Fmaj7 - Em7 - Dm7 - Cmaj7 - Bbmaj7 - Am7 - Gm7 - C7sus.
    Fm7, Em7, Dm7, Cm7, Bb7, Am7, Gm7, C7s = ([53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59],
                                              [46, 50, 53, 57], [45, 48, 52, 55], [43, 46, 50, 53], [48, 53, 55, 58])
    verse = [Fm7, Em7, Dm7, Cm7, Bb7, Am7, Gm7, C7s]
    bridge = [Bb7, Cm7, Am7, Dm7, Gm7, Am7, Bb7, C7s]
    render_song("village_theme", 84, 4, verse + verse + bridge + verse, 65, kalimba, 5, "lofi")


if __name__ == "__main__":
    footsteps()
    fishing()
    chopping()
    voices()
    weather()
    ui()
    music()
