"""Sign-in auto-start (HKCU Run key) and the desktop shortcut."""
import os
import subprocess
import sys

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
NAME = "MacShellWin"
MAIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "main.py")


def _pythonw():
    exe = sys.executable
    w = os.path.join(os.path.dirname(exe), "pythonw.exe")
    return w if os.path.exists(w) else exe


def _cmd(*args):
    return " ".join([f'"{_pythonw()}"', f'"{MAIN}"', *args])


def is_enabled():
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, NAME)
        return True
    except (ImportError, OSError):
        return False


def set_enabled(on):
    """On: start at sign-in in takeover mode. Off: remove it."""
    try:
        import winreg
    except ImportError:
        return False
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0,
                        winreg.KEY_SET_VALUE) as k:
        if on:
            winreg.SetValueEx(k, NAME, 0, winreg.REG_SZ, _cmd("--autostart"))
        else:
            try:
                winreg.DeleteValue(k, NAME)
            except FileNotFoundError:
                pass
    return True


def create_desktop_shortcut():
    """Desktop shortcut that opens the launcher (not the takeover)."""
    desktop = os.path.join(os.path.expanduser("~"), "Desktop", "MacShell.lnk")
    ps = (
        "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK);"
        "$s.TargetPath=$env:TGT;$s.Arguments=$env:ARGS;"
        "$s.WorkingDirectory=$env:WD;$s.Save()"
    )
    env = dict(os.environ, LNK=desktop, TGT=_pythonw(), ARGS=f'"{MAIN}"',
               WD=os.path.dirname(MAIN))
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                       env=env, check=True, capture_output=True)
        return desktop
    except (OSError, subprocess.CalledProcessError):
        return None
