"""Takeover: hide the Windows taskbar, stop Wallpaper Engine, set our wallpaper.

Everything is restored by release() (Quit MacShell, normal exit) or by
`python main.py --restore` if something ever goes wrong.
"""
import ctypes
import subprocess

WALLPAPER_ENGINE = ("wallpaper64", "wallpaper32")
SPI_SETDESKWALLPAPER = 0x14
SPI_GETDESKWALLPAPER = 0x73
SW_HIDE, SW_SHOW = 0, 5


def _user32():
    try:
        return ctypes.windll.user32
    except AttributeError:
        return None


def _taskbars():
    u = _user32()
    if not u:
        return []
    found = [u.FindWindowW("Shell_TrayWnd", None)]
    h = 0
    while True:  # one per extra monitor
        h = u.FindWindowExW(None, h, "Shell_SecondaryTrayWnd", None)
        if not h:
            break
        found.append(h)
    return [x for x in found if x]


def set_taskbar_visible(visible):
    u = _user32()
    for h in _taskbars():
        u.ShowWindow(h, SW_SHOW if visible else SW_HIDE)


def _ps(cmd):
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd],
                           capture_output=True, text=True, timeout=10)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def stop_wallpaper_engine():
    """Close Wallpaper Engine; return the exe paths so it can be restarted."""
    names = ",".join(WALLPAPER_ENGINE)
    out = _ps(f"Get-Process {names} -ErrorAction SilentlyContinue | "
              f"Select-Object -ExpandProperty Path")
    paths = sorted({p.strip() for p in out.splitlines() if p.strip()})
    if paths:
        _ps(f"Stop-Process -Name {names} -ErrorAction SilentlyContinue")
    return paths


def start_programs(paths):
    for p in paths:
        try:
            subprocess.Popen([p])
        except OSError:
            pass


def get_wallpaper():
    u = _user32()
    if not u:
        return ""
    buf = ctypes.create_unicode_buffer(520)
    u.SystemParametersInfoW(SPI_GETDESKWALLPAPER, len(buf), buf, 0)
    return buf.value


def set_wallpaper(path):
    u = _user32()
    if u and path:
        u.SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, 3)


class Takeover:
    def __init__(self):
        self.active = False
        self._we_paths = []
        self._old_wallpaper = ""

    def engage(self, s):
        if self.active:
            return
        self.active = True
        if s.get("override_wallpaper_engine"):
            self._we_paths = stop_wallpaper_engine()
        if s.get("wallpaper"):
            self._old_wallpaper = get_wallpaper()
            set_wallpaper(s["wallpaper"])
        if s.get("override_taskbar"):
            set_taskbar_visible(False)

    def release(self):
        if not self.active:
            return
        self.active = False
        set_taskbar_visible(True)
        if self._old_wallpaper:
            set_wallpaper(self._old_wallpaper)
        start_programs(self._we_paths)


def emergency_restore():
    """--restore: bring the taskbar back no matter what state we left it in."""
    set_taskbar_visible(True)
