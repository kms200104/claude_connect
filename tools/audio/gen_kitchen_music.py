#!/usr/bin/env python3
"""
식당 음악 두 곡을 CC0 실제 악기 · 드럼 녹음으로 짓는다 (v0.18).

  restaurant_theme.ogg  식당 문을 열었을 때 (120 BPM, 다장조, 16마디 반복) — 신나는 개업 노래
  cooking_theme.ogg     요리할 때 (한 박자 = 536 ms ≈ 112 BPM, 바장조, 16마디 반복) — 리듬 요리의 박자.
                        모든 박자에 '통' 하는 킥, 2 · 4 박에 손뼉, 박자 사이(&)에 피치카토 화음.
                        요리 동작의 누를 때(recipes.json hits)는 이 노래의 박자와 같은 격자다 (곡 0초 = 첫 박자).

악기 (모두 CC0 — https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds):
  첼로 피치카토 (bb - Novice Cello, Ben Burnes) — 베이스
  스틸팬 · 피치카토 한 음 (Kenney Music Jingles 의 마지막 음) — 선율 · 화음
  킥 · 스네어 · 손뼉 · 하이햇 · 트라이앵글 · 나무 딱 (BB 2HTC Samples Vol 4, Ben Burnes)

사용: python3 tools/audio/gen_kitchen_music.py --cc0 /tmp/cc0   (numpy, scipy, ffmpeg)
"""

import argparse
import subprocess
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/music"
SR = 44100

COOK_BEAT = 0.536
OPEN_BEAT = 0.5

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name: str) -> int:
    n = name[:-1]
    return 12 * (int(name[-1]) + 1) + NOTE_INDEX[n]


def hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


class Kit:
    def __init__(self, cc0: Path) -> None:
        self.cc0 = cc0
        self._cache: dict[str, np.ndarray] = {}

    def load(self, rel: str) -> np.ndarray:
        """스테레오 float (n, 2)."""
        if rel not in self._cache:
            raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", str(self.cc0 / rel), "-ac", "2", "-ar", str(SR), "-f", "f64le", "-"],
                                 capture_output=True, check=True).stdout
            x = np.frombuffer(raw, dtype=np.float64).reshape(-1, 2).copy()
            # 앞 무음 자르기.
            env = np.abs(x).max(axis=1)
            first = int(np.argmax(env > env.max() * 0.02))
            self._cache[rel] = x[max(first - 16, 0):]
        return self._cache[rel]

    def last_note(self, rel: str) -> np.ndarray:
        """징글의 마지막 음 (그 음의 시작부터 끝까지, 앞의 음은 뺀다)."""
        x = self.load(rel)
        mono = np.abs(x).mean(axis=1)
        hop = 256
        frames = np.array([mono[i:i + hop].max() for i in range(0, len(mono) - hop, hop)])
        rise = np.diff(frames)
        onsets = [i for i in range(1, len(rise)) if rise[i] > frames.max() * 0.15 and frames[i + 1] > frames.max() * 0.3]
        start = (onsets[-1] if onsets else 0) * hop
        note = x[max(start - 64, 0):].copy()
        note[:64] *= np.linspace(0, 1, 64)[:, None]
        return note


def pitched(sample: np.ndarray, ratio: float, length: float | None = None, fade: float = 0.04) -> np.ndarray:
    """음높이 바꾸기 (테이프처럼 빠르게/느리게) + 길이를 자르고 끝을 부드럽게."""
    n_out = int(len(sample) / ratio)
    src = np.arange(n_out) * ratio
    out = np.stack([np.interp(src, np.arange(len(sample)), sample[:, c]) for c in range(2)], axis=1)
    if length is not None:
        n = min(len(out), int(length * SR))
        out = out[:n].copy()
        f = min(int(fade * SR), n)
        out[n - f:] *= np.linspace(1, 0, f)[:, None] ** 2
    return out


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """p: -1 왼쪽 ~ 1 오른쪽 (같은 힘)."""
    a = (p + 1) * np.pi / 4
    return x * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2)


