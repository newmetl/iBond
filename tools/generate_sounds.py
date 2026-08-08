#!/usr/bin/env python3
"""Synthesizes Laser Taser's sound set as 16-bit mono WAVs (stdlib only).

Loops are built from integer numbers of cycles (or envelopes that reach zero
at the edges) so they are seamless. Output goes to App/Sounds/.
"""
import math
import random
import struct
import wave

random.seed(20260808)

def write_wav(path, samples, rate):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b"".join(
            struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767))
            for s in samples))
    print(f"{path}: {len(samples) / rate:.2f}s")

def saw(phase):
    return 2.0 * (phase - math.floor(phase + 0.5))

def square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0

# --- Player laser "BWWWWT": detuned saw buzz with slow AM, 0.4s loop -------
RATE = 44100
n = int(0.4 * RATE)
laser = []
for i in range(n):
    t = i / RATE
    am = 1.0 + 0.25 * math.sin(2 * math.pi * 7.5 * t)          # 3 cycles
    s = 0.6 * saw(150 * t) + 0.4 * saw(152.5 * t)              # 60 + 61 cycles
    laser.append(0.8 * am * s)
write_wav("App/Sounds/laser_loop.wav", laser, RATE)

# --- Shooter aim "mmmmmm": beating low hum, 1s loop -------------------------
n = int(1.0 * RATE)
aim = []
for i in range(n):
    t = i / RATE
    s = (math.sin(2 * math.pi * 110 * t) + math.sin(2 * math.pi * 112 * t)) * 0.5
    s += 0.3 * math.sin(2 * math.pi * 220 * t)
    aim.append(0.7 * s)
write_wav("App/Sounds/shooter_aim_loop.wav", aim, RATE)

# --- Shooter shot "ZZZZZZT": crackling square sweep, one-shot ---------------
n = int(0.35 * RATE)
zap = []
phase = 0.0
for i in range(n):
    t = i / RATE
    freq = 300 * (80 / 300) ** (t / 0.35)                       # 300 -> 80 Hz
    phase += freq / RATE
    crackle = 1.0 + 0.5 * math.sin(2 * math.pi * 30 * t)
    env = 1.0 if t < 0.3 else max(0.0, 1.0 - (t - 0.3) / 0.05)
    s = 0.6 * square(phase) + 0.4 * random.uniform(-1, 1)
    zap.append(env * crackle * s * 0.7)
write_wav("App/Sounds/shooter_fire.wav", zap, RATE)

# --- Runner steps "takatakataka": 4 clicky bursts, 0.5s loop -----------------
n = int(0.5 * RATE)
steps = [0.0] * n
for k in range(4):
    start = int(k * 0.125 * RATE)
    tone = 1400 if k % 2 == 0 else 1750                          # ta-ka
    for j in range(int(0.02 * RATE)):
        t = j / RATE
        env = math.exp(-t / 0.004)
        s = 0.6 * random.uniform(-1, 1) + 0.6 * math.sin(2 * math.pi * tone * t)
        steps[start + j] += env * s
write_wav("App/Sounds/runner_steps_loop.wav", steps, RATE)

# --- Death "OUCH!": falling square yelp, one-shot ----------------------------
n = int(0.3 * RATE)
ouch = []
phase = 0.0
for i in range(n):
    t = i / RATE
    freq = 700 * (330 / 700) ** (t / 0.3)                        # 700 -> 330 Hz
    freq *= 1.0 + 0.04 * math.sin(2 * math.pi * 24 * t)          # vibrato
    phase += freq / RATE
    env = min(1.0, t / 0.01) * math.exp(-t / 0.16)
    s = 0.7 * square(phase) + 0.3 * square(2 * phase)
    ouch.append(env * s)
write_wav("App/Sounds/ouch.wav", ouch, RATE)

# --- Music: dark futuristic ominous drone, 32s seamless loop -----------------
MRATE = 22050
DUR = 32
n = MRATE * DUR
music = [0.0] * n
# Low drone: A1 + harmonics, slow 4-cycle LFO (all integer cycles over 32s).
for i in range(n):
    t = i / MRATE
    lfo = 0.8 + 0.2 * math.sin(2 * math.pi * 0.125 * t)
    s = (math.sin(2 * math.pi * 55 * t)
         + 0.5 * math.sin(2 * math.pi * 110 * t)
         + 0.25 * math.sin(2 * math.pi * 165 * t + 0.5))
    music[i] += 0.30 * lfo * s
# Heartbeat thump each second: pitch-dropping sine with a click of noise.
for beat in range(DUR):
    start = beat * MRATE
    for j in range(int(0.35 * MRATE)):
        t = j / MRATE
        freq = 55 * (40 / 55) ** (t / 0.35)
        env = math.exp(-t / 0.09)
        music[start + j] += 0.5 * env * math.sin(2 * math.pi * freq * t)
        if j < int(0.004 * MRATE):
            music[start + j] += 0.15 * random.uniform(-1, 1)
# Tense high notes every 8 bars: Eb (tritone vs A) - C - B - Bb, swelling.
for bar, freq in enumerate([622, 523, 494, 466]):
    start = bar * 8 * MRATE
    for j in range(6 * MRATE):
        t = j / MRATE
        env = min(1.0, t / 1.5) * max(0.0, 1.0 - max(0.0, t - 3.0) / 3.0)
        trem = 1.0 + 0.3 * math.sin(2 * math.pi * 5 * t)
        music[start + j] += 0.10 * env * trem * math.sin(2 * math.pi * freq * t)
# Filtered-noise swells peaking mid-cycle, zero at the loop edges (16s period).
lp = 0.0
for i in range(n):
    t = i / MRATE
    swell = math.sin(math.pi * ((t % 16) / 16)) ** 2
    lp += 0.08 * (random.uniform(-1, 1) - lp)
    music[i] += 0.14 * swell * lp
write_wav("App/Sounds/music_loop.wav", music, MRATE)

# --- Player death "NOOOO": long dramatic two-stage fall, one-shot ------------
# Deeper and much longer than the NPC ouch so your own death is unmistakable:
# impact noise, then a square-wave wail sliding 500 -> 100 Hz with widening
# vibrato and a low sine underneath.
n = int(0.8 * RATE)
death = []
phase = 0.0
for i in range(n):
    t = i / RATE
    freq = 500 * (100 / 500) ** (t / 0.8)
    freq *= 1.0 + (0.03 + 0.08 * t) * math.sin(2 * math.pi * 11 * t)
    phase += freq / RATE
    env = min(1.0, t / 0.012) * math.exp(-t / 0.35)
    s = 0.55 * square(phase) + 0.35 * math.sin(math.pi * phase)  # sub-octave sine
    if t < 0.05:
        s += (1.0 - t / 0.05) * 0.7 * random.uniform(-1, 1)
    death.append(env * s)
write_wav("App/Sounds/player_death.wav", death, RATE)
