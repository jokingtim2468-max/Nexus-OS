"""`macshell-helper wallpaper engine ...` — Wallpaper Engine (Steam app 431960) for Settings > Wallpaper.

  wallpaper engine status          "installed\\t<exe>" or "missing"
  wallpaper engine list            one wallpaper per line (tab separated):
                                   W:<id>\\t<title>\\t<type>\\t<preview image>\\t<project.json>
  wallpaper engine apply FILE [MONITOR]   show it (starts Wallpaper Engine first if needed)
  wallpaper engine stop            remove Wallpaper Engine's wallpaper (a normal one was picked)

Wallpapers come from every Steam library: Workshop items (steamapps/workshop/content/431960/<id>)
and Wallpaper Engine's own projects (wallpaper_engine/projects/{myprojects,defaultprojects}).
Control uses Wallpaper Engine's documented command line
(https://help.wallpaperengine.io/en/functionality/cli.html). On Linux, `linux-wallpaperengine`
(open source) plays scene/video wallpapers from the same Steam folders when it is installed.

MACSHELL_WE_STEAM overrides the Steam folder (unusual installs, tests).
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

APP_ID = "431960"


class Fail(Exception):
    pass


def steam_root():
    env = os.environ.get("MACSHELL_WE_STEAM")
    if env:
        return env
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as k:
                return winreg.QueryValueEx(k, "SteamPath")[0]
        except OSError:
            return r"C:\Program Files (x86)\Steam"
    for p in ("~/.local/share/Steam", "~/.steam/steam", "~/.var/app/com.valvesoftware.Steam/.local/share/Steam"):
        p = os.path.expanduser(p)
        if os.path.isdir(p):
            return p
    return os.path.expanduser("~/.local/share/Steam")


def libraries(root):
    """Every Steam library folder: the main one plus those listed in libraryfolders.vdf."""
    libs = [root]
    try:
        with open(os.path.join(root, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace") as fh:
            for m in re.finditer(r'"path"\s+"([^"]+)"', fh.read()):
                p = m.group(1).replace("\\\\", "\\")
                if os.path.normcase(os.path.abspath(p)) not in [os.path.normcase(os.path.abspath(l)) for l in libs]:
                    libs.append(p)
    except OSError:
        pass
    return libs


def install_dir(libs):
    for lib in libs:
        d = os.path.join(lib, "steamapps", "common", "wallpaper_engine")
        if os.path.isdir(d):
            return d
    return None


def exe_path(d):
    for name in ("wallpaper64.exe", "wallpaper32.exe"):
        if d and os.path.isfile(os.path.join(d, name)):
            return os.path.join(d, name)
    return None


def wallpapers(libs, we_dir):
    dirs = []
    for lib in libs:
        dirs += glob.glob(os.path.join(lib, "steamapps", "workshop", "content", APP_ID, "*"))
    if we_dir:
        for sub in ("myprojects", "defaultprojects"):
            dirs += glob.glob(os.path.join(we_dir, "projects", sub, "*"))
    out = []
    for d in sorted(dirs):
        pj = os.path.join(d, "project.json")
        try:
            with open(pj, encoding="utf-8-sig") as fh:
                p = json.load(fh)
        except (OSError, ValueError):
            continue
        kind = str(p.get("type", "")).lower()
        if kind not in ("scene", "video", "web", "application"):
            continue
        preview = os.path.join(d, p["preview"]) if p.get("preview") else ""
        out.append({"id": os.path.basename(d), "title": str(p.get("title") or os.path.basename(d)).replace("\t", " ").strip(),
                    "type": kind, "preview": preview if preview and os.path.isfile(preview) else "", "file": pj})
    out.sort(key=lambda w: w["title"].lower())
    return out


def fmt(items):
    return "".join("W:%s\t%s\t%s\t%s\t%s\n" % (w["id"], w["title"], w["type"], w["preview"], w["file"]) for w in items)


def _running(exe):
    if os.name != "nt":
        return False
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq %s" % os.path.basename(exe), "/NH"],
                       capture_output=True, text=True, creationflags=0x08000000)
    return os.path.basename(exe).lower() in r.stdout.lower()


def control(exe, *args):
    flags = 0x08000000 if os.name == "nt" else 0
    r = subprocess.run([exe, "-control", *args], capture_output=True, text=True, creationflags=flags)
    if r.returncode != 0:
        raise Fail((r.stderr or r.stdout).strip() or "Wallpaper Engine did not accept the command.")
    return r.stdout


def apply_windows(exe, file, monitor):
    if not _running(exe):
        subprocess.Popen([exe], creationflags=0x08000000 | 0x00000008)   # CREATE_NO_WINDOW | DETACHED_PROCESS
        time.sleep(4)                                                     # it only takes commands once running
    control(exe, "openWallpaper", "-file", file, *(["-monitor", monitor] if monitor != "" else []))


def apply_linux(file, monitor):
    """linux-wallpaperengine plays the wallpaper behind the shell; one instance per screen."""
    lwe = shutil.which("linux-wallpaperengine")
    if not lwe:
        raise Fail("Install linux-wallpaperengine to play Wallpaper Engine wallpapers on Linux.")
    stop_linux()
    args = [lwe, "--silent"]
    if monitor != "":
        args += ["--screen-root", monitor]
    subprocess.Popen(args + [os.path.dirname(file)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def stop_linux():
    subprocess.run(["pkill", "-x", "linux-wallpaper"], capture_output=True)   # process name is cut at 15 chars


def main(argv):
    a = argv + ["", "", ""]
    libs = libraries(steam_root())
    we_dir = install_dir(libs)
    exe = exe_path(we_dir)
    try:
        if a[0] == "status":
            if os.name == "nt":
                print("installed\t%s" % exe if exe else "missing")
            else:
                lwe = shutil.which("linux-wallpaperengine")
                print("installed\t%s" % lwe if lwe else "missing")
        elif a[0] == "list":
            sys.stdout.write(fmt(wallpapers(libs, we_dir)))
        elif a[0] == "apply":
            if not a[1]:
                raise Fail("usage: wallpaper engine apply FILE [MONITOR]")
            if os.name == "nt":
                if not exe:
                    raise Fail("Wallpaper Engine isn't installed (Steam app 431960).")
                apply_windows(exe, a[1], a[2])
            else:
                apply_linux(a[1], a[2])
        elif a[0] == "stop":
            if os.name == "nt":
                if exe and _running(exe):
                    control(exe, "closeWallpaper")
            else:
                stop_linux()
        else:
            raise Fail("macshell-helper: unknown wallpaper engine command: %s" % " ".join(argv))
    except Fail as f:
        print(str(f), file=sys.stderr)
        return 1
    return 0