class Song:
    def __init__(self, beat: float, bars: int, tail: float = 3.0) -> None:
        self.beat = beat
        self.bars = bars
        self.length = bars * 4 * beat
        self.buses: dict[str, np.ndarray] = {}
        self.n = int((self.length + tail) * SR)

    def bus(self, name: str) -> np.ndarray:
        if name not in self.buses:
            self.buses[name] = np.zeros((self.n, 2))
        return self.buses[name]

    def put(self, bus: str, at_beats: float, x: np.ndarray, gain_db: float = 0.0, p: float = 0.0, swing: float = 0.0) -> None:
        t = at_beats * self.beat
        # 엇박(반 박자 뒤 &)을 살짝 늦춰 통통 튀게.
        if swing and abs((at_beats % 1.0) - 0.5) < 1e-6:
            t += swing * self.beat
        i = int(round(t * SR))
        b = self.bus(bus)
        y = pan(x, p) * 10 ** (gain_db / 20)
        end = min(len(b), i + len(y))
        b[i:end] += y[:end - i]

    def mix(self, levels: dict[str, float], reverb_send: dict[str, float]) -> np.ndarray:
        dry = np.zeros((self.n, 2))
        wet_in = np.zeros((self.n, 2))
        for name, x in self.buses.items():
            g = 10 ** (levels.get(name, 0.0) / 20)
            dry += x * g
            wet_in += x * g * reverb_send.get(name, 0.0)
        wet = reverb(wet_in)
        out = dry + wet
        # 반복: 끝에서 넘친 꼬리(울림)를 처음에 더해 이음매 없이.
        loop_n = int(round(self.length * SR))
        body = out[:loop_n].copy()
        tail = out[loop_n:]
        body[:len(tail)] += tail[:loop_n]
        return master(body)


def reverb(x: np.ndarray, seconds: float = 1.3) -> np.ndarray:
    """작은 방 울림: 지수로 사라지는 잡음 응답 (좌우 다르게) 을 FFT 로 곱한다."""
    rng = np.random.default_rng(7)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(x)
    for c in range(2):
        ir = rng.standard_normal(n) * np.exp(-t * 5.5)
        ir = sosfilt(butter(2, [300, 6500], "band", fs=SR, output="sos"), ir)
        ir[:int(0.012 * SR)] = 0.0
        ir /= np.sqrt((ir ** 2).sum())
        size = 1 << int(np.ceil(np.log2(len(x) + n)))
        y = np.fft.irfft(np.fft.rfft(x[:, c], size) * np.fft.rfft(ir, size), size)[:len(x)]
        out[:, c] = y
    return out * 0.35


def master(x: np.ndarray) -> np.ndarray:
    # 낮은 웅웅거림 정리 + 부드러운 봉우리 누름.
    x = sosfilt(butter(2, 32, "high", fs=SR, output="sos"), x, axis=0)
    peak = np.abs(x).max()
    x = x / peak * 10 ** (-2.5 / 20)
    # 부드럽게 눌러 -1.5 dBFS 를 넘지 않게 (Vorbis 로 줄여도 넘치지 않도록 여유).
    ceiling = 10 ** (-1.5 / 20)
    return np.tanh(x / ceiling) * ceiling


def write_ogg(path: Path, x: np.ndarray) -> None:
    pcm = np.clip(x, -1, 1).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(path)],
                   input=pcm, check=True)


# ---- 악기 ----

