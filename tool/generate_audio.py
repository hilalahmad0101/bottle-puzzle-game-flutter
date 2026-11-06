#!/usr/bin/env python3
"""Generates every sound in assets/audio/ from scratch.

All audio in Prism Pour is ORIGINAL: it is synthesised by this script from
sine waves, a seeded noise source and simple envelopes. No recording, sample
library or third-party music is used, so there is nothing to license. Run
`python3 tool/generate_audio.py` to regenerate the files byte-for-byte (the
noise is seeded). Only the Python standard library is needed.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')


def edges(samples, fade_in=0.002, fade_out=0.03):
    """Raised-cosine fades so a sound never starts or ends with a click."""
    out = list(samples)
    for i in range(min(len(out), n(fade_in))):
        out[i] *= 0.5 - 0.5 * math.cos(math.pi * i / max(1, n(fade_in)))
    tail = min(len(out), n(fade_out))
    for i in range(tail):
        out[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / max(1, tail))
    return out


def write(name, samples, peak=0.85, loop=False):
    """Writes mono 16-bit PCM, normalised to [peak].

    One-shot sounds get short fades at both ends; a loop must not (its ends
    meet each other, so it is built to be continuous instead).
    """
    if not loop:
        samples = edges(samples)
    top = max(1e-9, max(abs(s) for s in samples))
    scale = peak / top
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b''.join(
                struct.pack('<h', max(-32767, min(32767, int(s * scale * 32767))))
                for s in samples
            )
        )
    print(f'{name}: {len(samples) / RATE:.2f}s')


def n(seconds):
    return int(seconds * RATE)


def bell(freq, dur, amp=1.0, decay=5.0, partials=((1, 1.0), (2.01, 0.35), (3.02, 0.15))):
    """A soft glass-like bell: a few decaying sine partials."""
    out = []
    for i in range(n(dur)):
        t = i / RATE
        attack = min(1.0, t / 0.004)
        env = attack * math.exp(-decay * t)
        v = sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in partials)
        out.append(amp * env * v)
    return out


def mix(*tracks, length=None):
    length = length or max(len(t) for t in tracks)
    out = [0.0] * length
    for t in tracks:
        for i, s in enumerate(t[:length]):
            out[i] += s
    return out


def delay(track, seconds):
    return [0.0] * n(seconds) + track


def lowpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / RATE
    a = dt / (rc + dt)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def echo(samples, taps):
    """Adds quiet repeats (a tiny room)."""
    out = list(samples) + [0.0] * n(max(d for d, _ in taps))
    for d, g in taps:
        off = n(d)
        for i, s in enumerate(samples):
            out[i + off] += s * g
    return out


# --- effects ---------------------------------------------------------------

def select():
    # A tiny glass "tink" when a bottle is picked up.
    return bell(1568, 0.22, decay=22, partials=((1, 1.0), (2.76, 0.4), (5.4, 0.12)))


def glass_move():
    # Glass sliding/lifting: a short filtered-noise swish plus a soft knock.
    rnd = random.Random(7)
    swish = []
    length = n(0.32)
    for i in range(length):
        t = i / length
        env = math.sin(math.pi * t) ** 2
        swish.append((rnd.random() * 2 - 1) * env * 0.5)
    swish = lowpass(swish, 1800)
    knock = bell(392, 0.18, amp=0.7, decay=26, partials=((1, 1.0), (2.3, 0.25)))
    return mix(swish, delay(knock, 0.02), length=length)


def bubble(radius_mm, rnd):
    """One air bubble in water (van den Doel's model).

    A bubble rings at its Minnaert frequency (about 3.26 / radius), its pitch
    glides upward as it rings, and it dies away quickly. Water that "sounds
    like water" is thousands of these, at random times and sizes.
    """
    f0 = 3.26 / (radius_mm / 1000.0)
    damp = 0.043 * f0 + 0.0014 * f0 ** 1.5
    glide = 0.1 * damp
    dur = min(0.12, 6.0 / damp)
    out = []
    for i in range(n(dur)):
        t = i / RATE
        env = math.exp(-damp * t) * min(1.0, t / 0.0008)
        out.append(env * math.sin(2 * math.pi * f0 * (t + glide * t * t / 2)))
    return out


def bandpass(samples, low, high):
    return lowpass([a - b for a, b in zip(samples, lowpass(samples, low))], high)


def pour():
    """Liquid running out of a bottle into another.

    Three layers, all generated:
      * a steady stream: band-limited noise that swells and thins slowly;
      * a dense, random shower of tiny bubbles (the "babbling" of water),
        whose sizes shrink and whose rate rises as the receiving bottle
        fills, so the pitch climbs just as a real fill does;
      * a few larger, lower "glug" bubbles as the neck gulps air.
    """
    rnd = random.Random(2024)
    seconds = 1.8
    length = n(seconds)

    stream_noise = [rnd.random() * 2 - 1 for _ in range(length)]
    stream = bandpass(stream_noise, 500, 3800)
    out = [0.0] * length
    for i, v in enumerate(stream):
        t = i / RATE
        swell = 0.55 + 0.25 * math.sin(2 * math.pi * 3.1 * t) + 0.2 * math.sin(2 * math.pi * 7.9 * t + 1.3)
        out[i] = v * swell * 1.6

    def place(sound, at, gain):
        start = n(at)
        for k, v in enumerate(sound):
            if start + k < length:
                out[start + k] += v * gain

    t = 0.02
    while t < seconds - 0.12:
        fill = t / seconds                       # 0 empty .. 1 full
        rate = 140 + 260 * fill                  # bubbles per second
        t += rnd.expovariate(rate)
        radius = rnd.uniform(0.7, 2.6) * (1.0 - 0.45 * fill)
        place(bubble(radius, rnd), t, rnd.uniform(0.15, 0.5))

    for at, r in [(0.30, 5.5), (0.62, 5.0), (0.95, 4.4), (1.25, 3.9), (1.5, 3.4)]:
        place(bubble(r, rnd), at + rnd.uniform(-0.03, 0.03), 0.8)

    # Fade the whole pour in and out so it starts and stops softly.
    for i in range(length):
        t = i / RATE
        out[i] *= min(1.0, t / 0.12, (seconds - t) / 0.2)
    return out


def invalid():
    # Gentle "no": two soft falling tones, never harsh.
    a = bell(262, 0.16, decay=16, partials=((1, 1.0), (2, 0.2)))
    b = bell(196, 0.22, decay=14, partials=((1, 1.0), (2, 0.2)))
    return mix(a, delay(b, 0.1))


def complete():
    # A rising pentatonic arpeggio that blooms into a chord.
    notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
    parts = [delay(bell(f, 1.2, amp=0.6, decay=3.4), 0.11 * i) for i, f in enumerate(notes)]
    chord = [delay(bell(f, 1.6, amp=0.35, decay=2.2), 0.62) for f in (523.25, 659.25, 783.99)]
    return echo(mix(*parts, *chord), [(0.18, 0.28), (0.37, 0.14)])


def unlock():
    # Sparkle: fast shimmering high notes, then one warm low bell.
    rnd = random.Random(23)
    scale = [1046.5, 1174.7, 1318.5, 1568.0, 1760.0, 2093.0, 2349.3]
    sparks = []
    for i in range(9):
        f = scale[rnd.randrange(len(scale))]
        sparks.append(delay(bell(f, 0.5, amp=0.45, decay=9), 0.055 * i))
    base = delay(bell(392, 1.2, amp=0.7, decay=3.0), 0.5)
    return echo(mix(*sparks, base), [(0.15, 0.25), (0.3, 0.12)])


# --- music -----------------------------------------------------------------

def music():
    """A calm, slowly breathing pad that loops seamlessly (~32 s).

    Four chords of 8 s each; every chord fades with a raised-cosine window
    that overlaps its neighbours, wrapping from the last chord back to the
    first, so the loop point has no click.
    """
    chord_len = 8.0
    total = n(chord_len * 4)
    chords = [
        (110.00, 164.81, 220.00, 261.63, 329.63),   # A minor
        (87.31, 130.81, 174.61, 220.00, 261.63),    # F major
        (130.81, 196.00, 261.63, 329.63, 392.00),   # C major
        (98.00, 146.83, 196.00, 246.94, 293.66),    # G major
    ]
    out = [0.0] * total
    for ci, freqs in enumerate(chords):
        start = ci * chord_len
        for i in range(n(chord_len * 2)):          # window spans two slots
            t = i / RATE
            w = math.sin(math.pi * t / (chord_len * 2)) ** 2
            idx = (n(start - chord_len / 2) + i) % total
            v = 0.0
            for k, f in enumerate(freqs):
                for detune in (-0.6, 0.6):
                    v += math.sin(2 * math.pi * (f + detune * 0.1 * (k + 1)) * (t + start)) / (k + 2)
            trem = 0.85 + 0.15 * math.sin(2 * math.pi * 0.23 * (t + start))
            out[idx] += v * w * trem * 0.12
    # a few sparse, soft bell notes from a pentatonic set (seeded)
    rnd = random.Random(5)
    pent = [523.25, 587.33, 659.25, 783.99, 880.0]
    for i in range(7):
        when = 1.5 + i * 4.3
        note = bell(pent[rnd.randrange(len(pent))], 3.0, amp=0.07, decay=1.6)
        for j, s in enumerate(note):
            out[(n(when) + j) % total] += s
    return out


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('select.wav', select())
    write('glass_move.wav', glass_move())
    write('pour.wav', pour(), peak=0.7)
    write('invalid.wav', invalid(), peak=0.7)
    write('complete.wav', complete())
    write('unlock.wav', unlock())
    write('music_ambient.wav', music(), peak=0.6, loop=True)
