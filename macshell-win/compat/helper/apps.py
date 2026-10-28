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


def entry(app):
    """One .desktop file's text for an app from apps.ps1."""
    target = app.get("target") or ""
    wm = os.path.splitext(os.path.basename(target.replace("\\", "/")))[0].lower() if target else ""
    exec_ = "explorer.exe %s" % exec_arg(app["launch"])                 # opens exactly like the Start Menu
    lines = ["[Desktop Entry]", "Type=Application", "Name=%s" % app["name"], "Exec=%s" % exec_]
    if app.get("icon"):
        lines.append("Icon=%s" % app["icon"].replace("\\", "/"))     # Qt reads C:/... fine; backslashes get mangled
    if wm:
        lines.append("StartupWMClass=%s" % wm)
    lines.append("X-FreeForm=1")
    return "\n".join(lines) + "\n"


def exec_arg(s):
    """One quoted Exec= argument: inside quotes the desktop-entry parser needs \\\\ per backslash."""
    return '"%s"' % s.replace("\\", "\\" * 4).replace('"', '\\\\"')


# FreeForm's own apps, so Spotlight and Launchpad find them: (name, IPC target, icon in shell/assets)
OWN = [("Finder", "finder", "freeform-logo.png"), ("Widget Studio", "widgetstudio", "freeform-logo.png"), ("Music", "music", "music-app.svg"),
       ("Theme Studio", "themestudio", "freeform-logo.png"), ("App Store", "appstore", "freeform-logo.png"),
       ("FreeForm Settings", "settings", "freeform-logo.png"), ("Welcome Tour", "tour", "freeform-logo.png")]


def own_entries(root):
    """.desktop text for FreeForm's own apps; each opens through `qs ipc call <target> open`."""
    qs = os.path.join(root, "bin", "qs.exe")
    shell = os.path.join(root, "shell", "shell.qml")
    out = []
    for name, target, icon in OWN:
        verb = "start" if target == "tour" else "open"
        exec_ = "%s ipc -p %s call %s %s" % (exec_arg(qs), exec_arg(shell), target, verb)
        out.append((name, "\n".join(["[Desktop Entry]", "Type=Application", "Name=%s" % name, "Exec=%s" % exec_,
                                     "Icon=%s" % os.path.join(root, "shell", "assets", icon).replace("\\", "/"),
                                     "Categories=FreeForm;", "X-FreeForm=1"]) + "\n"))
    return out


def filename(name):
    return "ff-" + re.sub(r"[^a-z0-9._-]", "_", name.lower()) + ".desktop"


def write_all(apps, d, own=()):
    os.makedirs(d, exist_ok=True)
    keep = set()
    items = [(filename(a["name"]), entry(a)) for a in apps] + [(filename("freeform " + n), t) for n, t in own]
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
        count = write_all(apps, desktop_dir(), own)
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