class Band:
    def __init__(self, kit: Kit) -> None:
        self.kit = kit
        jingles = "kenney_musicjingles/Audio"
        self.steel = [(midi("D#4"), kit.last_note(f"{jingles}/Steel jingles/jingles_STEEL00.ogg")),
                      (midi("A#4"), kit.last_note(f"{jingles}/Steel jingles/jingles_STEEL02.ogg"))]
        self.pizz = [(midi("D#4"), kit.last_note(f"{jingles}/Pizzicato jingles/jingles_PIZZI00.ogg")),
                     (midi("A#4"), kit.last_note(f"{jingles}/Pizzicato jingles/jingles_PIZZI02.ogg"))]
        cello = "bb - Novice Cello (Nov 2021)"
        self.cello = [(midi(n), kit.load(f"{cello}/{n} - Pluck 1.wav")) for n in ("C2", "G2", "D3", "A3")]
        drums = "BB_2HTC Samples Vol 4/Drums"

        def drum(name: str) -> np.ndarray:
            f = next(p for p in (kit.cc0 / drums).iterdir() if name in p.name)
            return kit.load(f"{drums}/{f.name}")
        # 쿵이 시작하자마자 오는 킥 (Chunky Kick 은 쿵이 170ms 늦어 박자가 밀린다).
        self.kick = drum("I Should Be Sleeping - Good Kick")
        self.kick2 = drum("Moist Alleyway - Damp Kick")
        self.snare = drum("Cafe Sunset - Snare")
        self.clap = drum("Dancing in the Shallows - Clapper")
        self.hat = drum("Triple-C THICCC - Lil Hat")
        self.hat2 = drum("Tiny House Hands - Hat")
        self.triangle = drum("Bismuth - Triangle")
        self.clack = drum("Shapes in the Snow - Small Clack")
        self.click = drum("Cafe Sunset - Click")
        self.tink = drum("Depleted - Lil Tink")

    @staticmethod
    def _nearest(bank: list[tuple[int, np.ndarray]], m: int) -> tuple[int, np.ndarray]:
        return min(bank, key=lambda b: abs(b[0] - m))

    def note(self, bank: str, name: str, length: float) -> np.ndarray:
        m = midi(name)
        root, s = self._nearest(getattr(self, bank), m)
        return pitched(s, hz(m) / hz(root), length)


def chord_notes(root: str, quality: str, octave: int = 4) -> list[str]:
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    r = NOTE_INDEX[root]
    steps = [0, 4, 7] if quality == "" else [0, 3, 7]
    base = 12 * (octave + 1) + r
    # 가운데 음역(G3~F4 근처)으로 모은다.
    out = []
    for s in steps:
        m = base + s
        while m > midi("A4"):
            m -= 12
        while m < midi("F3"):
            m += 12
        out.append(f"{names[m % 12]}{m // 12 - 1}")
    return out


def parse_chord(c: str) -> tuple[str, str]:
    if c.endswith("m"):
        return c[:-1], "m"
    return c, ""


# ---- 곡 ----

COOK_CHORDS = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "C", "Bb", "C", "Am", "Dm", "Gm", "C", "F", "C"]
COOK_MELODY = [
    [(0, "C5"), (0.5, "A4"), (1, "C5"), (1.5, "F5"), (2.5, "E5"), (3, "F5")],
    [(0, "G5"), (1, "E5"), (1.5, "C5"), (2, "D5"), (3, "E5"), (3.5, "G5")],
    [(0, "F5"), (0.5, "E5"), (1, "D5"), (2, "A4"), (2.5, "D5"), (3, "F5")],
    [(0, "F5"), (1, "D5"), (1.5, "Bb4"), (2, "C5"), (2.5, "D5"), (3, "C5")],
    [(0, "A4"), (0.5, "C5"), (1, "F5"), (1.5, "A5"), (2.5, "G5"), (3, "F5")],
    [(0, "E5"), (0.5, "G5"), (1, "C6"), (2, "G5"), (2.5, "E5"), (3, "C5")],
    [(0, "D5"), (0.5, "F5"), (1, "Bb5"), (2, "C6"), (2.5, "Bb5"), (3, "G5")],
    [(0, "A5"), (1, "F5"), (1.5, "C5"), (2, "F5")],
    [(0, "D5"), (0.5, "F5"), (1, "Bb5"), (1.5, "A5"), (2, "F5"), (3, "D5")],
    [(0, "E5"), (0.5, "G5"), (1, "C6"), (1.5, "Bb5"), (2, "G5"), (3, "E5")],
    [(0, "C5"), (0.5, "E5"), (1, "A5"), (2, "G5"), (2.5, "E5"), (3, "C5")],
    [(0, "D5"), (0.5, "F5"), (1, "A5"), (1.5, "F5"), (2, "D5"), (3, "A4")],
    [(0, "Bb4"), (0.5, "D5"), (1, "G5"), (1.5, "F5"), (2, "D5"), (2.5, "Bb4"), (3, "D5")],
    [(0, "E5"), (0.5, "G5"), (1, "E5"), (1.5, "C5"), (2, "G4"), (3, "Bb4"), (3.5, "C5")],
    [(0, "A4"), (0.5, "C5"), (1, "F5"), (2, "A5"), (2.5, "G5"), (3, "A5")],
    [(0, "G5"), (1, "E5"), (2, "C5"), (3, "G4"), (3.5, "A4")],
]

