"""Render what `fetch` looks like in a terminal: a PNG of the final screen and a GIF of the
falling-FF intro (same physics as fetch-core.ps1). Used for previews/docs, not by fetch itself.

    python render_preview.py captured-output.txt out.png out.gif

captured-output.txt is fetch's real output (ANSI colours included), e.g. from the Windows CI run.
"""
import math
import random
import re
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
SIZE = 17
BG = (12, 12, 12)
FG = (204, 204, 204)


def xterm256(n):
    base = [(12, 12, 12), (197, 15, 31), (19, 161, 14), (193, 156, 0), (0, 55, 218), (136, 23, 152), (58, 150, 221), (204, 204, 204),
            (118, 118, 118), (231, 72, 86), (22, 198, 12), (249, 241, 165), (59, 120, 255), (180, 0, 158), (97, 214, 214), (242, 242, 242)]
    if n < 16:
        return base[n]
    if n < 232:
        n -= 16
        lv = [0, 95, 135, 175, 215, 255]
        return (lv[n // 36], lv[(n // 6) % 6], lv[n % 6])
    g = 8 + (n - 232) * 10
    return (g, g, g)


def parse(text):
    """-> rows of [(char, fg, bg, bold)] (Windows Terminal "Campbell" colours)."""
    rows = []
    for line in text.replace("\r", "").split("\n"):
        cells, fg, bg, bold = [], FG, None, False
        for tok in re.split(r"(\x1b\[[0-9;]*m)", line):
            m = re.fullmatch(r"\x1b\[([0-9;]*)m", tok)
            if not m:
                cells += [(ch, fg, bg, bold) for ch in tok]
                continue
            codes = [int(c) for c in m.group(1).split(";") if c] or [0]
            i = 0
            while i < len(codes):
                c = codes[i]
                if c == 0:
                    fg, bg, bold = FG, None, False
                elif c == 1:
                    bold = True
                elif c == 38 and i + 2 < len(codes) and codes[i + 1] == 5:
                    fg = xterm256(codes[i + 2]); i += 2
                elif 40 <= c <= 47:
                    bg = xterm256(c - 40)
                elif 100 <= c <= 107:
                    bg = xterm256(c - 100 + 8)
                elif 30 <= c <= 37:
                    fg = xterm256(c - 30)
                i += 1
        rows.append(cells)
    while rows and not rows[-1]:
        rows.pop()
    return rows


def simulate(width, rows, seed=7, frames=70):
    """fetch-core.ps1's falling FFs: gravity, wall bounce, up to two floor bounces, piling."""
    rnd = random.Random(seed)
    palette = [39, 45, 69, 75, 99, 135, 141]
    floor = {}
    ps = [dict(x=float(rnd.randint(1, width - 3)), y=-float(rnd.randint(0, 13)), vx=(rnd.random() - 0.5) * 0.9, vy=0.0,
               spin=rnd.randint(0, 3), c=xterm256(rnd.choice(palette)), done=False, b=0) for _ in range(22)]
    out = []
    for f in range(frames):
        for p in ps:
            if p["done"]:
                continue
            p["vy"] += 0.16; p["y"] += p["vy"]; p["x"] += p["vx"]
            if p["x"] < 0: p["x"], p["vx"] = 0, -p["vx"]
            if p["x"] > width - 2: p["x"], p["vx"] = width - 2, -p["vx"]
            col = int(round(p["x"]))
            ground = floor.get(col, rows - 1)
            if p["y"] >= ground:
                p["y"] = ground
                if p["b"] < 2 and abs(p["vy"]) > 0.5:
                    p["vy"] = -p["vy"] * 0.45; p["vx"] *= 0.6; p["b"] += 1
                else:
                    p["done"] = True
                    for dc in (-1, 0, 1, 2):
                        floor[col + dc] = ground - 1
        glyphs = ["FF", "\u2132\u2132", "FF", "\u2132F"]
        out.append([(int(round(p["x"])), int(math.floor(p["y"])), "FF" if p["done"] else glyphs[(p["spin"] + f) % 4], p["c"])
                    for p in ps if p["y"] >= 0])
        if all(p["done"] for p in ps):
            break
    return out


def draw(rows, falling, width, nrows, show_text=True):
    font, bold = ImageFont.truetype(FONT, SIZE), ImageFont.truetype(BOLD, SIZE)
    cw = font.getbbox("M")[2]
    ch = int(SIZE * 1.3)
    pad, bar = 18, 34
    im = Image.new("RGB", (pad * 2 + cw * width, bar + pad * 2 + ch * nrows), BG)
    d = ImageDraw.Draw(im)
    # Windows Terminal-ish title bar
    d.rectangle((0, 0, im.width, bar), fill=(32, 32, 32))
    d.rounded_rectangle((8, 5, 210, bar), radius=6, fill=(12, 12, 12))
    d.text((20, 10), "Windows PowerShell", font=ImageFont.truetype(FONT, 13), fill=(220, 220, 220))
    for i, sym in enumerate(["\u2014", "\u25a1", "\u2715"]):
        d.text((im.width - 120 + i * 40, 9), sym, font=ImageFont.truetype(FONT, 13), fill=(200, 200, 200))
    y0 = bar + pad
    textlen = {}
    if show_text:
        prompt = [(c, (204, 204, 204), None, False) for c in "PS C:\\Users\\you> "] + [(c, (249, 241, 165), None, False) for c in "fetch"]
        for r, cells in enumerate([prompt] + rows):
            textlen[r] = len(cells)
            for c, (txt, fg, bg, b) in enumerate(cells):
                x, y = pad + c * cw, y0 + r * ch
                if bg:
                    d.rectangle((x, y, x + cw, y + ch), fill=bg)
                if txt == "\u2588":                       # full block: fill the whole cell, like a terminal
                    d.rectangle((x, y, x + cw - 1, y + ch - 1), fill=fg)
                elif txt != " ":
                    d.text((x, y), txt, font=bold if b else font, fill=fg)
    for (x, y, g, col) in falling:
        r = y + 1                                   # the intro area starts under the prompt
        if show_text and x < textlen.get(r, 0):
            continue                                # behind the text
        d.text((pad + x * cw, y0 + r * ch), g, font=bold, fill=col)
    return im


def main(src, png, gif):
    rows = parse(open(src, encoding="utf-8", errors="replace").read())
    width = max(70, max(len(r) for r in rows) + 6)
    nrows = len(rows) + 3
    frames = simulate(width - 2, len(rows) + 2)
    draw(rows, frames[-1], width, nrows).save(png)
    pics = [draw(rows, f, width, nrows, show_text=False) for f in frames[::2]]
    pics.append(draw(rows, frames[-1], width, nrows))
    pics[0].save(gif, save_all=True, append_images=pics[1:], duration=[56] * (len(pics) - 1) + [2500], loop=0)


if __name__ == "__main__":
    main(*sys.argv[1:4])
