# MacShell for Windows

A Windows port of the look and feel of [MacShell](https://github.com/0-ss/MacShell)
(MIT, © 2026 Rickky), the macOS Tahoe-style Hyprland shell.

MacShell itself is Quickshell/QML + GLSL for Hyprland/Wayland and cannot run on
Windows. This project rebuilds it in **Python + PyQt6**, using the original
(`vendor/MacShell`, git submodule) as the visual reference — palette, radii and
layout come from its QML.

## Run (Windows 10 1803+ / 11)

    cd macshell-win
    pip install -r requirements.txt
    python main.py

## Layout

| File | What it does |
|------|--------------|
| `main.py` | Starts bar, dock, Control Center; wires toggles to your scripts |
| `glass.py` | Base frameless, always-on-top glass window |
| `blur.py` | Native Acrylic blur (`SetWindowCompositionAttribute`), Win11 rounded corners, hide from taskbar |
| `topbar.py` | Menu bar: workspaces, clock, Mullvad/Tor status, Control Center button |
| `dock.py` | Floating dock with hover magnification; launches `.exe`/`.bat`/URIs |
| `control_center.py` | Volume/brightness sliders, Mullvad (locked by kill switch) and Tor toggles |
| `theme.py` | MacShell palette (slab `#2B2B2D`, green `#30D158`, …) |
| `config.py` | **Edit this:** dock app paths and the commands your VPN/Tor toggles run |

## Status / limits

- First scaffold; untested on Windows yet (built and syntax-checked on Linux).
- Volume/brightness sliders are UI only — not wired to Windows audio/display yet.
- Acrylic is a blur, not MacShell's true refraction shader.
- The top bar overlays the screen; it does not yet reserve space (AppBar) or
  replace Explorer's taskbar.

## History

Earlier Linux/VM-hub work (FreeForm loader, vmhub, vault, netguard) was removed
from the tree but remains in this branch's git history.
