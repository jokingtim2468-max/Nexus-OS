"""`macshell-helper wallpaper scan|set` — MacShell's wallpaper folder scan and "set desktop picture"
without the Linux tools it used (find, awww).

  wallpaper scan DIR MAKE(0|1) [FAVOURITE...]   lines MacBar.qml reads: A:<file> per image/video in DIR
                                               (3 levels deep, natural sort), F:<fav> per existing favourite
  wallpaper set FILE                           make FILE the desktop picture (Windows: SPI_SETDESKWALLPAPER)
"""
import os
import re
import sys

EXT = re.compile(r"\.(jpe?g|png|webp|bmp|gif|mp4|webm|mkv|mov|m4v)$", re.I)


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def scan(d, make, favs):
    out = []
    if make == "1" and not os.path.isdir(d):
        try:
            os.makedirs(d, exist_ok=True)
        except OSError:
            pass
    if os.path.isdir(d):
        base = d.rstrip("\\/").count(os.sep)
        files = []
        for cur, dirs, names in os.walk(d, followlinks=True):
            if cur.rstrip("\\/").count(os.sep) - base >= 2:
                dirs[:] = []
            files += [os.path.join(cur, n) for n in names if EXT.search(n)]
        out += ["A:" + f.replace("\\", "/") for f in sorted(files, key=natural)]
    out += ["F:" + f for f in favs if os.path.isfile(f)]
    return "\n".join(out) + ("\n" if out else "")


def set_picture(path):
    if os.name == "nt":
        import ctypes
        SPI_SETDESKWALLPAPER, UPDATE = 0x0014, 0x01 | 0x02            # update ini + broadcast
        if not ctypes.windll.user32.SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, os.path.abspath(path), UPDATE):
            raise OSError("Windows refused the picture")
        return
    import shutil
    import subprocess
    for cmd in (["awww", "img", path], ["swww", "img", path],
                ["gsettings", "set", "org.gnome.desktop.background", "picture-uri", "file://" + path]):
        if shutil.which(cmd[0]) and subprocess.run(cmd, capture_output=True).returncode == 0:
            return
    raise OSError("no wallpaper tool found")


def main(argv):
    a = argv + ["", "", ""]
    try:
        if a[0] == "scan":
            sys.stdout.write(scan(a[1], a[2], argv[3:]))
        elif a[0] == "set" and a[1]:
            set_picture(a[1])
        else:
            raise OSError("usage: wallpaper scan DIR MAKE [FAV...] | wallpaper set FILE")
    except OSError as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0
