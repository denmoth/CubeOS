# -*- coding: utf-8 -*-
"""Треки для проигрывателя Jukebox: нотные файлы .csc (assets/music). Запуск: python tools/make_music.py

Формат CSC1 (текст): строки "title ...", "by ...", "bpm N" (темп, шаг это шестнадцатая), "steps N" (длина в шагах), затем
паттерны "p ИМЯ шаг:инструмент:высота[+высота]:громкость ..." (шаги внутри паттерна от 0) и размещения "@ ШАГ ИМЯ".
Высота это номер ноты CC (0..24) для инструмента, играет audiod (playNote). Одинаковые такты хранятся одним паттерном.
Ноты тут пишутся как в нотной записи (A4 = 69) и сами подбирают инструмент из списка предпочтений, в диапазон которого попадают.
"""
import os
import re
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# диапазоны инструментов (midi: F#3 = 54): нота = midi - начало, должна быть 0..24
RANGE = {
    "harp": 54, "pling": 54, "bit": 54, "banjo": 54, "iron_xylophone": 54,
    "bass": 30, "didgeridoo": 30, "guitar": 42,
    "flute": 66, "cow_bell": 66,
    "bell": 78, "chime": 78, "xylophone": 78,
}
DRUM = {"basedrum": 6, "snare": 12, "hat": 20}

NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    m = re.match(r"^([A-G])(#|b)?(-?\d)$", name)
    if not m:
        raise ValueError(name)
    v = 12 * (int(m.group(3)) + 1) + NOTES[m.group(1)]
    if m.group(2) == "#":
        v += 1
    elif m.group(2) == "b":
        v -= 1
    return v


def pick(m, prefs):
    for inst in prefs:
        base = RANGE[inst]
        if 0 <= m - base <= 24:
            return inst, m - base
    # ни один не подошёл: переносим на октаву в диапазон первого
    inst = prefs[0]
    base = RANGE[inst]
    while m - base < 0:
        m += 12
    while m - base > 24:
        m -= 12
    return inst, m - base


