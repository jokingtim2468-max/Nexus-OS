"""Shared base for every floating glass surface."""
from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QWidget

import blur
import theme as T


class GlassWindow(QWidget):
    def __init__(self, tool=True, on_top=True):
        flags = Qt.WindowType.FramelessWindowHint
        if on_top:
            flags |= Qt.WindowType.WindowStaysOnTopHint
        if tool:
            flags |= Qt.WindowType.Tool
        super().__init__(None, flags)
        self._tool = tool
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)

    def showEvent(self, e):
        super().showEvent(e)
        hwnd = int(self.winId())
        blur.apply_acrylic(hwnd, T.SLAB_RGB, T.GLASS_ALPHA)
        blur.round_corners(hwnd)
        if self._tool:
            blur.hide_from_taskbar(hwnd)
