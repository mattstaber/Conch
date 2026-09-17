#!/usr/bin/env python3
"""Generate a quiet synthetic reference for manual QuickTime tests; never records."""
import math
import struct
import wave
from pathlib import Path
output = Path(__file__).resolve().parent.parent / 'build' / 'synthetic-tone.wav'
output.parent.mkdir(exist_ok=True)
rate = 48000
# -34 dBFS peak: start with a modest physical output volume.
second = b''.join(struct.pack('<hh', *([int(32767 * .02 * math.sin(2 * math.pi * 440 * i / rate))] * 2)) for i in range(rate))
with wave.open(str(output), 'wb') as stream:
    stream.setnchannels(2); stream.setsampwidth(2); stream.setframerate(rate)
    for _ in range(120): stream.writeframes(second)
print(output)