class Song:
    def __init__(self, title, bpm, key=""):
        self.title = title
        self.bpm = bpm
        self.ev = {}  # шаг -> список (приоритет, инструмент, высоты, громкость)
        self.bars = 0
        self.key = key

    def add(self, step, prefs, notes, vol=2, prio=5):
        """notes: имя ноты или список имён (аккорд); prefs: список инструментов по предпочтению."""
        if isinstance(notes, str):
            notes = [notes]
        if isinstance(prefs, str):
            prefs = [prefs]
        by_inst = OrderedDict()
        for n in notes:
            inst, p = pick(midi(n), prefs)
            by_inst.setdefault(inst, []).append(p)
        for inst, ps in by_inst.items():
            self.ev.setdefault(step, []).append((prio, inst, ps, vol))
        self.bars = max(self.bars, step // 16 + 1)

    def drum(self, step, kind, vol=2, pitch=None):
        self.ev.setdefault(step, []).append((2, kind, [DRUM[kind] if pitch is None else pitch], vol))
        self.bars = max(self.bars, step // 16 + 1)

    def melody(self, start_bar, text, prefs, vol=2, prio=1):
        """text: такты через '|', в такте "шаг:нота" через пробел."""
        for i, bar in enumerate(text.split("|")):
            for tok in bar.split():
                st, note = tok.split(":")
                v = vol
                if note.endswith("!"):
                    note = note[:-1]
                    v = min(3, vol + 1)
                self.add((start_bar + i) * 16 + int(st), prefs, note, v, prio)

    def render(self):
        steps = self.bars * 16
        # не больше 7 нот на шаг: лишние (самые неважные) отбрасываются
        bars = {}
        for st in sorted(self.ev):
            evs = sorted(self.ev[st], key=lambda e: e[0])
            kept = []
            count = 0
            for prio, inst, ps, vol in evs:
                for p in ps:
                    if count < 7:
                        kept.append((inst, p, vol))
                        count += 1
            b = st // 16
            bars.setdefault(b, []).append((st % 16, kept))
        patterns = OrderedDict()
        placements = []
        for b in range(self.bars):
            items = bars.get(b, [])
            toks = []
            for off, kept in items:
                merged = OrderedDict()
                for inst, p, vol in kept:
                    merged.setdefault((inst, vol), []).append(p)
                for (inst, vol), ps in merged.items():
                    toks.append("%d:%s:%s:%d" % (off, inst, "+".join(str(x) for x in ps), vol))
            if not toks:
                continue
            body = " ".join(toks)
            if body not in patterns:
                patterns[body] = "b%d" % len(patterns)
            placements.append((b * 16, patterns[body]))
        out = ["CSC1", "title " + self.title, "by Claude", "bpm %d" % self.bpm, "steps %d" % steps]
        if self.key:
            out.append("key " + self.key)
        for body, name in patterns.items():
            out.append("p %s %s" % (name, body))
        for st, name in placements:
            out.append("@ %d %s" % (st, name))
        return "\n".join(out) + "\n"


def save(song, slug):
    d = os.path.join(ROOT, "assets", "music")
    os.makedirs(d, exist_ok=True)
    text = song.render()
    with open(os.path.join(d, slug + ".csc"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    secs = song.bars * 16 * 60 / song.bpm / 4
    print("%-16s %3d bars  %4d s  %5d bytes" % (slug, song.bars, secs, len(text)))


def drums_basic(s, bar, kick=True, snare=True, hat=True, open_hat=True, fill=False):
    b = bar * 16
    if kick:
        for st in (0, 4, 8, 12):
            s.drum(b + st, "basedrum", 3 if st == 0 else 2)
    if snare:
        for st in (4, 12):
            s.drum(b + st, "snare", 2)
    if hat:
        for st in range(0, 16, 2):
            s.drum(b + st, "hat", 2 if st % 4 == 2 and open_hat else 1)
    if fill:
        for st in (12, 13, 14, 15):
            s.drum(b + st, "snare", 1 + (st - 12) // 2 + 0)


# ---------------------------------------------------------------- 1. Neon Drive (синтвейв, ля минор)
def neon_drive():
    s = Song("Neon Drive", 118, "A minor")
    chords = [("A2", ["A3", "C4", "E4", "A4"]), ("F2", ["F3", "A3", "C4", "F4"]), ("C3", ["C4", "E4", "G4", "C5"]), ("G2", ["G3", "B3", "D4", "G4"])]
    P1 = ("0:E5 3:E5 4:D5 6:C5 8:D5 10:E5 12:A5!|0:F5 3:E5 4:C5 8:A4 10:C5 12:F5|"
          "0:E5 3:E5 4:G5 6:E5 8:D5 10:C5 12:D5 14:E5|0:D5 3:B4 4:D5 8:G5! 12:E5 14:D5")
    P2 = ("0:A5! 3:G5 4:E5 6:G5 8:A5 10:C6 12:A5|0:F5 2:A5 4:C6! 6:A5 8:F5 12:E5|"
          "0:G5 3:E5 4:C5 8:E5 10:G5 12:C6!|0:B5 2:A5 4:G5 6:D5 8:G5 10:F5 12:E5 14:D5")
    arp_idx = [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 3]
    layers = {  # (с такта, по такт): что играет
        "arp": [(0, 72)], "bass": [(8, 72)], "drums": [(8, 72)], "lead": [(24, 40), (48, 64)], "stab": [(16, 40), (48, 64)],
    }
    total = 72
    for bar in range(total):
        ch = chords[bar % 4]
        root, tones = ch

        def on(layer):
            return any(a <= bar < b for a, b in layers[layer])
        if on("arp"):
            soft = bar < 8
            for st in range(16):
                s.add(bar * 16 + st, ["pling", "bit"], tones[arp_idx[st]], 1 if soft or st % 4 else 2, 7)
        if on("bass"):
            for st in (0, 3, 6, 8, 11, 14):
                s.add(bar * 16 + st, ["bass", "didgeridoo"], root, 3 if st == 0 else 2, 3)
        if on("drums"):
            # в последнем такте каждой секции заполнение
            drums_basic(s, bar, fill=(bar % 8 == 7 and bar > 8), snare=bar >= 12 or bar % 8 > 3)
        elif bar >= 4:
            for st in range(0, 16, 4):
                s.drum(bar * 16 + st, "hat", 1)
        if on("stab"):
            for st in (0, 10):
                s.add(bar * 16 + st, ["harp"], tones[:3], 1, 8)
        if bar == 0:
            s.drum(0, "basedrum", 2)
    # мелодия: куплет с P1 дважды, припев с P2, срыв, финал
    s.melody(24, P1, ["flute"], 2)
    s.melody(28, P1, ["flute"], 2)
    s.melody(32, P2, ["flute"], 2)
    s.melody(36, P1, ["flute"], 2)
    s.melody(48, P2, ["flute", "bell"], 3)
    s.melody(52, P1, ["flute"], 2)
    s.melody(56, P2, ["flute", "bell"], 3)
    s.melody(60, P2, ["bell", "flute"], 2)
    # эхо мелодии колокольчиком в припевах
    for start in (32, 48, 56):
        for bar in range(start, start + 4):
            for st in (2, 6, 10, 14):
                if (bar + st) % 3 == 0:
                    s.add(bar * 16 + st, ["bell", "chime"], chords[bar % 4][1][2], 1, 6)
    # концовка: плавное затухание на тонике
    s.add(71 * 16, ["bell"], "A5", 3, 1)
    s.add(71 * 16 + 8, ["flute"], "E5", 2, 1)
    save(s, "neon-drive")


# ---------------------------------------------------------------- 2. Block Sunrise (рассвет, ре мажор)
def block_sunrise():
    s = Song("Block Sunrise", 84, "D major")
    prog = [("D2", ["D4", "F#4", "A4", "D5"]), ("A2", ["A3", "C#4", "E4", "A4"]), ("B2", ["B3", "D4", "F#4", "B4"]), ("G2", ["G3", "B3", "D4", "G4"])]
    prog2 = [("D2", ["D4", "F#4", "A4", "D5"]), ("A2", ["A3", "C#4", "E4", "A4"]), ("B2", ["B3", "D4", "F#4", "B4"]), ("F#2", ["F#3", "A3", "C#4", "F#4"]),
             ("G2", ["G3", "B3", "D4", "G4"]), ("D2", ["D4", "F#4", "A4", "D5"]), ("G2", ["G3", "B3", "D4", "G4"]), ("A2", ["A3", "C#4", "E4", "A4"])]
    A = ("0:F#5 4:A5 8:F#5 12:E5|0:E5 4:A5! 8:C#6 12:A5|0:D6 4:B5 8:F#5 12:B5|0:B5 4:G5 8:D5 12:G5")
    B = ("0:A5! 6:F#5 8:D5 12:F#5|0:E5 4:G5 8:A5! 12:E5|0:F#5 4:A5 8:B5! 12:A5|0:G5 4:F#5 8:E5 12:C#5"
         "|0:D6! 6:B5 8:A5 12:F#5|0:E5 4:F#5 8:A5 12:D6|0:B5 4:D6! 8:B5 12:G5|0:A5 8:C#6 12:E6!")
    plan = [(0, 4, prog), (4, 8, prog), (8, 16, prog2), (16, 24, prog2), (24, 28, prog), (28, 32, prog)]
    bar = 0
    for a, b, pr in plan:
        for k in range(a, b):
            root, tones = pr[(k - a) % len(pr)]
            # арпеджио арфой восьмыми
            pat = [0, 1, 2, 3, 2, 1, 2, 1]
            for i, st in enumerate(range(0, 16, 2)):
                s.add(k * 16 + st, ["harp"], tones[pat[i]], 1 if i % 2 else 2, 7)
            s.add(k * 16, ["bass"], root, 2, 3)
            if k >= 8:
                s.add(k * 16 + 8, ["bass"], root, 1, 3)
            if k >= 8 and k < 28:
                s.drum(k * 16, "basedrum", 1, 4)
                s.drum(k * 16 + 8, "basedrum", 1, 3)
                for st in (4, 12):
                    s.drum(k * 16 + st, "hat", 1)
    s.melody(4, A, ["bell", "flute"], 2)
    s.melody(8, B, ["flute", "bell"], 2)
    s.melody(16, B, ["bell", "flute"], 3)
    s.melody(24, A, ["bell", "flute"], 2)
    # звёзды: редкие высокие искры
    for k in range(8, 28):
        for st in (5, 13):
            if (k * 7 + st) % 5 == 0:
                s.add(k * 16 + st, ["chime"], prog[k % 4][1][3], 1, 6)
    s.add(31 * 16, ["bell"], "D6", 3, 1)
    s.add(31 * 16 + 8, ["bell"], "A5", 2, 1)
    save(s, "block-sunrise")


# ---------------------------------------------------------------- 3. Redstone Rave (рейв, ми минор)
def redstone_rave():
    s = Song("Redstone Rave", 150, "E minor")
    prog = [("E2", ["E4", "G4", "B4", "E5"]), ("C2", ["C4", "E4", "G4", "C5"]), ("G2", ["G3", "B3", "D4", "G4"]), ("D2", ["D4", "F#4", "A4", "D5"])]
    hook = ("0:B5! 2:B5 3:E6 6:D6 8:B5! 10:G5 12:A5 14:B5|0:C6! 2:C6 3:G5 6:E5 8:G5 10:C6 12:B5|"
            "0:D6! 2:D6 3:B5 6:G5 8:B5 10:D6 12:E6!|0:F#6 2:E6 3:D6 4:A5 8:D6 10:A5 12:F#5 14:A5")
    # (с такта, по такт): intro, build, drop, break, drop 2, outro
    drop1 = (16, 32)
    drop2 = (40, 56)

    def in_drop(k):
        return drop1[0] <= k < drop1[1] or drop2[0] <= k < drop2[1]
    total = 60
    for k in range(total):
        root, tones = prog[k % 4]
        b = k * 16
        arp_on = k < 56
        if arp_on:
            pat = [0, 1, 2, 1] * 4 if k % 2 == 0 else [0, 2, 1, 2, 3, 2, 1, 2] * 2
            for st in range(16):
                s.add(b + st, ["bit", "pling"], tones[pat[st]], 1 if k < 8 or 32 <= k < 40 else (2 if st % 4 == 0 else 1), 7)
        if in_drop(k):
            for st in (0, 4, 8, 12):
                s.drum(b + st, "basedrum", 3)
            for st in (4, 12):
                s.drum(b + st, "snare", 3 if st == 12 else 2)
            for st in range(16):
                if st % 2 == 0:
                    s.drum(b + st, "hat", 2 if st % 4 == 2 else 1)
            for st in (2, 6, 10, 14):
                s.add(b + st, ["bass", "didgeridoo"], root, 3, 3)
            if k % 4 == 3:
                for st in (13, 14, 15):
                    s.drum(b + st, "snare", 3)
        elif 8 <= k < 16:
            # нарастание: бочка и снейр всё чаще, подъём высоты
            density = [4, 4, 4, 4, 2, 2, 1, 1][k - 8]
            for st in range(0, 16, density):
                s.drum(b + st, "snare", 1 + (k - 8) // 3, 12 + (k - 8) * 1)
            for st in (0, 4, 8, 12):
                s.drum(b + st, "basedrum", 2)
            s.add(b, ["chime", "bell"], "E6" if k % 2 == 0 else "B6", 2, 6)
        elif k >= 56:
            s.drum(b, "basedrum", 2)
            s.add(b, ["bass"], root, 2, 3)
        elif 32 <= k < 40:
            # брейк: мягкие аккорды и хэт
            for st in (0, 8):
                s.add(b + st, ["harp"], tones[:3], 2, 8)
            for st in (4, 12):
                s.drum(b + st, "hat", 1)
        else:
            for st in range(0, 16, 4):
                s.drum(b + st, "hat", 1)
    for start in (16, 24, 40, 48):
        s.melody(start, hook, ["flute", "bell"], 2)
        s.melody(start + 4, hook, ["flute", "bell"], 3)
    # брейк: протяжная мелодия колокольчиками
    br = ("0:B5 8:E6|0:C6 8:G5|0:D6 8:B5|0:A5 4:D6 8:F#6!")
    s.melody(32, br, ["bell", "flute"], 2)
    s.melody(36, br, ["bell", "flute"], 3)
    s.add(59 * 16, ["bell"], "E6", 3, 1)
    save(s, "redstone-rave")


# ---------------------------------------------------------------- 4. Nether Lullaby (колыбельная, фа-диез минор)
def nether_lullaby():
    s = Song("Nether Lullaby", 68, "F# minor")
    prog = [("F#1", ["F#3", "A3", "C#4", "F#4"]), ("D2", ["D3", "F#3", "A3", "D4"]), ("A1", ["A3", "C#4", "E4", "A4"]), ("E2", ["E3", "G#3", "B3", "E4"])]
    theme = ("0:C#6 6:F#6! 10:E6 12:C#6|0:A5 4:D6 8:F#6 12:E6|0:E6 4:C#6 8:A5! 12:C#6|0:B5 6:G#5 8:E5! 12:B5")
    answer = ("0:F#6! 4:A6 8:F#6 12:E6|0:D6 4:F#6 8:A5 12:D6|0:C#6 4:E6! 8:C#6 12:A5|0:G#5 4:B5 8:E6! 12:B5")
    total = 40
    for k in range(total):
        root, tones = prog[k % 4]
        b = k * 16
        s.add(b, ["didgeridoo", "bass"], root, 2, 3)
        # гитара тихо перебором
        order = [0, 2, 1, 3, 2, 1]
        for i, st in enumerate((0, 3, 6, 8, 11, 14)):
            s.add(b + st, ["guitar", "harp"], tones[order[i]], 1 if i else 2, 7)
        if k >= 8:
            s.drum(b, "basedrum", 2, 3)
            s.drum(b + 6, "basedrum", 1, 2)
        if 16 <= k < 32:
            s.drum(b + 8, "hat", 1)
            s.drum(b + 12, "hat", 1)
    s.melody(4, theme, ["bell", "flute"], 2)
    s.melody(8, theme, ["bell", "flute"], 2)
    s.melody(16, answer, ["bell", "flute"], 3)
    s.melody(20, theme, ["flute", "bell"], 2)
    s.melody(24, answer, ["bell", "flute"], 3)
    s.melody(28, theme, ["bell", "flute"], 2)
    # огоньки Незера: тихие искры по пентатонике
    spark = ["F#6", "A6", "C#7", "E6", "B6"]
    for k in range(6, 36):
        for st in (1, 5, 9, 13):
            if (k * 5 + st * 3) % 7 == 0:
                s.add(k * 16 + st, ["chime", "bell"], spark[(k + st) % 5], 1, 6)
    s.add(39 * 16, ["bell"], "F#6", 3, 1)
    s.add(39 * 16 + 8, ["bell"], "C#6", 2, 1)
    save(s, "nether-lullaby")


# ---------------------------------------------------------------- 5. Pixel Parade (марш, до мажор)
def pixel_parade():
    s = Song("Pixel Parade", 132, "C major")
    prog = [("C3", ["C4", "E4", "G4"]), ("F2", ["F3", "A3", "C4"]), ("G2", ["G3", "B3", "D4"]), ("C3", ["C4", "E4", "G4"]),
            ("A2", ["A3", "C4", "E4"]), ("F2", ["F3", "A3", "C4"]), ("G2", ["G3", "B3", "D4"]), ("G2", ["G3", "B3", "D4"])]
    tune = ("0:E5 2:G5 4:C6! 8:G5 10:E5 12:G5|0:F5 2:A5 4:C6 8:A5 10:F5 12:A5|0:G5 2:B5 4:D6! 8:B5 10:G5 12:D5|0:E5 2:G5 4:C6! 8:E6 12:C6"
            "|0:C6 2:E6 4:A5! 8:C6 10:E6 12:A5|0:A5 2:C6 4:F6! 8:C6 10:A5 12:F5|0:B5 2:D6 4:G5! 8:D6 10:B5 12:G5|0:G5 4:B5 8:D6! 12:G6")
    total = 48
    for k in range(total):
        root, tones = prog[k % 8]
        b = k * 16
        # ум-па: бас на 1 и 3 долю, аккорд на 2 и 4
        for st in (0, 8):
            s.add(b + st, ["bass"], root, 3 if st == 0 else 2, 3)
        for st in (4, 12):
            s.add(b + st, ["pling", "banjo"], tones, 1, 8)
        if k >= 4:
            for st in (0, 8):
                s.drum(b + st, "basedrum", 2)
            for st in (4, 12):
                s.drum(b + st, "snare", 2)
            for st in (2, 6, 10, 14):
                s.drum(b + st, "hat", 1)
        if k % 8 == 7 and k >= 8:
            for st in (12, 13, 14, 15):
                s.drum(b + st, "snare", 2)
    for start in (8, 16, 24, 32, 40):
        s.melody(start, tune, ["bit", "harp"], 2)
    for start in (16, 32):
        # вторая рука колокольчиком на октаву выше
        for i, bar in enumerate(tune.split("|")):
            for tok in bar.split():
                st, note = tok.split(":")
                n = note.rstrip("!")
                if int(st) % 4 == 0:
                    s.add((start + i) * 16 + int(st) + 2, ["bell", "chime"], n[:-1] + str(int(n[-1]) + 1), 1, 6)
    s.add(47 * 16 + 8, ["bit"], "C6", 3, 1)
    s.add(47 * 16 + 12, ["bell"], "C7", 3, 1)
    save(s, "pixel-parade")


if __name__ == "__main__":
    neon_drive()
    block_sunrise()
    redstone_rave()
    nether_lullaby()
    pixel_parade()
