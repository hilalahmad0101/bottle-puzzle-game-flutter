# Audio

Every file here is **original**. They were synthesised from scratch by
[`tool/generate_audio.py`](../../tool/generate_audio.py) using only sine
waves, seeded noise and simple envelopes: no recording, sample pack, loop
library or third-party music was used. There is nothing to license and no
attribution is required. The project owner holds all rights.

Run `python3 tool/generate_audio.py` to regenerate them exactly (the noise is
seeded, so the output is reproducible).

| File | Used for |
| --- | --- |
| `select.wav` | picking up / putting down a bottle, a hint appearing |
| `glass_move.wav` | the glass lifting as a pour begins |
| `pour.wav` | soft liquid while a pour is shown |
| `invalid.wav` | a tap that cannot be a move (two soft falling tones) |
| `complete.wav` | level complete |
| `unlock.wav` | a new bottle design or a new journey chapter |
| `music_ambient.wav` | optional ambient background music (32 s seamless loop) |

Format: 16-bit mono PCM WAV at 22.05 kHz, kept small on purpose.

If you replace any of these with other material, only use sounds you have the
right to ship, and record where they came from here.
