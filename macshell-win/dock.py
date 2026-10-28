"""Floating glass dock with macOS-style hover magnification."""
import os
import subprocess

from PyQt6.QtCore import QVariantAnimation, QEasingCurve
from PyQt6.QtWidgets import QHBoxLayout, QToolButton, QWidget

import config
import theme as T
from glass import GlassWindow

MAG = 1.45  # hovered icon scale


class DockIcon(QToolButton):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.setText(app["glyph"])
        self.setToolTip(app["name"])
        self.setFixedSize(int(T.DOCK_ICON * MAG) + 6, int(T.DOCK_ICON * MAG) + 6)
        self._px = T.DOCK_ICON
        self._anim = QVariantAnimation(self)
        self._anim.setDuration(140)
        self._anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._anim.valueChanged.connect(self._apply)
        self._apply(T.DOCK_ICON)
        self.clicked.connect(self.launch)

    def _apply(self, px):
        self._px = int(px)
        pad = int(T.DOCK_ICON * MAG) - self._px
        self.setStyleSheet(
            f"QToolButton {{ font-size:{int(self._px * 0.55)}px; color:{T.TEXT};"
            f" background:{T.GLASS_HI}; border:1px solid {T.BORDER};"
            f" border-radius:{int(self._px * 0.26)}px;"
            f" margin:{pad}px {pad // 2}px 0 {pad // 2}px; }}")

    def _to(self, target):
        self._anim.stop()
        self._anim.setStartValue(self._px)
        self._anim.setEndValue(target)
        self._anim.start()

    def enterEvent(self, e):
        self._to(int(T.DOCK_ICON * MAG))
        super().enterEvent(e)

    def leaveEvent(self, e):
        self._to(T.DOCK_ICON)
        super().leaveEvent(e)

    def launch(self):
        path = self.app["path"]
        try:
            if hasattr(os, "startfile"):
                os.startfile(path)          # Windows: exe, .bat, URIs
            else:
                subprocess.Popen([path])
        except OSError as exc:
            print(f"dock: could not launch {path}: {exc}")


class Dock(GlassWindow):
    def __init__(self, screen_geo):
        super().__init__()
        root = QWidget(self)
        root.setObjectName("dock")
        root.setStyleSheet(
            f"QWidget#dock {{ background:{T.GLASS}; border:1px solid {T.BORDER};"
            f" border-radius:{T.RADIUS_DOCK}px; }}")
        lay = QHBoxLayout(root)
        lay.setContentsMargins(10, 0, 10, 6)
        lay.setSpacing(2)
        for app in config.DOCK_APPS:
            lay.addWidget(DockIcon(app))
        root.adjustSize()
        self.resize(root.size())
        self.move(screen_geo.x() + (screen_geo.width() - self.width()) // 2,
                  screen_geo.y() + screen_geo.height() - self.height() - 10)
