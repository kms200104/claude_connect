#!/usr/bin/env python3
"""
CC0 실제 녹음으로 효과음 · 환경음 만들기 (합성 파형 대신).

받아 둔 두 묶음에서 소리를 골라 자르고 · 겹치고 · 음높이를 바꾸고 · 크기를 맞춰 assets/audio/sfx/<id>.wav (모노 16bit) 로 쓴다.
  - CC0-Public-Domain-Sounds  https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds  (CC0 1.0, 묶음별 원작자는 CREDITS.md)
  - Noisekun 환경음            https://github.com/mateusfg7/noisekun  (.github/assets/sounds, 여기서 쓰는 것은 모두 CC0)

사용:
  git clone --depth 1 https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds /tmp/cc0
  git clone --depth 1 https://github.com/mateusfg7/noisekun /tmp/noisekun
  python3 tools/audio/import_cc0_sfx.py --cc0 /tmp/cc0 --noisekun /tmp/noisekun [--only fish_bite,chop]

크기: 지금까지 합성음과 같은 크기로 들리도록 A 가중 평균 크기(소리가 나는 구간)를 TARGET 에 맞춘다 (게임 코드의 볼륨 값을 그대로 쓸 수 있게).
반복 소리(_loop)는 끝과 처음을 겹쳐 이음매 없이 돌게 만든다.
필요: numpy, scipy, ffmpeg (ogg · mp3 읽기).
"""

import argparse
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy.signal import bilinear_zpk, butter, resample_poly, sosfilt, zpk2sos

ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets/audio/sfx"
SR = 44100
LOOP_SR = 32000

# 합성음 때의 A 가중 크기(dB) — 게임 안 볼륨 균형을 지킨다. 천둥은 원래보다 조금 크게.
TARGET = {
    "birds_loop": -20.4, "camera_shutter": -18.6, "cash_in": -13.0, "chop": -17.0, "coin": -15.5,
    "cook_bubble": -18.1, "cook_chop": -18.5, "cook_plate": -17.2, "cook_sizzle": -18.5, "crickets_loop": -22.1,
    "dig": -19.0, "door_bell": -16.5, "emote_down": -17.5, "emote_hey": -16.0, "emote_pop": -16.6,
    "emote_up": -15.6, "event_start": -16.0, "fanfare_big": -14.8, "fanfare_small": -14.8, "fish_bite": -15.5,
    "fish_cast": -16.5, "fish_catch": -15.7, "fish_escape": -17.5, "fish_nibble": -18.5, "fish_plop": -17.0,
    "fish_reel": -22.0, "grow": -19.4, "kick_brake": -19.5, "kick_latch": -16.0, "kick_push": -19.0,
    "kick_roll_loop": -21.0, "level_up": -14.0, "line_zip": -19.5, "order_bell": -14.5, "pickup": -16.0,
    "plane_loop": -26.0, "quest_done": -13.5, "rain_loop": -22.5, "skid": -16.0, "thunder_1": -18.0,
    "thunder_2": -18.5, "thunder_roll": -17.0, "thunder_far": -22.0, "tree_creak": -18.0, "tree_land": -15.5, "twinkle": -18.0, "ui_cancel": -19.1,
    "ui_click": -18.0, "ui_close": -20.9, "ui_confirm": -17.0, "ui_open": -19.8,
}

WATER = "cc0:40-cc0-water-splash-slime-sfx"
WOOD = "cc0:100-CC0-wood-metal-SFX"
BFH = "cc0:75-cc0-breaking-falling-hit-sfx"
SFX100 = "cc0:100-CC0-SFX"
RPG80 = "cc0:80-CC0-RPG-SFX"
KRPG = "cc0:kenney_rpgaudio/Audio"
KIMP = "cc0:kenney_impactsounds/Audio"
KUIA = "cc0:kenney_uiaudio/Audio"
KJ = "cc0:kenney_musicjingles/Audio"
MECH = "cc0:bb - Smol Mechanisms (May 2021)"
WOOSH = "cc0:Micro Pack - Organic Wooshes"
KNIFE = "cc0:Micro Pack - Kitchen Knives"
RETAIL = "cc0:BB_Retail Therapy Sample Pack"
LOOPS = "cc0:30-cc0-sfx-loops"
MUD = "cc0:25-CC0-mud-sfx"
NK = "nk:"


