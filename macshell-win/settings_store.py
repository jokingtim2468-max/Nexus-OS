"""Persistent settings: %APPDATA%\\MacShellWin\\settings.json."""
import copy
import json
import os

import config

DIR = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~/.config"),
                   "MacShellWin")
PATH = os.path.join(DIR, "settings.json")

DEFAULTS = {
    # first launch
    "first_run": True,
    # startup & takeover
    "autostart": False,
    "override_taskbar": True,
    "override_wallpaper_engine": True,
    # appearance
    "theme": "dark",
    "accent": "#0A84FF",
    "glass_alpha": 153,
    "reduce_motion": False,
    "wallpaper": "",
    # dock
    "dock_size": 52,
    "dock_magnification": 1.45,
    "dock_apps": config.DOCK_APPS,
    # menu bar
    "clock_24h": False,
    "clock_seconds": False,
    "workspaces": config.WORKSPACES,
    "show_net_status": True,
    # control center
    "cc_volume": True,
    "cc_brightness": True,
    # network hooks
    "hooks": config.HOOKS,
}


def load():
    s = copy.deepcopy(DEFAULTS)
    try:
        with open(PATH, encoding="utf-8") as fh:
            s.update(json.load(fh))
    except (OSError, ValueError):
        pass
    return s


def save(s):
    os.makedirs(DIR, exist_ok=True)
    tmp = PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(s, fh, indent=2)
    os.replace(tmp, PATH)
