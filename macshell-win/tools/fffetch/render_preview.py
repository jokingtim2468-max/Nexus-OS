"""Render what `fetch` looks like in a terminal: a PNG of one frame and a looping GIF of the
FFs falling behind the text (same motion as fetch-core.ps1). Used for previews/docs, not by fetch itself.

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
                elif c == 48 and i + 2 < len(codes) and codes[i + 1] == 5:
                    bg = xterm256(codes[i + 2]); i += 2
                elif c == 22:
                    bold = False
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


def snow(rows, width, seed=7, frames=90):
    """fetch-core.ps1's falling FFs: they fall nonstop over the card, recycled at the top."""
    rnd = random.Random(seed)
    palette = [255, 253, 250, 247, 244]
    nrow = len(rows)
    glyphs = ["FF"] * 4

    def new():
        return dict(x=float(rnd.randint(1, width - 4)), y=-float(rnd.randint(0, nrow)), vx=(rnd.random() - 0.5) * 0.3,
                    vy=rnd.random() * 0.2, spin=rnd.randint(0, 3), c=xterm256(rnd.choice(palette)))
    ps = [new() for _ in range(14)]
    out = []
    for f in range(frames):
        for i, p in enumerate(ps):
            p["vy"] = min(p["vy"] + 0.04, 0.6); p["y"] += p["vy"]; p["x"] += p["vx"]
            if p["x"] < 0 or p["x"] > width - 3:
                p["vx"] = -p["vx"]; p["x"] = max(0, min(p["x"], width - 3))
            if p["y"] >= nrow:
                ps[i] = new(); ps[i]["y"] = -1
        out.append([(int(round(p["x"])), int(math.floor(p["y"])), glyphs[(p["spin"] + f // 4) % 4], p["c"]) for p in ps if p["y"] >= 0])
    return out


def solid(cell):
    ch, fg, bg, b = cell
    return ch != " " or (bg is not None and bg != xterm256(237))


def draw(rows, falling, width, nrows):
    font, bold = ImageFont.truetype(FONT, SIZE), ImageFont.truetype(BOLD, SIZE)
    cw = font.getbbox("M")[2]
    ch = int(SIZE * 1.3)
    pad, bar = 18, 34
    im = Image.new("RGB", (pad * 2 + cw * width, bar + pad * 2 + ch * nrows), BG)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, im.width, bar), fill=(32, 32, 32))
    d.rounded_rectangle((8, 5, 210, bar), radius=6, fill=(12, 12, 12))
    d.text((20, 10), "Windows PowerShell", font=ImageFont.truetype(FONT, 13), fill=(220, 220, 220))
    for i, sym in enumerate(["\u2014", "\u25a1", "\u2715"]):
        d.text((im.width - 120 + i * 40, 9), sym, font=ImageFont.truetype(FONT, 13), fill=(200, 200, 200))
    y0 = bar + pad
    prompt = [(c, (204, 204, 204), None, False) for c in "PS C:\\Users\\you> "] + [(c, (249, 241, 165), None, False) for c in "fetch"]
    hint = [(c, xterm256(244), None, False) for c in "press any key to stop the FFs"]
    allrows = [prompt] + rows + [hint]
    for r, cells in enumerate(allrows):
        for c, (txt, fg, bg, b) in enumerate(cells):
            x, y = pad + c * cw, y0 + r * ch
            if bg:
                d.rectangle((x, y, x + cw, y + ch), fill=bg)
            if txt == "\u2588":
                d.rectangle((x, y, x + cw - 1, y + ch - 1), fill=fg)
            elif txt != " ":
                d.text((x, y), txt, font=bold if b else font, fill=fg)
    cardw = max(len(r) for r in rows)
    for (x, y, g, col) in falling:        # behind the text, above the card
        for k, gch in enumerate(g):
            cx = x + k
            if y >= len(rows) or cx >= cardw or cx >= len(rows[y]) or solid(rows[y][cx]):
                continue
            d.text((pad + cx * cw, y0 + (y + 1) * ch), gch, font=bold, fill=col)
    return im


def main(src, png, gif):
    rows = parse(open(src, encoding="utf-8", errors="replace").read())
    width = max(70, max(len(r) for r in rows) + 6)
    nrows = len(rows) + 3
    frames = snow(rows, max(len(r) for r in rows))
    draw(rows, frames[40], width, nrows).save(png)
    pics = [draw(rows, f, width, nrows) for f in frames]
    pics[0].save(gif, save_all=True, append_images=pics[1:], duration=40, loop=0)


if __name__ == "__main__":
    main(*sys.argv[1:4])
