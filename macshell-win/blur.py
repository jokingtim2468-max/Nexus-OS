"""Native Windows Acrylic blur behind frameless Qt windows.

Uses user32.SetWindowCompositionAttribute (Win10 1803+/Win11). All windll access
happens inside functions so the module imports on any OS.
"""
import ctypes
from ctypes import POINTER, Structure, byref, c_int, c_uint, c_void_p, sizeof


class _AccentPolicy(Structure):
    _fields_ = [("AccentState", c_uint), ("AccentFlags", c_uint),
                ("GradientColor", c_uint), ("AnimationId", c_uint)]


class _CompAttrData(Structure):
    _fields_ = [("Attribute", c_int), ("Data", POINTER(_AccentPolicy)),
                ("SizeOfData", c_uint)]


ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
WCA_ACCENT_POLICY = 19


def apply_acrylic(hwnd, rgb=(0x2B, 0x2B, 0x2D), alpha=0x99):
    """Frosted glass behind `hwnd`. rgb/alpha = tint (MacShell slab #2B2B2D)."""
    try:
        user32 = ctypes.windll.user32
    except AttributeError:
        return False
    r, g, b = rgb
    accent = _AccentPolicy(ACCENT_ENABLE_ACRYLICBLURBEHIND, 2,
                           (alpha << 24) | (b << 16) | (g << 8) | r, 0)
    data = _CompAttrData(WCA_ACCENT_POLICY, ctypes.pointer(accent), sizeof(accent))
    fn = user32.SetWindowCompositionAttribute
    fn.argtypes = [c_void_p, POINTER(_CompAttrData)]
    fn.restype = c_int
    return bool(fn(c_void_p(int(hwnd)), byref(data)))


def round_corners(hwnd):
    """Win11 native rounded corners (DWMWA_WINDOW_CORNER_PREFERENCE=33, ROUND=2)."""
    try:
        pref = c_int(2)
        ctypes.windll.dwmapi.DwmSetWindowAttribute(c_void_p(int(hwnd)), 33,
                                                   byref(pref), sizeof(pref))
    except (AttributeError, OSError):
        pass


def hide_from_taskbar(hwnd):
    """Tool window: not in taskbar / Alt+Tab."""
    try:
        user32 = ctypes.windll.user32
    except AttributeError:
        return
    GWL_EXSTYLE, WS_EX_TOOLWINDOW = -20, 0x80
    style = user32.GetWindowLongW(int(hwnd), GWL_EXSTYLE)
    user32.SetWindowLongW(int(hwnd), GWL_EXSTYLE, style | WS_EX_TOOLWINDOW)