def L(src: str, start: float = 0.0, end: float | None = None, at: float = 0.0, gain: float = 0.0,
      pitch: float = 0.0, hp: float = 40.0, lp: float = 0.0, fin: float = 0.003, fout: float = 0.02) -> dict:
    """겹칠 소리 한 줄: src 의 start~end 초를 잘라 at 초에 gain dB 로 놓는다. pitch 반음 (길이도 바뀐다)."""
    return dict(src=src, start=start, end=end, at=at, gain=gain, pitch=pitch, hp=hp, lp=lp, fin=fin, fout=fout)


# 소리마다: layers (겹칠 녹음들), 그리고 선택으로 length(최대 길이) · loop(이음 겹침 초) · fout(끝 사라짐 초).
RECIPES: dict[str, dict] = {
    # ---- 낚시 ----
    # 찌가 수면에 톡 닿는 소리 (작은 물체가 떨어지는 짧은 첨벙).
    "fish_plop": dict(layers=[L(f"{WATER}/splash_09.ogg", 0.0, 0.34), L(f"{WATER}/splash_10.ogg", 0.0, 0.2, 0.004, -12.0, pitch=3.0)]),
    # 입질 전 찌를 살짝 건드림: 아주 작은 톡 (높고 짧게).
    "fish_nibble": dict(layers=[L(f"{WATER}/splash_10.ogg", 0.0, 0.22, pitch=4.0, fout=0.08)]),
    # 진짜 입질: 물고기가 찌를 물고 끌어들이는 '꿀꺽' 첨벙 + 물속으로 잠기는 뽀글.
    "fish_bite": dict(layers=[L(f"{WATER}/splash_04.ogg", 0.12, 0.85), L(f"{SFX100}/plop_02.ogg", 0.09, 0.33, 0.07, -4.0, pitch=-3.0),
                              L(f"{WATER}/bubble_01.ogg", 0.0, 0.5, 0.25, -10.0, pitch=2.0, fout=0.2)], fout=0.25),
    # 낚싯대를 휘두르는 바람 소리.
    "fish_cast": dict(layers=[L(f"{WOOSH}/Swish 1.wav", 0.0, 0.3, hp=180.0, fout=0.1)]),
    # 던질 때 릴에서 줄이 빠르게 풀리는 '지이익'.
    "line_zip": dict(layers=[L(f"{MECH}/Ratchet Muted 1.wav", 0.0, 0.2, pitch=3.0, fout=0.06)]),
    # 감기 (누를 때마다 릴을 한 바퀴): 릴 래칫 딸깍딸깍.
    "fish_reel": dict(layers=[L(f"{MECH}/Ratchet Harsh 1.wav", 0.0, 0.3, fout=0.05)]),
    # 끌어올림: 물 밖으로 나오며 퍼덕이는 첨벙첨벙.
    "fish_catch": dict(layers=[L(f"{WATER}/splash_08.ogg", 0.0, 0.62), L(f"{WATER}/splash_06.ogg", 0.0, 0.42, 0.18, -5.0)], fout=0.2),
    # 놓침: 몸부림치다 물속으로 빠져 사라짐.
    "fish_escape": dict(layers=[L(f"{WATER}/splash_07.ogg", 0.0, 0.95)], fout=0.35),
    # ---- 나무 ----
    # 도끼질: 실제 도끼 찍는 소리 + 나무 몸통의 둔탁함 + 낮은 쿵.
    "chop": dict(layers=[L(f"{KRPG}/chop.ogg", 0.035, 0.24), L(f"{WOOD}/wood_hit_03.ogg", 0.0, 0.3, 0.004, -6.0),
                         L(f"{KIMP}/impactWood_heavy_000.ogg", 0.0, 0.25, 0.0, -8.0)]),
    # 쓰러지기 시작: 섬유가 찢어지는 우지끈 + 길게 끄는 삐걱 (넘어지는 0.9초 동안).
    "tree_creak": dict(layers=[L(f"{WOOD}/wood_cracking_01.ogg", 0.0, 0.5), L(f"{KRPG}/creak2.ogg", 0.22, 0.83, 0.12, -2.0, pitch=-5.0),
                               L(f"{WOOD}/wood_cracking_03.ogg", 0.0, 0.5, 0.45, -5.0)], fout=0.2),
    # 땅에 닿음: 둔중한 쿵 + 가지가 부러지는 우두둑 + 잎이 흩어지는 쏴아.
    "tree_land": dict(layers=[L(f"{KIMP}/impactSoft_heavy_000.ogg", 0.0, 0.5), L(f"{WOOD}/wood_falling_01.ogg", 0.0, 0.44, 0.01, -2.0),
                              L(f"{BFH}/bfh1_wood_breaking_03.ogg", 0.0, 0.45, 0.06, -6.0),
                              L(f"{NK}leaves.ogg", 6.0, 7.1, 0.03, -3.0, hp=300.0, fin=0.02, fout=0.5)], fout=0.4),
    # 자람: 잎이 쑥 펼쳐지며 바스락.
    "grow": dict(layers=[L(f"{NK}leaves.ogg", 12.0, 12.7, hp=300.0, fin=0.12, fout=0.3)]),
    # ---- 땅 · 몸 ----
    "dig": dict(layers=[L(f"{MUD}/mud_10.ogg", 0.0, 0.2), L(f"{KIMP}/impactSoft_medium_000.ogg", 0.0, 0.25, 0.03, -8.0)]),
    # 달리다 멈춤: 신발이 흙바닥을 쓸며 미끄러짐.
    "skid": dict(layers=[L(f"{RETAIL}/Bumpy Texture 1.wav", 0.05, 0.5, hp=150.0, lp=6000.0, fin=0.01, fout=0.18),
                         L(f"{MUD}/mud_10.ogg", 0.0, 0.2, 0.0, -10.0)]),
    "pickup": dict(layers=[L(f"{KRPG}/handleSmallLeather.ogg", 0.0, 0.45)]),
    # ---- 요리 ----
    # 칼이 도마를 탁.
    "cook_chop": dict(layers=[L(f"{KNIFE}/Big Knife - Tap 1.wav", 0.0, 0.25), L(f"{WOOD}/wood_hit_06.ogg", 0.0, 0.2, 0.0, -9.0)]),
    # 팬에서 지글: 장작 타닥임의 높은 쪽 + 쉬익.
    "cook_sizzle": dict(layers=[L(f"{NK}fire.ogg", 20.0, 21.4, hp=2500.0, fin=0.04, fout=0.4),
                                L(f"{RETAIL}/Smooth Texture 1.wav", 0.9, 2.3, 0.0, -8.0, hp=3500.0, fin=0.06, fout=0.4)]),
    # 냄비에서 보글보글.
    "cook_bubble": dict(layers=[L(f"{LOOPS}/water_boiling.ogg", 0.5, 1.7, fin=0.05, fout=0.3), L(f"{WATER}/bubble_03.ogg", 0.0, 0.5, 0.1, -9.0)]),
    # 접시를 내려놓는 쨍.
    "cook_plate": dict(layers=[L(f"{SFX100}/dishes_01.ogg", 0.0, 0.27, fout=0.1)]),
    # 주문 종 (호텔 데스크 종처럼 딩).
    "order_bell": dict(layers=[L(f"{SFX100}/bell_02.ogg", 0.0, 0.53)]),
    # ---- 돈 · 가게 ----
    "coin": dict(layers=[L(f"{RPG80}/item_coins_01.ogg", 0.0, 0.4)]),
    # 금전등록기 짤랑 + 딩.
    "cash_in": dict(layers=[L(f"{RPG80}/item_coins_03.ogg", 0.0, 0.48), L(f"{SFX100}/bell_02.ogg", 0.0, 0.5, 0.14, -9.0, pitch=5.0)]),
    # 가게 문에 달린 종 딸랑딸랑.
    "door_bell": dict(layers=[L(f"{SFX100}/bell_03.ogg", 0.0, 1.45)], fout=0.4),
    "camera_shutter": dict(layers=[L(f"{MECH}/Click Button 1.wav", 0.0, 0.3)]),
    # ---- 킥보드 · 탈것 ----
    "kick_latch": dict(layers=[L(f"{KRPG}/metalLatch.ogg", 0.03, 0.26)]),
    # 발로 땅 차기: 신발 바닥이 포장길을 탁 + 쓱.
    "kick_push": dict(layers=[L(f"{KIMP}/footstep_concrete_001.ogg", 0.0, 0.12),
                              L(f"{RETAIL}/Bumpy Texture 1.wav", 0.6, 0.85, 0.02, -7.0, hp=150.0, lp=5000.0, fin=0.02, fout=0.1)]),
    # 뒷발로 흙받이를 밟는 마찰음.
    "kick_brake": dict(layers=[L(f"{RETAIL}/Smooth Texture 1.wav", 1.0, 1.7, lp=3500.0, pitch=-3.0, fin=0.03, fout=0.25)]),
    # 바퀴가 길 위를 구르는 소리 (반복).
    "kick_roll_loop": dict(layers=[L(f"{LOOPS}/rolling.ogg", 0.0, 1.06, fin=0.0, fout=0.0)], loop=0.15),
    # ---- 감정표현 · 알림 (실제 악기 녹음: Kenney 피치카토 · 스틸팬) ----
    "emote_pop": dict(layers=[L(f"{RETAIL}/Cork Lid 1.wav", 1.08, 1.3, hp=150.0, fout=0.06)]),
    "emote_up": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI08.ogg")]),
    "emote_down": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI09.ogg")]),
    "emote_hey": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI04.ogg")]),
    "fanfare_small": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI10.ogg")]),
    "fanfare_big": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI02.ogg"), L(f"{KJ}/Steel jingles/jingles_STEEL02.ogg", gain=-5.0)]),
    "quest_done": dict(layers=[L(f"{KJ}/Steel jingles/jingles_STEEL10.ogg"), L(f"{KJ}/Pizzicato jingles/jingles_PIZZI10.ogg", gain=-7.0)]),
    "level_up": dict(layers=[L(f"{KJ}/Pizzicato jingles/jingles_PIZZI16.ogg"), L(f"{KJ}/Steel jingles/jingles_STEEL16.ogg", gain=-6.0)]),
    "event_start": dict(layers=[L(f"{KJ}/Steel jingles/jingles_STEEL15.ogg")]),
    # 반짝 (별 · 별똥별): 유리잔을 톡톡 두드린 소리를 높게 셋.
    "twinkle": dict(layers=[L(f"{KIMP}/impactGlass_light_000.ogg", 0.0, 1.2, 0.0, 0.0, pitch=7.0),
                            L(f"{KIMP}/impactGlass_light_002.ogg", 0.0, 1.2, 0.07, -3.0, pitch=12.0),
                            L(f"{KIMP}/impactGlass_light_003.ogg", 0.0, 1.2, 0.13, -6.0, pitch=16.0)], fout=0.25),
    # ---- 화면 단추: 실제 스위치 · 책 녹음 (Kenney UI Audio · RPG Audio) ----
    "ui_click": dict(layers=[L(f"{KUIA}/click3.ogg")]),
    "ui_confirm": dict(layers=[L(f"{KUIA}/switch7.ogg")]),
    "ui_cancel": dict(layers=[L(f"{KUIA}/switch1.ogg", pitch=-3.0)]),
    # 창 열기 · 닫기: 책장을 펼치고 덮는 소리.
    "ui_open": dict(layers=[L(f"{KRPG}/bookOpen.ogg", hp=150.0)]),
    "ui_close": dict(layers=[L(f"{KRPG}/bookClose.ogg", hp=120.0)]),
    # ---- 환경음 (반복) ----
    "birds_loop": dict(layers=[L(f"{NK}birds-tree.ogg", 20.0, 38.0, fin=0.0, fout=0.0)], loop=2.0, sr=LOOP_SR),
    "crickets_loop": dict(layers=[L(f"{NK}night.ogg", 5.0, 23.0, fin=0.0, fout=0.0)], loop=2.0, sr=LOOP_SR),
    "rain_loop": dict(layers=[L(f"{NK}rain.ogg", 10.0, 28.0, fin=0.0, fout=0.0)], loop=2.0, sr=LOOP_SR),
    "plane_loop": dict(layers=[L(f"{NK}air-plane.ogg", 10.0, 24.0, fin=0.0, fout=0.0)], loop=2.0, sr=LOOP_SR),
    # 천둥: 폭풍우 녹음에서 우르릉 두 대목.
    "thunder_1": dict(layers=[L(f"{NK}storm.ogg", 9.8, 15.3, fin=0.05)], fout=1.2),
    "thunder_2": dict(layers=[L(f"{NK}storm.ogg", 48.3, 54.0, fin=0.05)], fout=1.2),
    # 우르르 쾅쾅: 멀리서 굴러오다 연달아 터지는 긴 천둥 (가끔).
    "thunder_roll": dict(layers=[L(f"{NK}storm.ogg", 43.6, 57.8, fin=0.4)], fout=1.8),
    # 번쩍임 없이 멀리서 낮게 우르릉 (번개 사이사이).
    "thunder_far": dict(layers=[L(f"{NK}storm.ogg", 26.0, 36.5, lp=900.0, fin=0.8)], fout=2.0),
}


