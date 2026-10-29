"""`macshell-helper theme apply NAME` — push a FreeForm theme preset to apps outside the shell.

  theme apply black|white|graphite|default
  theme apply-custom JSON      a Theme Studio theme: {"id","mode","bg","side","card","fg","sub","accent"}
  theme list

What it changes:
  * Windows: "Choose your mode" for apps and the system (HKCU Personalize AppsUseLightTheme /
    SystemUsesLightTheme), so Explorer, Settings, Store apps and most programs follow.
  * Linux: the GNOME/GTK colour-scheme preference (gsettings), which GTK/libadwaita apps follow.
  * Spotify: only when Spicetify (open source, https://spicetify.app) is installed — writes a
    "FreeForm" theme with one colour scheme per preset and runs `spicetify apply`.
    Spotify itself has no theming; without Spicetify it is left alone.
  * Discord: only when a client mod is installed — Vencord, Vesktop or BetterDiscord: writes a
    "FreeForm" theme (CSS colour variables) into its themes folder and turns it on.
  * Windows accent colour (Start, title bars, links): the theme's accent.
"""
import json
import os
import shutil
import subprocess
import sys

# background, surfaces, text, subtle text, accent — shared with Settings > Appearance
PRESETS = {
    "black":    {"dark": True,  "bg": "000000", "main": "0A0A0A", "card": "1A1A1A", "text": "FFFFFF", "subtext": "A1A1A6", "accent": "D1D1D6"},
    "white":    {"dark": False, "bg": "FFFFFF", "main": "F5F5F7", "card": "E5E5EA", "text": "000000", "subtext": "6E6E73", "accent": "636366"},
    "graphite": {"dark": True,  "bg": "2C2C2E", "main": "3A3A3C", "card": "48484A", "text": "F2F2F7", "subtext": "AEAEB2", "accent": "8E8E93"},
    "default":  {"dark": True,  "bg": "1E1E1E", "main": "121212", "card": "2A2A2C", "text": "F5F5F7", "subtext": "A1A1A6", "accent": "0A84FF"},
}


def from_studio(t):
    """A Theme Studio theme in the preset shape (hex without #)."""
    h = lambda k, d: str(t.get(k) or d).lstrip("#").upper()
    return {"dark": t.get("mode", "dark") != "light", "bg": h("side", "000000"), "main": h("bg", "121212"),
            "card": h("card", "1F1F1F"), "text": h("fg", "FFFFFF"), "subtext": h("sub", "A7A7A7"), "accent": h("accent", "1DB954")}


def spicetify_color_ini(extra=None):
    """Spicetify colour schemes: one [section] per preset (plus a custom one)."""
    out = []
    for name, p in list(PRESETS.items()) + list((extra or {}).items()):
        out += ["[%s]" % name,
                "text               = %s" % p["text"],
                "subtext            = %s" % p["subtext"],
                "main               = %s" % p["main"],
                "sidebar            = %s" % p["bg"],
                "player             = %s" % p["bg"],
                "card               = %s" % p["card"],
                "shadow             = 000000",
                "selected-row       = %s" % p["text"],
                "button             = %s" % p["accent"],
                "button-active      = %s" % p["accent"],
                "button-disabled    = %s" % p["subtext"],
                "tab-active         = %s" % p["card"],
                "notification       = %s" % p["accent"],
                "notification-error = FF453A",
                "misc               = %s" % p["subtext"], ""]
    return "\n".join(out)


def spicetify_dir():
    if os.name == "nt":
        return os.path.join(os.environ.get("APPDATA", ""), "spicetify")
    return os.path.expanduser("~/.config/spicetify")


def apply_spotify(name, extra=None):
    exe = shutil.which("spicetify")
    if not exe:
        return "Spotify: Spicetify isn't installed, left unchanged."
    d = os.path.join(spicetify_dir(), "Themes", "FreeForm")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "color.ini"), "w", encoding="utf-8") as fh:
        fh.write(spicetify_color_ini(extra))
    if not os.path.exists(os.path.join(d, "user.css")):
        open(os.path.join(d, "user.css"), "w").close()
    for args in (["config", "current_theme", "FreeForm", "color_scheme", name], ["apply", "-n"]):
        r = subprocess.run([exe, *args], capture_output=True, text=True)
        if r.returncode != 0:
            return "Spotify: spicetify %s failed: %s" % (args[0], (r.stderr or r.stdout).strip()[-200:])
    return "Spotify: themed (%s)." % name


DISCORD_CSS = """/**
 * @name FreeForm
 * @description Follows your FreeForm theme (made by FreeForm; rewritten when you apply a theme)
 * @author FreeForm
 * @version 1.0
 */
:root, .theme-dark, .theme-light {
  --background-primary: #%(main)s; --background-secondary: #%(card)s; --background-secondary-alt: #%(card)s;
  --background-tertiary: #%(bg)s; --background-floating: #%(bg)s; --background-accent: #%(accent)s;
  --background-modifier-hover: #%(text)s14; --background-modifier-selected: #%(text)s24;
  --channeltextarea-background: #%(card)s; --modal-background: #%(main)s; --bg-base-primary: #%(main)s;
  --bg-base-secondary: #%(card)s; --bg-base-tertiary: #%(bg)s; --bg-surface-raised: #%(card)s;
  --text-normal: #%(text)s; --text-default: #%(text)s; --header-primary: #%(text)s; --header-secondary: #%(subtext)s;
  --text-muted: #%(subtext)s; --interactive-normal: #%(subtext)s; --interactive-hover: #%(text)s;
  --interactive-active: #%(text)s; --channels-default: #%(subtext)s; --brand-500: #%(accent)s;
  --brand-experiment: #%(accent)s; --text-link: #%(accent)s; --button-filled-brand-background: #%(accent)s;
}
"""


