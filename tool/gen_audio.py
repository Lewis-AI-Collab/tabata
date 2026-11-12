#!/usr/bin/env python3
"""Generate the timer clips in assets/audio.

Tick and beep are original waveforms (public domain, CC0). The spoken clips
are synthesized with SVOX Pico (`pico2wave`, Apache-2.0) and then trimmed.
See assets/audio/LICENSE.txt.
"""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SR = 44100
SPEECH_LIMIT = 0.85


def write_pcm(path: Path, samples: list[int], sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))


def synth_tone(path: Path, freq: float, ms: float, amp: float, partial: float = 0) -> None:
    count = int(SR * ms / 1000)
    attack = max(1, int(SR * 0.002))
    samples: list[int] = []
    for i in range(count):
        t = i / SR
        env = 1.0 if i >= attack else i / attack
        env *= math.exp(-3.2 * i / count)
        wave_value = math.sin(2 * math.pi * freq * t)
        if partial:
            wave_value += partial * math.sin(2 * math.pi * freq * 2 * t)
        sample = int(32767 * amp * wave_value * env)
        samples.append(max(-32767, min(32767, sample)))
    write_pcm(path, samples, SR)


def read_pcm(path: Path) -> tuple[list[int], int]:
    with wave.open(str(path), "r") as handle:
        rate = handle.getframerate()
        count = handle.getnframes()
        raw = handle.readframes(count)
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise SystemExit(f"{path} is not mono 16-bit")
    samples = list(struct.unpack("<" + "h" * (len(raw) // 2), raw))
    return samples, rate


def trim_speech(samples: list[int], rate: int) -> list[int]:
    threshold = 500
    audible = [i for i, sample in enumerate(samples) if abs(sample) > threshold]
    if not audible:
        raise SystemExit("synthesized speech was silent")
    pad_front = int(rate * 0.02)
    pad_back = int(rate * 0.04)
    start = max(0, audible[0] - pad_front)
    end = min(len(samples), audible[-1] + pad_back)
    clipped = samples[start:end]
    fade = int(rate * 0.008)
    for i in range(min(fade, len(clipped))):
        gain = i / fade
        clipped[i] = int(clipped[i] * gain)
        clipped[-1 - i] = int(clipped[-1 - i] * gain)
    duration = len(clipped) / rate
    if duration > SPEECH_LIMIT:
        ratio = duration / SPEECH_LIMIT
        sped: list[int] = []
        pos = 0.0
        while int(pos) < len(clipped) - 1:
            sped.append(clipped[int(pos)])
            pos += ratio
        clipped = sped
    if len(clipped) / rate >= 1:
        raise SystemExit("speech clip still covers the next second")
    return clipped


def synthesize_word(path: Path, phrase: str) -> None:
    pico = shutil.which("pico2wave")
    if pico is None:
        raise SystemExit("pico2wave is required to build the spoken clips")
    raw = path.with_suffix(".raw.wav")
    subprocess.run([pico, "-w", str(raw), phrase], check=True)
    samples, rate = read_pcm(raw)
    raw.unlink()
    write_pcm(path, trim_speech(samples, rate), rate)


def main() -> None:
    synth_tone(OUT / "tick.wav", freq=660, ms=28, amp=0.14)
    synth_tone(OUT / "beep.wav", freq=1480, ms=110, amp=0.55, partial=0.35)
    words = {
        "workout.wav": "workout",
        "rest.wav": "rest",
    }
    for name, phrase in words.items():
        synthesize_word(OUT / name, phrase)
        samples, rate = read_pcm(OUT / name)
        print(f"{name}: {len(samples) / rate:.3f}s peak {max(abs(s) for s in samples)}")


if __name__ == "__main__":
    main()
