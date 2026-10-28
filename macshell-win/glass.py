"""Shared base for every floating glass surface (bar, dock, control center)."""
from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QWidget

import blur


class GlassWindow(QWidget):
    def __init__(self, tool=True):
        flags = (Qt.WindowType.FramelessWindowHint
                 | Qt.WindowType.WindowStaysOnTopHint)
        if tool:
            flags |= Qt.WindowType.Tool
        super().__init__(None, flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)

    def showEvent(self, e):
        super().showEvent(e)
        hwnd = int(self.winId())
        blur.apply_acrylic(hwnd)
        blur.round_corners(hwnd)
        blur.hide_from_taskbar(hwnd)