def apply_discord(p):
    """Vencord / Vesktop / BetterDiscord: write FreeForm.theme.css and enable it."""
    appdata = os.environ.get("APPDATA") or os.path.expanduser("~/.config")
    css = DISCORD_CSS % p
    done = []
    # Vencord and Vesktop: themes/<file>.css, enabled in settings/settings.json "enabledThemes"
    for client, base in (("Vencord", os.path.join(appdata, "Vencord")), ("Vesktop", os.path.join(appdata, "vesktop"))):
        if not os.path.isdir(base):
            continue
        os.makedirs(os.path.join(base, "themes"), exist_ok=True)
        with open(os.path.join(base, "themes", "FreeForm.theme.css"), "w", encoding="utf-8") as fh:
            fh.write(css)
        sp = os.path.join(base, "settings", "settings.json")
        try:
            with open(sp, encoding="utf-8") as fh:
                cfg = json.load(fh)
            on = cfg.get("enabledThemes") or []
            if "FreeForm.theme.css" not in on:
                cfg["enabledThemes"] = on + ["FreeForm.theme.css"]
                with open(sp, "w", encoding="utf-8") as fh:
                    json.dump(cfg, fh, indent=4)
        except (OSError, ValueError):
            pass                                                        # first run: the user enables it once in Themes
        done.append(client)
    # BetterDiscord: themes/<file>.theme.css, enabled in data/stable/themes.json
    bd = os.path.join(appdata, "BetterDiscord")
    if os.path.isdir(bd):
        os.makedirs(os.path.join(bd, "themes"), exist_ok=True)
        with open(os.path.join(bd, "themes", "FreeForm.theme.css"), "w", encoding="utf-8") as fh:
            fh.write(css)
        tp = os.path.join(bd, "data", "stable", "themes.json")
        try:
            with open(tp, encoding="utf-8") as fh:
                cfg = json.load(fh)
        except (OSError, ValueError):
            cfg = {}
        cfg["FreeForm"] = True
        try:
            os.makedirs(os.path.dirname(tp), exist_ok=True)
            with open(tp, "w", encoding="utf-8") as fh:
                json.dump(cfg, fh, indent=4)
        except OSError:
            pass
        done.append("BetterDiscord")
    return "Discord: themed (%s)." % ", ".join(done) if done else "Discord: no client mod (Vencord, Vesktop, BetterDiscord) found, left unchanged."


def apply_accent(p):
    """Windows accent colour (Start, title bars, links) from the theme's accent."""
    if os.name != "nt":
        return "Accent: unchanged."
    import winreg
    h = p["accent"]
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    abgr = 0xFF000000 | (b << 16) | (g << 8) | r                          # Windows stores 0xAABBGGRR
    argb = 0xFF000000 | (r << 16) | (g << 8) | b
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\DWM") as k:
        winreg.SetValueEx(k, "AccentColor", 0, winreg.REG_DWORD, abgr)
        winreg.SetValueEx(k, "ColorizationColor", 0, winreg.REG_DWORD, argb)
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent") as k:
        winreg.SetValueEx(k, "AccentColorMenu", 0, winreg.REG_DWORD, abgr)
        winreg.SetValueEx(k, "StartColorMenu", 0, winreg.REG_DWORD, abgr)
    return "Windows accent: #%s." % h


def apply_system(p):
    if os.name == "nt":
        import winreg
        light = 0 if p["dark"] else 1
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER,
                              r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize") as k:
            winreg.SetValueEx(k, "AppsUseLightTheme", 0, winreg.REG_DWORD, light)
            winreg.SetValueEx(k, "SystemUsesLightTheme", 0, winreg.REG_DWORD, light)
        return "Windows apps: %s mode." % ("dark" if p["dark"] else "light")
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
                        "prefer-dark" if p["dark"] else "prefer-light"], capture_output=True)
        return "GTK apps: %s." % ("dark" if p["dark"] else "light")
    return "System apps: unchanged."


def main(argv):
    a = argv + ["", ""]
    if a[0] == "list":
        for n, p in PRESETS.items():
            print("%s\t%s\t#%s\t#%s" % (n, "dark" if p["dark"] else "light", p["bg"], p["accent"]))
        return 0
    if a[0] == "apply-custom" and a[1]:
        import json
        t = json.loads(a[1])
        name = "".join(ch for ch in str(t.get("id", "custom")) if ch.isalnum() or ch in "-_") or "custom"
        p = from_studio(t)
        print(apply_system(p))
        print(apply_spotify(name, {name: p}))
        print(apply_discord(p))
        print(apply_accent(p))
        return 0
    if a[0] == "apply" and a[1] in PRESETS:
        print(apply_system(PRESETS[a[1]]))
        print(apply_spotify(a[1]))
        print(apply_discord(PRESETS[a[1]]))
        print(apply_accent(PRESETS[a[1]]))
        return 0
    print("usage: theme list | theme apply %s" % "|".join(PRESETS), file=sys.stderr)
    return 64
