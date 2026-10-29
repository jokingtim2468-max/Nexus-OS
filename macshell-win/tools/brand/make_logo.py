"""FreeForm's logo: the two F's of "FF", each built from a grid of white dots.

    python3 tools/brand/make_logo.py          (from macshell-win/)

Writes macshell/assets/freeform-logo.png (app tile), macshell/assets/freeform.ico (shortcut icon)
and macshell/ff-logo-white.svg / ff-logo-black.svg (the menu bar mark). Small sizes use a coarser
grid so the dots still read.
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


DOT = 0.72         # dot diameter, as a share of the grid step


def cells(step):
    """Centres (in the 100 box) of the dots for a grid of `step` units. Each F gets the same grid,
    measured from its own left edge, so the two letters match dot for dot."""
    F = [(8, 10, 20, 90), (8, 10, 44, 26), (8, 38, 40, 53)]               # one F, at x = 8
    one = []
    y = 10 + step / 2
    while y < 90:
        x = 8 + step / 2
        while x < 44:
            if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in F): one.append((x, y))
            x += step
        y += step
    return one + [(x + 48, y) for x, y in one]


def tile(size, step, bg=(0, 0, 0, 255), fg=(255, 255, 255, 255), pad=0.16, radius=0.22):
    ss = 4                                                                  # supersample, then shrink: smooth edges
    S = size * ss
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius), fill=bg)
    k = S * (1 - 2 * pad) / 100; o = S * pad
    r = step * DOT / 2
    for cx, cy in cells(step):
        d.ellipse([o + (cx - r) * k, o + (cy - r) * k, o + (cx + r) * k, o + (cy + r) * k], fill=fg)
    return im.resize((size, size), Image.LANCZOS)


def svg(color, step=4.0):
    rects = "".join('<circle cx="%.2f" cy="%.2f" r="%.2f"/>' % (cx, cy, step * DOT / 2) for cx, cy in cells(step))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 100 100">\n'
            '  <!-- FreeForm "FF": each F is a grid of dots (tools/brand/make_logo.py) -->\n'
            '  <g fill="%s">%s</g>\n</svg>\n' % (color, rects))


if __name__ == "__main__":
    tile(1024, 5.0).save(os.path.join(SHELL, "assets", "freeform-logo.png"))
    # Windows picks the closest size; tiny sizes get a coarser grid
    sizes = [(256, 5.0), (128, 6.0), (64, 7.0), (48, 8.0), (32, 10.0), (24, 12.0), (16, 13.0)]
    imgs = [tile(s, st) for s, st in sizes]
    imgs[0].save(os.path.join(SHELL, "assets", "freeform.ico"), sizes=[(s, s) for s, _ in sizes], append_images=imgs[1:])
    for name, col in (("ff-logo-white.svg", "#ffffff"), ("ff-logo-black.svg", "#000000")):
        with open(os.path.join(SHELL, name), "w") as f:
            f.write(svg(col, 6.0))                                          # the menu bar mark is ~16 px: coarse grid
    print("logo written")
