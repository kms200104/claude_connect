#!/usr/bin/env python3
"""
고품질 실제 녹음(Foley) 오픈소스 사운드(CC0 / CC-BY)를 솔바람 마을 형식에 맞춰 임포트 및 처리하는 스크립트.

출처:
- Cozy Farm SFX (Bramble & Byte, CC-BY 4.0, https://opengameart.org/content/cozy-farm-sfx-50-farming-game-sound-effects-tools-harvest-shop-ui-jingles)
  : 도끼질(chop), 나무 쓰러짐(tree_creak, tree_land), 아이템 줍기(pickup), 코인(coin), 상점 벨(door_bell), 퀘스트 완료(quest_done), 레벨업(level_up)
- Rain (loopable) (Ylmir, CC0, https://opengameart.org/content/rain-loopable)
  : 실제 창가/지면 빗소리 심리스 루프 (rain_loop)
- Rain and Thunder Loop (DoKashiteru, CC-BY 3.0, https://opengameart.org/content/rain-and-thunder-loop)
  : 실제 천둥소리 (thunder_1, thunder_2)
"""

import os
from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets/audio/sfx"
DL_DIR = ROOT.parent / "audio_dl"
COZY_DIR = DL_DIR / "cozy_farm/cozy-farm-sfx/sfx"
RAIN_DIR = DL_DIR / "rain_ogg"
THUNDER_PATH = DL_DIR / "rain_thunder_loop.wav"


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    """오디오를 특정 피크 dBFS 수준으로 정규화."""
    max_val = np.max(np.abs(x))
    if max_val < 1e-9:
        return x
    target_lin = 10.0 ** (peak_db / 20.0)
    return x * (target_lin / max_val)


def make_seamless_loop(x: np.ndarray, crossfade_sec: float = 1.0, sr: int = 44100) -> np.ndarray:
    """
    Equal-Power Crossfade 기법을 적용하여 이음매(클릭)가 전혀 없는 완벽한 루프 생성.
    """
    n_fade = int(crossfade_sec * sr)
    if len(x) <= n_fade * 2:
        return x

    head = x[:n_fade]
    body = x[n_fade:-n_fade]
    tail = x[-n_fade:]

    # Equal power fade curve (cos / sin)
    t = np.linspace(0.0, np.pi / 2.0, n_fade)
    fade_in = np.sin(t)
    fade_out = np.cos(t)

    if x.ndim == 2:
        fade_in = fade_in[:, np.newaxis]
        fade_out = fade_out[:, np.newaxis]

    blended = tail * fade_out + head * fade_in
    return np.concatenate([blended, body], axis=0)


def fade_edges(x: np.ndarray, fade_in_sec: float = 0.005, fade_out_sec: float = 0.03, sr: int = 44100) -> np.ndarray:
    """시작과 끝의 틱 잡음을 제거하기 위한 미세 페이드."""
    out = x.copy()
    n_in = int(fade_in_sec * sr)
    n_out = int(fade_out_sec * sr)
    if n_in > 0 and len(out) > n_in:
        t_in = np.linspace(0.0, 1.0, n_in)
        if out.ndim == 2:
            t_in = t_in[:, np.newaxis]
        out[:n_in] *= t_in
    if n_out > 0 and len(out) > n_out:
        t_out = np.linspace(1.0, 0.0, n_out)
        if out.ndim == 2:
            t_out = t_out[:, np.newaxis]
        out[-n_out:] *= t_out
    return out


