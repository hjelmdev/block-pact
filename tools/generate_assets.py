#!/usr/bin/env python3
"""Generates the placeholder pixel-art textures and retro sound effects.

Everything produced here is a *placeholder* that is referenced only through
resources (BlockSkin, PlayerPalette, SoundLibrary, TouchControls exports),
so replacing a file – or pointing a resource at a new one – needs no code.

Usage:  python3 tools/generate_assets.py   (needs numpy + pillow)
"""
import math
import os
import wave

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "skins", "default", "textures")
PAT = os.path.join(ROOT, "skins", "default", "patterns")
ICONS = os.path.join(ROOT, "ui", "icons")
SFX = os.path.join(ROOT, "audio", "sfx")
MUSIC = os.path.join(ROOT, "audio", "music")
RATE = 22050


# --------------------------------------------------------------------------
# Textures

def save_gray_alpha(arr_v, arr_a, path):
    """arr_v / arr_a: float arrays 0..1 -> RGBA png (value in RGB)."""
    v = (np.clip(arr_v, 0, 1) * 255).astype(np.uint8)
    a = (np.clip(arr_a, 0, 1) * 255).astype(np.uint8)
    img = np.dstack([v, v, v, a])
    Image.fromarray(img, "RGBA").save(path)


def block_base():
    # Shade map: 0.0 = dark edge, 0.5 = player base color, 1.0 = highlight.
    n = 16
    v = np.zeros((n, n))
    for y in range(n):
        for x in range(n):
            if x == 0 or y == 0 or x == n - 1 or y == n - 1:
                v[y, x] = 0.05
            elif x == 1 or y == 1:
                v[y, x] = 0.92
            elif x == n - 2 or y == n - 2:
                v[y, x] = 0.28
            else:
                t = (y - 2) / (n - 5)
                v[y, x] = 0.72 - 0.24 * t
    for (x, y) in [(3, 3), (4, 3), (3, 4)]:
        v[y, x] = 1.0
    save_gray_alpha(v, np.ones((n, n)), os.path.join(TEX, "block_base.png"))


def glow():
    n = 32
    yy, xx = np.mgrid[0:n, 0:n]
    d = np.sqrt((xx - (n - 1) / 2) ** 2 + (yy - (n - 1) / 2) ** 2) / (n / 2)
    a = np.clip(1 - d, 0, 1) ** 2
    save_gray_alpha(np.ones((n, n)), a, os.path.join(TEX, "glow.png"))


def ghost():
    n = 16
    a = np.full((n, n), 0.12)
    a[0, :] = a[-1, :] = a[:, 0] = a[:, -1] = 0.85
    save_gray_alpha(np.ones((n, n)), a, os.path.join(TEX, "ghost.png"))


def cell_bg():
    n = 16
    v = np.full((n, n), 1.0)
    a = np.zeros((n, n))
    a[0, :] = 0.06
    a[:, 0] = 0.06
    a[0, 0] = 0.12
    save_gray_alpha(v, a, os.path.join(TEX, "cell_bg.png"))


def particle():
    n = 4
    save_gray_alpha(np.ones((n, n)), np.ones((n, n)), os.path.join(TEX, "particle.png"))


