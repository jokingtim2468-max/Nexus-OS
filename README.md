# MacShell for Windows

Turns Windows into a Mac: a port of the look and feel of
[MacShell](https://github.com/0-ss/MacShell) (MIT, © 2026 Rickky), the macOS
Tahoe-style Hyprland shell, rebuilt in **Python + PyQt6** for Windows.
`vendor/MacShell` (git submodule) is the visual reference — palette, radii and
layout come from its QML.

## Install & run (Windows 10 1803+ / 11)

    cd macshell-win
    pip install -r requirements.txt
    python main.py

`python main.py` opens the **launcher**. From Settings → Startup & Takeover →
*Desktop shortcut → Create* you get a desktop shortcut that opens it too.

## How it starts

| | What happens |
|---|---|
| **Launcher** (shortcut / `main.py`) | Card with the auto-start toggle and **Launch**. Launch dips down, bounces up, slides right, expands over the whole desktop, then the shell takes over. |
| **Auto-start ON** | Registered in `HKCU\…\Run`. At sign-in MacShell starts straight away (`--autostart`) and **takes over**: hides the Windows taskbar, closes Wallpaper Engine, sets your MacShell wallpaper. |
| **Auto-start OFF** | Nothing runs at sign-in and nothing is overridden until you press **Launch**. |
| **Quit** | FF menu → *Quit MacShell* (or Settings → *Quit and Restore Windows*) brings back the taskbar, your old wallpaper and Wallpaper Engine. |
| **Emergency** | `python main.py --restore` shows the taskbar again if anything goes wrong. |

## First launch

A dimmed walkthrough spotlights the menu bar, the Mullvad/Tor status and
Control Center, the dock and Settings. Arrow keys / Enter / Esc work. Re-open it
from the FF menu → *Show Tutorial*.

## Settings (everything is here)

Laid out like macOS System Settings; saved to
`%APPDATA%\MacShellWin\settings.json`; **Apply** rebuilds the shell live.

- **General** – reduce motion, replay the tour
- **Appearance** – light/dark, accent color, glass opacity
- **Wallpaper** – pick an image (restored on quit)
- **Dock** – icon size, magnification, add/remove/browse apps (programs, `.bat`, URLs)
- **Menu Bar** – 24-hour clock, seconds, number of workspaces, Mullvad/Tor status
- **Control Center** – show/hide volume and brightness
- **Startup & Takeover** – auto-start, replace taskbar, close Wallpaper Engine, desktop shortcut, restore Windows
- **Network & Privacy** – the commands the Mullvad and Tor switches run (`{connect}`, `{state}`)

## Files (`macshell-win/`)

| File | Role |
|------|------|
| `main.py` | Entry: launcher, `--autostart`, `--restore` |
| `launcher.py` | Launcher card + launch animation |
| `shell.py` | Builds/rebuilds bar, dock, Control Center; owns takeover |
| `tutorial.py` | First-launch walkthrough |
| `settings_app.py` | Settings window |
| `settings_store.py` | Load/save settings |
| `override.py` | Hide/restore taskbar, Wallpaper Engine, wallpaper |
| `autostart.py` | Run-key auto-start, desktop shortcut |
| `topbar.py`, `dock.py`, `control_center.py` | The shell surfaces |
| `glass.py`, `blur.py`, `theme.py` | Acrylic glass, MacShell palette, toggle switches |
| `config.py` | First-launch defaults |

## Status / known limits

- Built and run on Linux offscreen (every screen + the launch → tour → Settings →
  Apply flow runs without errors); **not yet run on real Windows**, where the
  Acrylic blur, taskbar hiding and Run key actually apply.
- Volume/brightness sliders are UI only (not wired to Windows audio/display yet).
- Workspaces are visual only (not tied to Windows virtual desktops yet).
- Hiding the taskbar doesn't free its screen space; maximized windows still stop
  where the taskbar was.
- Acrylic is a blur, not MacShell's real-time refraction shader.

## History

Earlier Linux/VM-hub work (FreeForm loader, vmhub, vault, netguard) was removed
from the tree but remains in this branch's git history.
