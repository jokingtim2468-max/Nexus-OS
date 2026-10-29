"""`macshell-helper apps sync` — make Windows' Start Menu apps visible to MacShell.

MacShell (Dock, Spotlight, Launchpad, the menu bar's app name) finds apps through Quickshell's
DesktopEntries, i.e. freedesktop .desktop files. This writes one per Start Menu shortcut and
Microsoft Store app into ~/.local/share/applications (files named ff-*.desktop, refreshed each
sync), with the app's 256 px icon. StartupWMClass is the .exe name, the same id our Win32
ToplevelManager gives the app's windows, so the Dock shows a dot under running apps.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def desktop_dir():
    home = os.environ.get("XDG_DATA_HOME") or os.path.join(os.environ.get("HOME") or os.path.expanduser("~"), ".local", "share")
    return os.path.join(home, "applications")


# Windows apps whose names clash with FreeForm's own ("Settings" is FreeForm's)
RENAME = {"Settings": "Windows Settings"}


# The Mac-style icon theme FreeForm ships (icons/FreeForm-Mac, built from MacTahoe in CI): apps it
# has a tile for use that tile instead of their own Windows icon. Names it uses for Windows apps:
ALIASES = {"chrome": "google-chrome", "msedge": "microsoft-edge", "explorer": "system-file-manager",
           "file_explorer": "system-file-manager", "windowsterminal": "utilities-terminal", "terminal": "utilities-terminal",
           "wt": "utilities-terminal", "cmd": "utilities-terminal", "powershell": "utilities-terminal",
           "spotify": "spotify", "discord": "discord", "code": "visual-studio-code",
           "notepad": "notepad", "obs64": "obs", "telegram": "telegram"}


def themed_icons(root):
    d = os.path.join(root, "icons", "FreeForm-Mac", "apps", "scalable") if root else ""
    try:
        return {f[:-4] for f in os.listdir(d) if f.endswith(".svg")}
    except OSError:
        return set()


# apps that keep their own icon (the theme's version looks wrong next to the running app)
OWN_ICON = {"steam"}
# apps whose windows belong to a different .exe than the shortcut's (so the Dock's dot lands on the pinned icon)
WINDOW_EXE = {"steam": "steamwebhelper"}


def theme_icon(name, wm, themed):
    """The theme's icon name for this app, or "" when the theme has none."""
    if wm in OWN_ICON or name.lower() in OWN_ICON:
        return ""
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    for c in (ALIASES.get(wm), ALIASES.get(slug.replace("-", "_")), slug, wm):
        if c and c in themed:
            return c
    return ""


def entry(app, themed=frozenset()):
    """One .desktop file's text for an app from apps.ps1."""
    target = app.get("target") or ""
    wm = os.path.splitext(os.path.basename(target.replace("\\", "/")))[0].lower() if target else ""
    exec_ = "explorer.exe %s" % exec_arg(app["launch"])                 # opens exactly like the Start Menu
    name = RENAME.get(app["name"], app["name"])
    lines = ["[Desktop Entry]", "Type=Application", "Name=%s" % name, "Exec=%s" % exec_]
    themed_name = theme_icon(app["name"], wm, themed)
    if themed_name:
        lines.append("Icon=%s" % themed_name)
    elif app.get("icon"):
        lines.append("Icon=%s" % app["icon"].replace("\\", "/"))     # Qt reads C:/... fine; backslashes get mangled
    if wm:
        lines.append("StartupWMClass=%s" % WINDOW_EXE.get(wm, wm))
    lines.append("X-FreeForm=1")
    return "\n".join(lines) + "\n"


def exec_arg(s):
    """One quoted Exec= argument: inside quotes the desktop-entry parser needs \\\\ per backslash."""
    return '"%s"' % s.replace("\\", "\\" * 4).replace('"', '\\\\"')


# FreeForm's own apps, so Spotlight and Launchpad find them: (name, IPC target, icon: theme name or file in shell/assets)
OWN = [("Widget Studio", "widgetstudio", "preferences-desktop-theme"), ("Theme Studio", "themestudio", "preferences-desktop-color"),
       ("Files", "finder", "system-file-manager"), ("Settings", "settings", "preferences-system")]