OPEN_CHORDS = ["C", "Am", "F", "G", "C", "Am", "F", "G", "F", "G", "Em", "Am", "Dm", "G", "C", "G"]
OPEN_MELODY = [
    [(0, "E5"), (0.5, "G5"), (1, "C6"), (2, "G5"), (2.5, "E5"), (3, "G5")],
    [(0, "A5"), (1, "E5"), (1.5, "C5"), (2, "E5"), (3, "A5")],
    [(0, "F5"), (0.5, "A5"), (1, "C6"), (2, "A5"), (3, "F5"), (3.5, "G5")],
    [(0, "G5"), (0.5, "D5"), (1, "B4"), (1.5, "D5"), (2, "G5"), (3, "B5")],
    [(0, "C6"), (1, "G5"), (1.5, "E5"), (2, "G5"), (2.5, "C6"), (3, "E6")],
    [(0, "D6"), (0.5, "C6"), (1, "A5"), (2, "E5"), (3, "A5")],
    [(0, "F5"), (1, "A5"), (1.5, "C6"), (2, "A5"), (2.5, "F5"), (3, "A5")],
    [(0, "G5"), (1, "B5"), (2, "D6"), (3, "B5")],
    [(0, "A5"), (0.5, "C6"), (1, "A5"), (1.5, "F5"), (2, "C5"), (3, "F5")],
    [(0, "G5"), (0.5, "B5"), (1, "D6"), (2, "B5"), (3, "G5")],
    [(0, "E5"), (0.5, "G5"), (1, "B5"), (2, "G5"), (2.5, "E5"), (3, "B4")],
    [(0, "C5"), (0.5, "E5"), (1, "A5"), (2, "C6"), (3, "B5")],
    [(0, "A5"), (0.5, "F5"), (1, "D5"), (2, "F5"), (3, "A5")],
    [(0, "B5"), (0.5, "D6"), (1, "G5"), (2, "F5"), (3, "D5")],
    [(0, "E5"), (0.5, "G5"), (1, "C6"), (1.5, "E6"), (2, "D6"), (3, "C6")],
    [(0, "B5"), (1, "G5"), (2, "D5"), (3, "F5"), (3.5, "D5")],
]


def bass_note(root: str, octave: int = 2) -> str:
    m = 12 * (octave + 1) + NOTE_INDEX[root]
    while m < midi("C2"):
        m += 12
    while m > midi("B2"):
        m -= 12
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return f"{names[m % 12]}{m // 12 - 1}"


def fifth(name: str) -> str:
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    m = midi(name) + 7
    return f"{names[m % 12]}{m // 12 - 1}"


def cooking(band: Band) -> np.ndarray:
    # 엇박을 늦추지 않는다 (swing 없음) — 반 박자 누름(hits 0.5)이 노래의 &와 딱 맞게.
    s = Song(COOK_BEAT, 16)
    rng = np.random.default_rng(3)
    for bar in range(16):
        b0 = bar * 4
        root, q = parse_chord(COOK_CHORDS[bar])
        # 드럼: 박자마다 통(킥) — 요리 누름의 박자. 2 · 4 에 손뼉 + 스네어.
        for k in range(4):
            s.put("kick", b0 + k, band.kick, 0.0)
            if k in (1, 3):
                s.put("clap", b0 + k, band.clap, -1.0, 0.1)
                s.put("clap", b0 + k, band.snare, -7.0, -0.1)
            s.put("hat", b0 + k + 0.5, band.hat, -2.0 + rng.uniform(-1.5, 0), 0.35)
            s.put("hat", b0 + k + 0.25, band.hat2, -14.0 + rng.uniform(-2, 0), -0.35)
            s.put("hat", b0 + k + 0.75, band.hat2, -13.0 + rng.uniform(-2, 0), -0.35)
        if bar % 2 == 1:
            s.put("perc", b0 + 3.5, band.clack, -6.0, 0.5)
            s.put("perc", b0 + 3.75, band.clack, -9.0, 0.5)
        if bar % 4 == 0:
            s.put("perc", b0, band.triangle, -8.0, -0.5)
        # 베이스 (첼로 피치카토): 1 근음 · 2& 옥타브 · 3 5도 · 4& 근음, 통통 튄다.
        bn = bass_note(root)
        for pos, name, ln in [(0, bn, 0.5), (1.5, bn, 0.3), (2, fifth(bn), 0.5), (3.5, bn, 0.3)]:
            s.put("bass", b0 + pos, band.note("cello", name, ln * COOK_BEAT * 2), 0.0, 0.0)
        # 화음 (피치카토): 박자 사이(&) 마다 짧게 톡.
        for k in range(4):
            for i, n in enumerate(chord_notes(root, q)):
                s.put("chords", b0 + k + 0.5, band.note("pizz", n, 0.22), -4.0, (i - 1) * 0.4)
        # 선율 (스틸팬).
        for pos, name in COOK_MELODY[bar]:
            s.put("lead", b0 + pos, band.note("steel", name, 0.55), 0.0, 0.15)
            s.put("lead", b0 + pos + 0.75, band.note("steel", name, 0.3), -14.0, -0.4)
    return s.mix({"kick": -1.0, "clap": -4.0, "hat": -10.0, "perc": -6.0, "bass": 1.0, "chords": -6.0, "lead": -2.0},
                 {"clap": 0.25, "chords": 0.35, "lead": 0.45, "perc": 0.3})


