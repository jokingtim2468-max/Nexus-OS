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
    exec_ = 'explorer.exe "%s"' % app["launch"]                         # opens exactly like the Start Menu
    lines = ["[Desktop Entry]", "Type=Application", "Name=%s" % app["name"], "Exec=%s" % exec_]
    if app.get("icon"):
        lines.append("Icon=%s" % app["icon"])
    if wm:
        lines.append("StartupWMClass=%s" % wm)
    lines.append("X-FreeForm=1")
    return "\n".join(lines) + "\n"


def filename(name):
    return "ff-" + re.sub(r"[^a-z0-9._-]", "_", name.lower()) + ".desktop"


def write_all(apps, d):
    os.makedirs(d, exist_ok=True)
    keep = set()
    for a in apps:
        f = filename(a["name"])
        keep.add(f)
        path = os.path.join(d, f)
        text = entry(a)
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
    r = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                        "-File", os.path.join(HERE, "apps.ps1"), icons],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", creationflags=0x08000000)
    try:
        apps = json.loads(r.stdout or "[]")
    except ValueError:
        print("apps: could not list Start Menu apps", file=sys.stderr)
        return 1
    if isinstance(apps, dict):
        apps = [apps]
    print("%d apps" % write_all(apps, desktop_dir()))
    return 0