def own_entries(root):
    """.desktop text for FreeForm's own apps; each opens through `qs ipc call <target> open`."""
    qs = os.path.join(root, "bin", "qs.exe")
    shell = os.path.join(root, "shell", "shell.qml")
    out = []
    for name, target, icon in OWN:
        verb = "start" if target == "tour" else "open"
        exec_ = "%s ipc -p %s call %s %s" % (exec_arg(qs), exec_arg(shell), target, verb)
        out.append((name, "\n".join(["[Desktop Entry]", "Type=Application", "Name=%s" % name, "Exec=%s" % exec_,
                                     "Icon=%s" % (icon if "." not in icon else os.path.join(root, "shell", "assets", icon).replace("\\", "/")),
                                     "Categories=FreeForm;", "X-FreeForm=1"]) + "\n"))
    return out


def filename(name):
    return "ff-" + re.sub(r"[^a-z0-9._-]", "_", name.lower()) + ".desktop"


# Windows apps that aren't Start Menu shortcuts on Windows 11 but should be findable (Spotlight, Launchpad, Dock)
SYSTEM_APPS = [{"name": "File Explorer", "launch": "explorer.exe", "target": "C:\\Windows\\explorer.exe", "icon": ""}]


def write_all(apps, d, own=(), themed=frozenset()):
    os.makedirs(d, exist_ok=True)
    keep = set()
    have = {a["name"].lower() for a in apps}
    apps = list(apps) + [a for a in SYSTEM_APPS if a["name"].lower() not in have]
    items = [(filename(a["name"]), entry(a, themed)) for a in apps] + [(filename("freeform " + n), t) for n, t in own]
    for f, text in items:
        keep.add(f)
        path = os.path.join(d, f)
        try:
            with open(path, encoding="utf-8") as fh:
                if fh.read() == text:
                    continue
        except OSError:
            pass
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
    for f in os.listdir(d):                                              # apps that were uninstalled
        if f.startswith("ff-") and f.endswith(".desktop") and f not in keep:
            os.remove(os.path.join(d, f))
    return len(keep)


def main(argv):
    if argv[:1] != ["sync"]:
        print("usage: apps sync", file=sys.stderr)
        return 64
    if os.name != "nt":
        return 0                                                         # Linux has real .desktop files
    icons = os.path.join(os.environ.get("LOCALAPPDATA", ""), "FreeForm", "icons")
    root = os.environ.get("FREEFORM_ROOT", "")
    own = own_entries(root) if root else ()
    # 1) the app list fast (icons only where already extracted), 2) again extracting missing icons.
    # Each pass has a time limit, so a stuck shortcut or Store app can't leave the app list empty.
    count = 0
    for extra, limit in ((["-NoIcons"], 90), ([], 300)):
        apps = list_apps(icons, extra, limit)
        if apps is None:
            continue
        count = write_all(apps, desktop_dir(), own, themed_icons(root))
    if not count:
        print("apps: could not list Start Menu apps", file=sys.stderr)
        return 1
    print("%d apps" % count)
    return 0


def list_apps(icons, extra, limit):
    try:
        r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                            "-File", os.path.join(HERE, "apps.ps1"), icons] + extra,
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           creationflags=0x08000000, timeout=limit)
    except subprocess.TimeoutExpired:
        print("apps: listing timed out after %d s%s" % (limit, " (icon pass)" if not extra else ""), file=sys.stderr)
        return None
    out = (r.stdout or "").strip()
    if out and out[0] not in "[{":                                       # anything printed before the JSON
        starts = [i for i in (out.find("["), out.find("{")) if i >= 0]
        out = out[min(starts):] if starts else out
    try:
        apps = json.loads(out or "[]")
    except ValueError:
        print("apps: unreadable list: %s" % (r.stderr or out)[-300:], file=sys.stderr)
        return None
    return [apps] if isinstance(apps, dict) else apps
