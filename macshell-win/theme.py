"""MacShell (macOS Tahoe) palette, taken from vendor/MacShell/MacShell/*.qml.

Values are module globals so every component reads the current theme;
apply(settings) updates them before the UI is (re)built.
"""

SLAB_RGB = (0x2B, 0x2B, 0x2D)   # glass base (GlassSlab baseColor #2B2B2D)
GLASS_ALPHA = 153
TEXT = "#F5F5F7"
TEXT_DIM = "rgba(245,245,247,0.55)"
GLASS = "rgba(255,255,255,0.12)"
GLASS_HI = "rgba(255,255,255,0.20)"
BORDER = "rgba(255,255,255,0.14)"
ACCENT = "#0A84FF"
GREEN = "#30D158"
RED = "#FF453A"
PURPLE = "#BF5AF2"

BAR_HEIGHT = 30
DOCK_ICON = 52
MAG = 1.45
RADIUS_MENU = 14
RADIUS_DOCK = 22
FONT = "Segoe UI Variable, Segoe UI, Inter"
REDUCE_MOTION = False


def switch_qss():
    """macOS-style toggle switches for QCheckBox, drawn as SVGs in the current accent."""
    import os
    import settings_store
    d = os.path.join(settings_store.DIR, "ui")
    os.makedirs(d, exist_ok=True)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="38" height="22">'
           '<rect width="38" height="22" rx="11" fill="{fill}" fill-opacity="{op}"/>'
           '<circle cx="{cx}" cy="11" r="9" fill="#fff"/></svg>')
    files = {"off": svg.format(fill="#78787F", op=0.55, cx=11),
             "on": svg.format(fill=ACCENT, op=1, cx=27),
             "locked": svg.format(fill=GREEN, op=0.6, cx=27)}
    path = {}
    for name, body in files.items():
        p = os.path.join(d, f"switch-{name}.svg")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
        path[name] = p.replace("\\", "/")
    return (f"QCheckBox::indicator {{ width:38px; height:22px; image:url({path['off']}); }}"
            f"QCheckBox::indicator:checked {{ image:url({path['on']}); }}"
            f"QCheckBox::indicator:checked:disabled {{ image:url({path['locked']}); }}")


def apply(s):
    dark = s.get("theme", "dark") != "light"
    globals().update(
        SLAB_RGB=(0x2B, 0x2B, 0x2D) if dark else (0xF5, 0xF5, 0xF7),
        GLASS_ALPHA=int(s.get("glass_alpha", 153)),
        TEXT="#F5F5F7" if dark else "#1D1D1F",
        TEXT_DIM="rgba(245,245,247,0.55)" if dark else "rgba(29,29,31,0.55)",
        GLASS="rgba(255,255,255,0.12)" if dark else "rgba(255,255,255,0.55)",
        GLASS_HI="rgba(255,255,255,0.20)" if dark else "rgba(255,255,255,0.80)",
        BORDER="rgba(255,255,255,0.14)" if dark else "rgba(0,0,0,0.08)",
        ACCENT=s.get("accent", "#0A84FF"),
        DOCK_ICON=int(s.get("dock_size", 52)),
        MAG=float(s.get("dock_magnification", 1.45)),
        REDUCE_MOTION=bool(s.get("reduce_motion", False)),
    )