def a_weighting(sr: int):
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    z = [0.0, 0.0, 0.0, 0.0]
    p = [-2 * np.pi * f4] * 2 + [-2 * np.pi * f3, -2 * np.pi * f2] + [-2 * np.pi * f1] * 2
    k = (2 * np.pi * f4) ** 2 * 10 ** (1.9997 / 20)
    zd, pd, kd = bilinear_zpk(z, p, k, sr)
    return zpk2sos(zd, pd, kd)


def active_level(x: np.ndarray, sr: int) -> float:
    """A 가중 · 소리가 나는 구간(가장 큰 20ms 의 10% 이상)의 평균 크기 dB."""
    y = sosfilt(a_weighting(sr), x)
    hop = int(sr * 0.02)
    fr = np.array([np.sqrt(np.mean(y[i:i + hop] ** 2)) for i in range(0, max(len(y) - hop + 1, 1), hop)])
    act = fr[fr > fr.max() * 0.1]
    return 20 * np.log10(np.sqrt(np.mean(act ** 2)) + 1e-12)


class Sources:
    def __init__(self, cc0: Path, noisekun: Path) -> None:
        self.cc0 = cc0
        self.nk = noisekun / ".github/assets/sounds"
        self._cache: dict[tuple[str, int], np.ndarray] = {}

    def path(self, src: str) -> Path:
        if src.startswith("cc0:"):
            return self.cc0 / src[4:]
        if src.startswith("nk:"):
            return self.nk / src[3:]
        raise ValueError(src)

    def load(self, src: str, sr: int) -> np.ndarray:
        key = (src, sr)
        if key not in self._cache:
            p = self.path(src)
            if not p.exists():
                raise FileNotFoundError(p)
            raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", str(p), "-ac", "1", "-ar", str(sr), "-f", "f64le", "-"],
                                 capture_output=True, check=True).stdout
            self._cache[key] = np.frombuffer(raw, dtype=np.float64).copy()
        return self._cache[key]