def opening(band: Band) -> np.ndarray:
    s = Song(OPEN_BEAT, 16)
    rng = np.random.default_rng(5)
    for bar in range(16):
        b0 = bar * 4
        root, q = parse_chord(OPEN_CHORDS[bar])
        for k in range(4):
            if k in (0, 2):
                s.put("kick", b0 + k, band.kick, 0.0)
            if k in (1, 3):
                s.put("clap", b0 + k, band.clap, 0.0, 0.15)
                s.put("clap", b0 + k, band.snare, -6.0, -0.15)
            for sub in (0.0, 0.5):
                s.put("hat", b0 + k + sub, band.hat, (-3.0 if sub else -7.0) + rng.uniform(-1.5, 0), 0.3)
        if bar % 2 == 1:
            s.put("kick", b0 + 2.5, band.kick2, -4.0)
        if bar % 4 == 0:
            s.put("perc", b0, band.triangle, -4.0, -0.4)
        if bar % 4 == 3:
            for i, pos in enumerate([3.0, 3.25, 3.5, 3.75]):
                s.put("perc", b0 + pos, band.clack, -6.0 + i, 0.4 - i * 0.2)
        bn = bass_note(root)
        for pos, name, ln in [(0, bn, 0.45), (0.75, bn, 0.2), (1.5, fifth(bn), 0.3), (2, bn, 0.45), (3, fifth(bn), 0.3), (3.5, bn, 0.3)]:
            s.put("bass", b0 + pos, band.note("cello", name, ln * OPEN_BEAT * 2), 0.0)
        # 피치카토 펼침화음 (16분음표로 오르내림).
        notes = chord_notes(root, q) + [chord_notes(root, q)[0][:-1] + str(int(chord_notes(root, q)[0][-1]) + 1)]
        pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        for i in range(16):
            n = notes[pattern[i % 8]]
            s.put("chords", b0 + i * 0.25, band.note("pizz", n, 0.18), -6.0 - (0 if i % 4 == 0 else 3), (pattern[i % 8] - 1.5) * 0.3)
        for pos, name in OPEN_MELODY[bar]:
            s.put("lead", b0 + pos, band.note("steel", name, 0.5), 0.0, 0.1)
    return s.mix({"kick": -2.0, "clap": -5.0, "hat": -11.0, "perc": -5.0, "bass": 0.0, "chords": -7.0, "lead": -1.0},
                 {"clap": 0.3, "chords": 0.4, "lead": 0.5, "perc": 0.35})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cc0", required=True, type=Path)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()
    band = Band(Kit(args.cc0))
    args.out.mkdir(parents=True, exist_ok=True)
    for name, make in [("cooking_theme", cooking), ("restaurant_theme", opening)]:
        x = make(band)
        write_ogg(args.out / f"{name}.ogg", x)
        print(f"{name}: {len(x) / SR:.2f}s")


if __name__ == "__main__":
    main()
