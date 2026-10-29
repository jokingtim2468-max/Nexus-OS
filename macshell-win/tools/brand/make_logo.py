"""FreeForm's logo: the two F's of "FF", each built from a grid of tiny F's.

    python3 tools/brand/make_logo.py          (from macshell-win/)

Writes macshell/assets/freeform-logo.png (app tile), macshell/assets/freeform.ico (shortcut icon)
and macshell/ff-logo-white.svg / ff-logo-black.svg (the menu bar mark). Small sizes use a coarser
grid so the little F's still read.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.normpath(os.path.join(HERE, "..", "..", "macshell"))

# the big letters, in a 100x100 box: (x0, y0, x1, y1) bars of each F
BARS = []
for ox in (0, 48):
    BARS += [(8 + ox, 10, 20 + ox, 90), (8 + ox, 10, 44 + ox, 26), (8 + ox, 38, 40 + ox, 53)]


def inside(x, y):
    return any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in BARS)


def small_f(cx, cy, s):
    """The bars of one tiny F centred at (cx, cy), s = its height."""
    w = s * 0.62; t = s * 0.24; x0, y0 = cx - w / 2, cy - s / 2
    return [(x0, y0, x0 + t, y0 + s), (x0, y0, x0 + w, y0 + t), (x0, y0 + s * 0.42, x0 + w * 0.82, y0 + s * 0.42 + t)]


def cells(step):
    """Centres (in the 100 box) of the tiny F's for a grid of `step` units."""
    out = []
    y = 10 + step / 2
    while y < 90:
        x = 8 + step / 2
        while x < 92:
            if inside(x, y): out.append((x, y))
            x += step
        y += step
    return out


def mark_bars(step):
    return [b for cx, cy in cells(step) for b in small_f(cx, cy, step * 0.78)]


def tile(size, step, bg=(0, 0, 0, 255), fg=(255, 255, 255, 255), pad=0.16, radius=0.22):
    ss = 4                                                                  # supersample, then shrink: smooth edges
    S = size * ss
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius), fill=bg)
    k = S * (1 - 2 * pad) / 100; o = S * pad
    for x0, y0, x1, y1 in mark_bars(step):
        d.rectangle([o + x0 * k, o + y0 * k, o + x1 * k, o + y1 * k], fill=fg)
    return im.resize((size, size), Image.LANCZOS)


def svg(color, step=4.0):
    rects = "".join('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f"/>' % (x0, y0, x1 - x0, y1 - y0)
                    for x0, y0, x1, y1 in mark_bars(step))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 100 100">\n'
            '  <!-- FreeForm "FF": each F is a grid of tiny F\'s (tools/brand/make_logo.py) -->\n'
            '  <g fill="%s">%s</g>\n</svg>\n' % (color, rects))


if __name__ == "__main__":
    tile(1024, 4.0).save(os.path.join(SHELL, "assets", "freeform-logo.png"))
    # Windows picks the closest size; tiny sizes get a coarser grid
    sizes = [(256, 4.0), (128, 5.0), (64, 6.0), (48, 7.5), (32, 9.0), (24, 11.0), (16, 13.0)]
    imgs = [tile(s, st) for s, st in sizes]
    imgs[0].save(os.path.join(SHELL, "assets", "freeform.ico"), sizes=[(s, s) for s, _ in sizes], append_images=imgs[1:])
    for name, col in (("ff-logo-white.svg", "#ffffff"), ("ff-logo-black.svg", "#000000")):
        with open(os.path.join(SHELL, name), "w") as f:
            f.write(svg(col, 6.0))                                          # the menu bar mark is ~16 px: coarse grid
    print("logo written")