def fade(x: np.ndarray, sr: int, fin: float, fout: float) -> np.ndarray:
    x = x.copy()
    n_in = min(int(fin * sr), len(x))
    n_out = min(int(fout * sr), len(x))
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in) ** 2
    if n_out > 0:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def render_layer(src: Sources, layer: dict, sr: int) -> np.ndarray:
    x = src.load(layer["src"], sr)
    a = int(layer["start"] * sr)
    b = len(x) if layer["end"] is None else min(int(layer["end"] * sr), len(x))
    x = x[a:b]
    if layer["hp"] > 0:
        x = sosfilt(butter(2, layer["hp"], "high", fs=sr, output="sos"), x)
    if layer["lp"] > 0:
        x = sosfilt(butter(2, layer["lp"], "low", fs=sr, output="sos"), x)
    if layer["pitch"] != 0.0:
        # 음높이를 올리면 짧아지고 내리면 길어진다 (테이프처럼).
        ratio = 2.0 ** (layer["pitch"] / 12.0)
        up, down = int(round(1000 / ratio)), 1000
        x = resample_poly(x, up, down)
    x = fade(x, sr, layer["fin"], layer["fout"])
    return x * 10 ** (layer["gain"] / 20)


def make_loop(x: np.ndarray, sr: int, overlap: float) -> np.ndarray:
    """끝의 overlap 초를 처음에 같은 힘으로 겹쳐, 끝 → 처음이 이음매 없이 이어지게."""
    n = int(overlap * sr)
    if n <= 0 or len(x) <= 2 * n:
        return x
    t = np.linspace(0.0, np.pi / 2, n)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    return np.concatenate([tail * np.cos(t) + head * np.sin(t), body])