def main():
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    print("=== 고품질 실제 Foley 오디오 임포트 시작 ===")

    # 1. 도끼질 (chop)
    print("1. 도끼질 (chop.wav) 처리 중...")
    axe_data, sr = sf.read(str(COZY_DIR / "axe-chop.wav"))
    if axe_data.ndim > 1:
        axe_data = np.mean(axe_data, axis=1)
    axe_data = fade_edges(normalize(axe_data, -1.0), fade_in_sec=0.001, fade_out_sec=0.02, sr=sr)
    sf.write(str(SFX_DIR / "chop.wav"), axe_data.astype(np.float32), sr, subtype="PCM_16")

    # 2. 나무 쓰러짐 분할 (tree_creak & tree_land)
    print("2. 나무 넘어가는 소리 (tree_creak.wav / tree_land.wav) 처리 중...")
    tree_data, sr = sf.read(str(COZY_DIR / "tree-fall.wav"))
    if tree_data.ndim > 1:
        tree_data = np.mean(tree_data, axis=1)
    
    # 0.0s ~ 0.42s : 나무가 우지끈 찢어지는 크랙
    n_split = int(0.42 * sr)
    creak_part = tree_data[:n_split].copy()
    creak_part = fade_edges(normalize(creak_part, -2.0), fade_in_sec=0.002, fade_out_sec=0.06, sr=sr)
    sf.write(str(SFX_DIR / "tree_creak.wav"), creak_part.astype(np.float32), sr, subtype="PCM_16")

    # 0.38s ~ 끝 : 지면에 쿵 떨어지며 잎사귀가 퍼지는 임팩트
    n_start_land = int(0.38 * sr)
    land_part = tree_data[n_start_land:].copy()
    land_part = fade_edges(normalize(land_part, -0.5), fade_in_sec=0.005, fade_out_sec=0.1, sr=sr)
    sf.write(str(SFX_DIR / "tree_land.wav"), land_part.astype(np.float32), sr, subtype="PCM_16")

    # 3. 빗소리 루프 (rain_loop)
    print("3. 리얼 빗소리 심리스 루프 (rain_loop.wav) 처리 중...")
    rain_data, sr = sf.read(str(RAIN_DIR / "1.ogg"))
    # 모바일 최적화 및 3D 입체 음향 공간감을 위해 모노로 합치거나 스테레오 유지
    # 모바일 앰비언스는 22~44.1kHz 모노 또는 스테레오. AudioStreamWAV 모노가 메모리와 호환성에 안전
    if rain_data.ndim > 1:
        rain_mono = np.mean(rain_data, axis=1)
    else:
        rain_mono = rain_data
    # 8초 구간 추출 후 심리스 루프화
    sub_len = int(9.0 * sr)
    start_pos = int(2.0 * sr)
    rain_slice = rain_mono[start_pos : start_pos + sub_len]
    rain_loop = make_seamless_loop(rain_slice, crossfade_sec=1.2, sr=sr)
    rain_loop = normalize(rain_loop, -3.0)  # 루프 환경음이므로 귀가 피로하지 않게 -3dB
    sf.write(str(SFX_DIR / "rain_loop.wav"), rain_loop.astype(np.float32), sr, subtype="PCM_16")

    # 4. 천둥 소리 (thunder_1 & thunder_2)
    print("4. 리얼 천둥소리 (thunder_1.wav / thunder_2.wav) 처리 중...")
    th_data, sr = sf.read(str(THUNDER_PATH))
    if th_data.ndim > 1:
        th_mono = np.mean(th_data, axis=1)
    else:
        th_mono = th_data
    
    # 천둥 1: 1.6s ~ 5.4s (3.8초)
    th1 = th_mono[int(1.6 * sr) : int(5.4 * sr)].copy()
    th1 = fade_edges(normalize(th1, -0.5), fade_in_sec=0.01, fade_out_sec=0.25, sr=sr)
    sf.write(str(SFX_DIR / "thunder_1.wav"), th1.astype(np.float32), sr, subtype="PCM_16")

    # 천둥 2: 12.6s ~ 17.2s (4.6초 묵직한 잔향)
    th2 = th_mono[int(12.6 * sr) : int(17.2 * sr)].copy()
    th2 = fade_edges(normalize(th2, -0.5), fade_in_sec=0.01, fade_out_sec=0.3, sr=sr)
    sf.write(str(SFX_DIR / "thunder_2.wav"), th2.astype(np.float32), sr, subtype="PCM_16")

    # 5. 기타 편의성/품질 업그레이드 효과음
    print("5. 아이템, 상점, 낚시 효과음 업데이트 중...")
    
    # 아이템 줍기 (pickup)
    pick_data, sr = sf.read(str(COZY_DIR / "pickup-item.wav"))
    pick_data = fade_edges(normalize(np.mean(pick_data, axis=1) if pick_data.ndim > 1 else pick_data, -2.0), sr=sr)
    sf.write(str(SFX_DIR / "pickup.wav"), pick_data.astype(np.float32), sr, subtype="PCM_16")

    # 상점 코인 짤랑 (coin)
    coin_data, sr = sf.read(str(COZY_DIR / "sell-coins.wav"))
    coin_data = fade_edges(normalize(np.mean(coin_data, axis=1) if coin_data.ndim > 1 else coin_data, -2.0), sr=sr)
    sf.write(str(SFX_DIR / "coin.wav"), coin_data.astype(np.float32), sr, subtype="PCM_16")

    # 상점 문 종 (door_bell)
    bell_data, sr = sf.read(str(COZY_DIR / "shop-bell.wav"))
    bell_data = fade_edges(normalize(np.mean(bell_data, axis=1) if bell_data.ndim > 1 else bell_data, -1.5), sr=sr)
    sf.write(str(SFX_DIR / "door_bell.wav"), bell_data.astype(np.float32), sr, subtype="PCM_16")

    # 퀘스트 완료 (quest_done)
    quest_data, sr = sf.read(str(COZY_DIR / "jingle-quest-complete.wav"))
    quest_data = fade_edges(normalize(np.mean(quest_data, axis=1) if quest_data.ndim > 1 else quest_data, -1.0), sr=sr)
    sf.write(str(SFX_DIR / "quest_done.wav"), quest_data.astype(np.float32), sr, subtype="PCM_16")

    # 상점 레벨업 팡파레 (level_up)
    lvl_data, sr = sf.read(str(COZY_DIR / "jingle-level-up.wav"))
    lvl_data = fade_edges(normalize(np.mean(lvl_data, axis=1) if lvl_data.ndim > 1 else lvl_data, -1.0), sr=sr)
    sf.write(str(SFX_DIR / "level_up.wav"), lvl_data.astype(np.float32), sr, subtype="PCM_16")

    print("=== 모든 사운드 임포트 및 고음질 변환 완료! ===")


if __name__ == "__main__":
    main()