def patterns():
    n = 16
    defs = {
        "none": lambda x, y: False,
        "diagonal": lambda x, y: (x + y) % 6 == 0,
        "dots": lambda x, y: x % 5 == 2 and y % 5 == 2,
        "cross": lambda x, y: (x == 7 or y == 7) and 4 <= x <= 11 and 4 <= y <= 11,
        "stripes": lambda x, y: y % 4 == 1,
        "checker": lambda x, y: ((x // 4) + (y // 4)) % 2 == 0 and 2 <= x <= 13 and 2 <= y <= 13,
        "ring": lambda x, y: max(abs(x - 7.5), abs(y - 7.5)) in (3.5,),
        "diamond": lambda x, y: abs(x - 7.5) + abs(y - 7.5) == 5,
    }
    for name, f in defs.items():
        a = np.zeros((n, n))
        for y in range(n):
            for x in range(n):
                if 1 < x < n - 2 and 1 < y < n - 2 and f(x, y):
                    a[y, x] = 0.45
        save_gray_alpha(np.ones((n, n)), a, os.path.join(PAT, f"{name}.png"))


GLYPHS = {
    "x": ["101", "101", "010", "101", "101"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "5": ["111", "100", "111", "001", "111"],
}


def special_glyph(text, name):
    n = 16
    img = np.zeros((n, n, 4), dtype=np.uint8)
    w = len(text) * 4 - 1
    ox = (n - w) // 2
    oy = (n - 5) // 2
    fg = set()
    for i, ch in enumerate(text):
        rows = GLYPHS[ch]
        for gy, row in enumerate(rows):
            for gx, bit in enumerate(row):
                if bit == "1":
                    fg.add((ox + i * 4 + gx, oy + gy))
    for (x, y) in fg:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                px, py = x + dx, y + dy
                if 0 <= px < n and 0 <= py < n and (px, py) not in fg:
                    img[py, px] = (10, 10, 20, 230)
    for (x, y) in fg:
        img[y, x] = (255, 255, 255, 255)
    Image.fromarray(img, "RGBA").save(os.path.join(TEX, f"special_{name}.png"))


def icons():
    os.makedirs(ICONS, exist_ok=True)
    n = 16

    def save(name, pts):
        img = np.zeros((n, n, 4), dtype=np.uint8)
        for (x, y) in pts:
            if 0 <= x < n and 0 <= y < n:
                img[y, x] = (255, 255, 255, 255)
        Image.fromarray(img, "RGBA").resize((64, 64), Image.NEAREST).save(os.path.join(ICONS, f"{name}.png"))

    def tri_left():
        return {(x, y) for y in range(n) for x in range(n) if 4 <= x <= 11 and abs(y - 7.5) <= (x - 3.5) * 0.55}

    left = tri_left()
    save("left", left)
    save("right", {(15 - x, y) for (x, y) in left})
    down = {(y, x) for (x, y) in {(15 - x, y) for (x, y) in left}}
    save("down", down)
    hard = {(x, y - 3) for (x, y) in down if y - 3 >= 0} | {(x, 13) for x in range(3, 13)} | {(x, 14) for x in range(3, 13)}
    save("hard_drop", hard)

    def arc(cw):
        pts = set()
        for a in range(30, 330, 4):
            r = math.radians(a)
            for rr in (4.5, 5.5):
                x = 7.5 + rr * math.cos(r)
                y = 7.5 - rr * math.sin(r) if cw else 7.5 + rr * math.sin(r)
                pts.add((int(round(x)), int(round(y))))
        # arrow head near the end
        hx, hy = (12, 9) if cw else (12, 6)
        for d in range(4):
            for e in range(-d, d + 1):
                pts.add((hx + e, (hy - 3 + d) if cw else (hy + 3 - d)))
        return pts

    save("rotate_cw", arc(True))
    save("rotate_ccw", {(15 - x, y) for (x, y) in arc(True)})
    hold = {(x, y) for x in range(3, 13) for y in range(3, 13) if x in (3, 12) or y in (3, 12)}
    hold |= {(x, y) for x in range(6, 10) for y in range(6, 10)}
    save("hold", hold)
    pause = {(x, y) for x in list(range(4, 7)) + list(range(9, 12)) for y in range(3, 13)}
    save("pause", pause)


# --------------------------------------------------------------------------
# Special cells + powerups (pixel art, 16x16). Characters map to colors;
# '.' is transparent. Special overlays sit on top of the player-colored block.

PIX = {
    "#": (12, 10, 22, 235), "w": (255, 255, 255, 255), "l": (200, 205, 220, 255),
    "d": (70, 72, 90, 255), "k": (32, 32, 44, 255), "y": (255, 220, 70, 255),
    "o": (255, 150, 40, 255), "r": (240, 60, 60, 255), "c": (110, 235, 255, 255),
    "b": (60, 140, 255, 255), "g": (255, 200, 40, 255), "G": (190, 130, 20, 255),
    "p": (240, 90, 220, 255), "v": (150, 90, 255, 255), "e": (90, 230, 120, 255),
}

ART = {
    "bomb": [
        "................",
        "...........y....",
        "..........yoy...",
        ".........#.y....",
        "........#.......",
        ".....####.......",
        "....#kkkk#......",
        "...#kkwkkk#.....",
        "...#kwkkkk#.....",
        "...#kkkkkk#.....",
        "...#kkkkkk#.....",
        "....#kkkk#......",
        ".....####.......",
        "................",
        "................",
        "................",
    ],
    "megabomb": [
        "............y...",
        "...........yoy..",
        "..........#.y...",
        ".........#......",
        "....######......",
        "...#kkkkkk#.....",
        "..#kkwwkkkk#....",
        "..#kwkkkkkk#....",
        "..#kkkrrkkk#....",
        "..#kkrrrrkk#....",
        "..#kkkrrkkk#....",
        "..#kkkkkkkk#....",
        "...#kkkkkk#.....",
        "....######......",
        "................",
        "................",
    ],
    "laser": [
        "......#cc#......",
        "......#ww#......",
        "......#cc#......",
        "......#ww#......",
        "....##cwwc##....",
        "...#ccwwwwcc#...",
        "..#cwwwwwwwwc#..",
        "..#cwwwwwwwwc#..",
        "...#ccwwwwcc#...",
        "....##cwwc##....",
        "......#ww#......",
        "......#cc#......",
        "......#ww#......",
        "......#cc#......",
        "................",
        "................",
    ],
    "paint": [
        "................",
        ".......##.......",
        "......#pp#......",
        ".....#pppp#.....",
        "....#ppwppp#....",
        "...#ppwppppp#...",
        "...#pppppppp#...",
        "..#pppppppppp#..",
        "..#ppppppppvp#..",
        "..#pppppppvvp#..",
        "...#pppppvvp#...",
        "....#pppppp#....",
        ".....######.....",
        "................",
        "................",
        "................",
    ],
    "gold": [
        "................",
        ".....######.....",
        "....#gggggg#....",
        "...#ggwwgggG#...",
        "..#ggwggGgggG#..",
        "..#gwggGGGggG#..",
        "..#gggGgggggG#..",
        "..#gggGGGgggG#..",
        "..#gggggGgggG#..",
        "..#gggGGGgggG#..",
        "...#gggGggGG#...",
        "....#GGGGGG#....",
        ".....######.....",
        "................",
        "................",
        "................",
    ],
    "powerup": [
        "................",
        "...##########...",
        "..#eeeeeeeeee#..",
        "..#ewwwwwwwwe#..",
        "..#ew##ww##we#..",
        "..#ewwwww##we#..",
        "..#ewwww##wwe#..",
        "..#ewww##wwwe#..",
        "..#ewwwwwwwwe#..",
        "..#ewww##wwwe#..",
        "..#ewwwwwwwwe#..",
        "..#eeeeeeeeee#..",
        "...##########...",
        "................",
        "................",
        "................",
    ],
}

# UI icons for powerups (drawn white-ish with color; 16x16 scaled to 64).
ICON_ART = {
    "pu_bomb": ART["bomb"],
    "pu_slow": [
        "................",
        "...##########...",
        "...#llllllll#...",
        "....#cccccc#....",
        ".....#cccc#.....",
        "......#cc#......",
        ".......##.......",
        "......#..#......",
        ".....#....#.....",
        "....#..cc..#....",
        "...#..cccc..#...",
        "...#cccccccc#...",
        "...#llllllll#...",
        "...##########...",
        "................",
        "................",
    ],
    "pu_double": [
        "................",
        "................",
        "..#.#...####....",
        "..#.#..#....#...",
        "...#........#...",
        "..#.#......#....",
        "..#.#.....#.....",
        "........#.......",
        ".......#........",
        ".......######...",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    "pu_quake": [
        "................",
        "................",
        "..o.............",
        "..oo......o.....",
        "..o.o....oo.....",
        "..o..o..o.o.....",
        "..o...oo..o..o..",
        "..o.......o.oo..",
        "..o........oo...",
        "................",
        "..##.##.##.##...",
        "..#d##d##d##d#..",
        "..############..",
        "................",
        "................",
        "................",
    ],
    "pu_rush": [
        "................",
        "....r......r....",
        "....rr....rr....",
        ".....rr..rr.....",
        "......rrrr......",
        ".......rr.......",
        "....r......r....",
        "....rr....rr....",
        ".....rr..rr.....",
        "......rrrr......",
        ".......rr.......",
        "................",
        "....########....",
        "................",
        "................",
        "................",
    ],
    "power": [
        "................",
        ".........yy.....",
        "........yy......",
        ".......yy.......",
        "......yy........",
        ".....yyyyyy.....",
        "........yy......",
        ".......yy.......",
        "......yy........",
        ".....yy.........",
        "....yy..........",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
}


def _render_art(rows, scale=1):
    n = len(rows)
    img = np.zeros((n, n, 4), dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row[:n]):
            if ch in PIX:
                img[y, x] = PIX[ch]
    im = Image.fromarray(img, "RGBA")
    if scale != 1:
        im = im.resize((n * scale, n * scale), Image.NEAREST)
    return im


def _outline_white(rows):
    # The double icon is drawn with '#' strokes; render them white.
    return [r.replace("#", "w") for r in rows]


def special_art():
    for name, rows in ART.items():
        _render_art(rows).save(os.path.join(TEX, f"special_{name}.png"))
    os.makedirs(ICONS, exist_ok=True)
    for name, rows in ICON_ART.items():
        if name == "pu_double":
            rows = _outline_white(rows)
        _render_art(rows, 4).save(os.path.join(ICONS, f"{name}.png"))


AVATARS = os.path.join(ROOT, "ui", "avatars")


def avatars(count=16):
    """Symmetric pixel critters (identicon style). White body + dark outline,
    tinted with the player's color at runtime."""
    os.makedirs(AVATARS, exist_ok=True)
    rng = np.random.default_rng(20261008)
    made = 0
    attempt = 0
    while made < count and attempt < 500:
        attempt += 1
        half = rng.random((10, 5)) < 0.5
        half[:, 4] |= rng.random(10) < 0.35  # thicker spine
        half[0:2, :] &= rng.random((2, 5)) < 0.4  # sparse antennae
        body = np.concatenate([half, half[:, ::-1]], axis=1)  # 10 x 10
        filled = body.sum()
        if filled < 38 or filled > 66:
            continue
        # eyes: two holes in the upper half
        ey = int(rng.integers(3, 5))
        ex = int(rng.integers(1, 4))
        body[ey, ex] = body[ey, 9 - ex] = True
        img = np.zeros((16, 16, 4), dtype=np.uint8)
        ox, oy = 3, 3
        for y in range(10):
            for x in range(10):
                if body[y, x]:
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            px, py = ox + x + dx, oy + y + dy
                            if 0 <= px < 16 and 0 <= py < 16 and img[py, px, 3] == 0:
                                img[py, px] = (14, 12, 24, 255)
        for y in range(10):
            for x in range(10):
                if body[y, x]:
                    shade = 255 if y < 7 else 215
                    img[oy + y, ox + x] = (shade, shade, shade, 255)
        img[oy + ey, ox + ex] = img[oy + ey, ox + 9 - ex] = (14, 12, 24, 255)
        Image.fromarray(img, "RGBA").save(os.path.join(AVATARS, "avatar_%02d.png" % (made + 1)))
        made += 1


def fx_sfx():
    os.makedirs(SFX, exist_ok=True)
    w = lambda name, s, v=0.6: write(os.path.join(SFX, f"{name}.wav"), s, v)
    boom_n = int(RATE * 0.55)
    boom = noise(0.55, 11) * env(boom_n, 0.001, 0.95)
    low = osc(90, 0.55, "sine", sweep_to=30) * env(boom_n, 0.001, 0.9)
    w("explosion", mix(boom * 0.8, low), 0.8)
    big_n = int(RATE * 0.9)
    w("megabomb", mix(noise(0.9, 12) * env(big_n, 0.001, 0.97), osc(70, 0.9, "sine", sweep_to=20) * env(big_n, 0.001, 0.95) * 1.2), 0.85)
    zap = osc(2400, 0.35, "saw", sweep_to=200) * env(int(RATE * 0.35), 0.001, 0.8)
    w("laser", mix(zap, osc(1200, 0.35, "square", 0.1, sweep_to=100) * env(int(RATE * 0.35), 0.001, 0.8) * 0.5), 0.5)
    splash = noise(0.3, 13) * env(int(RATE * 0.3), 0.01, 0.9)
    w("paint", mix(splash * 0.5, seq([tone(n_, 0.05, "tri") for n_ in (79, 76, 83, 88)])), 0.5)
    w("gold", seq([tone(95, 0.05, "square", 0.25), tone(100, 0.25, "square", 0.25, 0.8)]), 0.45)
    w("powerup_get", seq([tone(n_, 0.04, "square", 0.25) for n_ in (72, 79, 84, 91)] + [tone(96, 0.2, "tri", rel=0.8)]), 0.5)
    w("powerup_use", mix(osc(300, 0.3, "square", 0.25, sweep_to=1500) * env(int(RATE * 0.3), 0.002, 0.7), noise(0.3, 14) * env(int(RATE * 0.3), 0.01, 0.9) * 0.2), 0.45)
    rum_n = int(RATE * 0.8)
    t = np.arange(rum_n) / RATE
    rum = noise(0.8, 15) * env(rum_n, 0.02, 0.9) * (0.6 + 0.4 * np.sin(2 * math.pi * 9 * t))
    w("quake", mix(rum, osc(55, 0.8, "sine") * env(rum_n, 0.02, 0.9)), 0.75)
    w("slow", seq([tone(n_, 0.12, "tri") for n_ in (79, 74, 67)]), 0.45)
    w("rush", seq([tone(n_, 0.035, "square", 0.25) for n_ in (60, 67, 72, 79, 84, 91, 96)]), 0.45)


# --------------------------------------------------------------------------
# Sound

def env(n, attack=0.005, release=0.5):
    t = np.arange(n) / RATE
    dur = n / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((dur - t) / max(dur * release, 1e-4), 0, 1)
    return a * r


def osc(freq, dur, kind="square", duty=0.5, sweep_to=None):
    n = int(RATE * dur)
    f = np.full(n, float(freq)) if sweep_to is None else np.linspace(freq, sweep_to, n)
    phase = np.cumsum(f) / RATE
    frac = phase % 1.0
    if kind == "square":
        return np.where(frac < duty, 1.0, -1.0)
    if kind == "tri":
        return 4 * np.abs(frac - 0.5) - 1
    if kind == "saw":
        return 2 * frac - 1
    return np.sin(2 * math.pi * phase)


def noise(dur, seed=0):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, int(RATE * dur))


def seq(parts):
    return np.concatenate(parts)


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[: len(s)] += s
    return out


def write(path, sig, vol=0.6):
    sig = np.asarray(sig, dtype=float)
    peak = np.max(np.abs(sig)) or 1
    data = (sig / peak * vol * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def note(n):
    """MIDI note -> Hz"""
    return 440.0 * 2 ** ((n - 69) / 12)


def tone(n, dur, kind="square", duty=0.5, rel=0.6):
    s = osc(note(n), dur, kind, duty)
    return s * env(len(s), 0.003, rel)


def sfx():
    os.makedirs(SFX, exist_ok=True)
    w = lambda name, s, v=0.6: write(os.path.join(SFX, f"{name}.wav"), s, v)
    s = osc(1400, 0.025, "square", 0.25); w("move", s * env(len(s), 0.001, 0.8), 0.25)
    s = osc(700, 0.05, "square", 0.25, sweep_to=1300); w("rotate", s * env(len(s), 0.002, 0.6), 0.3)
    s = osc(260, 0.02, "tri"); w("soft_drop", s * env(len(s), 0.001, 0.9), 0.2)
    thump = osc(140, 0.14, "sine", sweep_to=45) * env(int(RATE * 0.14), 0.001, 0.9)
    crack = noise(0.06, 1) * env(int(RATE * 0.06), 0.001, 0.9)
    w("hard_drop", mix(thump, crack * 0.5), 0.75)
    s = mix(osc(190, 0.08, "square", 0.5, sweep_to=90) * env(int(RATE * 0.08), 0.001, 0.9),
            noise(0.03, 2) * env(int(RATE * 0.03), 0.001, 0.9) * 0.3)
    w("lock", s, 0.45)
    w("hold", seq([tone(72, 0.05, "tri"), tone(79, 0.07, "tri")]), 0.4)

    base = 72
    chords = {1: [0, 4, 7], 2: [0, 4, 7, 12], 3: [0, 4, 7, 12, 16], 4: [0, 4, 7, 12, 16, 19, 24]}
    for k, notes in chords.items():
        step = 0.045 if k < 4 else 0.04
        parts = [tone(base + i, step, "square", 0.25, 0.5) for i in notes[:-1]]
        parts.append(tone(base + notes[-1], 0.25 + 0.05 * k, "square", 0.25, 0.8))
        sig = seq(parts)
        shimmer = osc(note(base + 24), len(sig) / RATE, "tri") * env(len(sig), 0.01, 1.0) * 0.15
        w(f"line_{k}", mix(sig, shimmer), 0.5 + 0.05 * k)

    w("combo", seq([tone(84, 0.04, "square", 0.125), tone(91, 0.08, "square", 0.125)]), 0.4)

    n = int(RATE * 0.5)
    t = np.arange(n) / RATE
    vib = np.sin(2 * math.pi * 14 * t) * 30
    sp = np.sin(2 * math.pi * np.cumsum(note(96) + vib) / RATE) * env(n, 0.005, 0.9)
    arp = seq([tone(n_, 0.05, "square", 0.125, 0.4) for n_ in (84, 88, 91, 96, 100, 103)])
    sparkle = noise(0.5, 3) * env(n, 0.01, 0.95) * 0.12 * (np.sin(2 * math.pi * 30 * t) > 0)
    w("special_x", mix(arp, sp * 0.5, sparkle), 0.6)

    s = osc(1760, 0.08, "sine"); w("score_arrive", s * env(len(s), 0.001, 0.95), 0.25)
    w("level_up", seq([tone(n_, 0.07, "square", 0.25) for n_ in (67, 71, 74, 79)] + [tone(83, 0.3, "square", 0.25, 0.8)]), 0.55)
    s = osc(500, 0.6, "square", 0.5, sweep_to=60); w("top_out", s * env(len(s), 0.005, 0.7), 0.5)
    w("game_over", seq([tone(n_, d, "tri", rel=0.4) for n_, d in ((67, 0.2), (63, 0.2), (60, 0.2), (55, 0.6))]), 0.6)
    w("countdown", tone(76, 0.12, "square", 0.25), 0.4)
    w("go", tone(88, 0.3, "square", 0.25, 0.8), 0.45)
    # Steal: quick "swipe" down-up with a little sparkle.
    swipe = osc(1200, 0.12, "square", 0.25, sweep_to=500) * env(int(RATE * 0.12), 0.002, 0.6)
    w("steal", seq([swipe, tone(88, 0.05, "square", 0.125), tone(95, 0.12, "square", 0.125, 0.8)]), 0.5)
    w("lead_change", seq([tone(n_, 0.06, "square", 0.25) for n_ in (72, 76, 79)] + [tone(84, 0.22, "square", 0.25, 0.8)]), 0.45)
    w("lead_lost", seq([tone(n_, 0.09, "tri") for n_ in (76, 72)] + [tone(67, 0.25, "tri", rel=0.8)]), 0.5)
    w("ui_click", tone(84, 0.025, "square", 0.25, 0.9), 0.25)
    w("ui_back", tone(72, 0.04, "square", 0.25, 0.9), 0.25)


def music():
    os.makedirs(MUSIC, exist_ok=True)
    bpm = 132
    beat = 60 / bpm
    eighth = beat / 2
    # Am – F – C – G, 2 bars each, simple arpeggiated lead.
    prog = [(57, [0, 3, 7]), (53, [0, 4, 7]), (60, [0, 4, 7]), (55, [0, 4, 7])]
    total = int(RATE * eighth * 8 * 2 * len(prog))
    out = np.zeros(total)
    pos = 0
    lead_pattern = [0, 2, 1, 2, 0, 2, 1, 3]
    for root, chord in prog:
        for bar in range(2):
            for i in range(8):
                n_ = int(RATE * eighth)
                # bass
                b = osc(note(root - 12), eighth, "tri") * env(n_, 0.002, 0.3)
                out[pos:pos + n_] += b * 0.5
                # lead arp
                idx = lead_pattern[i]
                pitch = root + 12 + (chord + [12])[idx]
                if bar == 1 and i >= 6:
                    pitch += 12 if i == 7 else 7
                l = osc(note(pitch), eighth, "square", 0.25) * env(n_, 0.002, 0.5)
                out[pos:pos + n_] += l * 0.18
                # hats / kick
                if i % 2 == 1:
                    h = noise(0.03, i) * env(int(RATE * 0.03), 0.001, 0.9)
                    out[pos:pos + len(h)] += h * 0.08
                if i % 4 == 0:
                    k = osc(110, 0.09, "sine", sweep_to=40) * env(int(RATE * 0.09), 0.001, 0.9)
                    out[pos:pos + len(k)] += k * 0.5
                pos += n_
    write(os.path.join(MUSIC, "theme_loop.wav"), out, 0.5)


if __name__ == "__main__":
    import sys
    for d in (TEX, PAT, SFX, MUSIC):
        os.makedirs(d, exist_ok=True)
    if "--avatars-only" in sys.argv:
        avatars()
        sys.exit(0)
    if "--fx-only" in sys.argv:
        special_art()
        fx_sfx()
        sys.exit(0)
    only_sfx = "--sfx-only" in sys.argv
    if not only_sfx:
        block_base(); glow(); ghost(); cell_bg(); particle(); patterns()
        special_glyph("x2", "x2"); special_glyph("x3", "x3"); special_glyph("x5", "x5")
        icons()
        music()
    sfx()
    print("assets generated")