def build(sid: str, recipe: dict, src: Sources) -> tuple[np.ndarray, int]:
    sr = recipe.get("sr", SR)
    parts = [(int(l["at"] * sr), render_layer(src, l, sr)) for l in recipe["layers"]]
    total = max(at + len(p) for at, p in parts)
    out = np.zeros(total)
    for at, p in parts:
        out[at:at + len(p)] += p
    if "length" in recipe:
        out = out[:int(recipe["length"] * sr)]
    if "loop" in recipe:
        out = make_loop(out, sr, recipe["loop"])
    elif "fout" in recipe:
        out = fade(out, sr, 0.0, recipe["fout"])
    # 앞쪽 무음 자르기 (반응이 늦게 들리지 않게) — 반복 소리는 그대로.
    if "loop" not in recipe:
        thr = np.abs(out).max() * 0.02
        first = int(np.argmax(np.abs(out) > thr))
        out = out[max(first - int(0.002 * sr), 0):]
        last = len(out) - int(np.argmax(np.abs(out[::-1]) > thr * 0.25))
        out = fade(out[:last], sr, 0.0, 0.01)
    # 크기: 합성음 때와 같은 A 가중 크기로. 실제 녹음은 순간 봉우리가 높아 그대로 키우면 넘치므로,
    # 봉우리만 살짝 눌러(최대 MAX_LIMIT_DB) 맞추고, 그래도 넘치면 -1 dBFS 에 맞춰 줄인다.
    for _ in range(3):
        out *= 10 ** ((TARGET[sid] - active_level(out, sr)) / 20)
        out = limit(out, sr)
    peak = np.abs(out).max()
    if peak > CEILING:
        out *= CEILING / peak
    return out, sr


CEILING = 10 ** (-1 / 20)
MAX_LIMIT_DB = 9.0


def limit(x: np.ndarray, sr: int) -> np.ndarray:
    """미리 보는(2ms) 봉우리 제한기: 넘치는 곳만 부드럽게 눌러 CEILING 아래로 (누르는 양은 MAX_LIMIT_DB 까지)."""
    need = np.minimum(1.0, CEILING / np.maximum(np.abs(x), 1e-12))
    need = np.maximum(need, 10 ** (-MAX_LIMIT_DB / 20))
    look = max(int(0.002 * sr), 1)
    # 앞으로 look 만큼 가장 작은 값 (미리 줄이기 시작)
    padded = np.concatenate([need, np.ones(look)])
    g = np.minimum.reduce([padded[i:i + len(need)] for i in range(look + 1)])
    # 줄일 땐 빠르게(lookahead 동안), 되돌릴 땐 천천히 (60ms)
    rel = np.exp(-1.0 / (0.06 * sr))
    att = np.exp(-1.0 / (0.0005 * sr))
    env = np.empty_like(g)
    e = 1.0
    for i, v in enumerate(g):
        e = v + (e - v) * (att if v < e else rel)
        env[i] = min(e, v) if v < e else e
    return x * env


def write_wav(path: Path, x: np.ndarray, sr: int) -> None:
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cc0", required=True, type=Path)
    ap.add_argument("--noisekun", required=True, type=Path)
    ap.add_argument("--only", default="")
    ap.add_argument("--out", type=Path, default=SFX_DIR)
    args = ap.parse_args()
    src = Sources(args.cc0, args.noisekun)
    only = set(filter(None, args.only.split(",")))
    args.out.mkdir(parents=True, exist_ok=True)
    for sid, recipe in RECIPES.items():
        if only and sid not in only:
            continue
        x, sr = build(sid, recipe, src)
        write_wav(args.out / f"{sid}.wav", x, sr)
        print(f"{sid:16s} {len(x) / sr:5.2f}s  {sr}Hz  level {active_level(x, sr):6.1f} dB(A)  peak {20 * np.log10(np.abs(x).max() + 1e-12):5.1f} dB")


if __name__ == "__main__":
    main()
