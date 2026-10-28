"""Floating glass dock with macOS-style hover magnification."""
import os
import subprocess

from PyQt6.QtCore import QEasingCurve, QRectF, QVariantAnimation
from PyQt6.QtGui import QPainterPath, QRegion
from PyQt6.QtWidgets import QHBoxLayout, QToolButton, QWidget

import theme as T
from glass import GlassWindow


class DockIcon(QToolButton):
    def __init__(self, app, on_internal):
        super().__init__()
        self.app = app
        self.on_internal = on_internal
        self.setText(app.get("glyph", "•"))
        self.setToolTip(app.get("name", ""))
        big = int(T.DOCK_ICON * T.MAG)
        self.setFixedSize(big + 6, big + 6)
        self._px = T.DOCK_ICON
        self._anim = QVariantAnimation(self)
        self._anim.setDuration(0 if T.REDUCE_MOTION else 140)
        self._anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._anim.valueChanged.connect(self._apply)
        self._apply(T.DOCK_ICON)
        self.clicked.connect(self.launch)

    def _apply(self, px):
        self._px = int(px)
        pad = int(T.DOCK_ICON * T.MAG) - self._px
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
        self._to(int(T.DOCK_ICON * T.MAG))
        super().enterEvent(e)

    def leaveEvent(self, e):
        self._to(T.DOCK_ICON)
        super().leaveEvent(e)

    def launch(self):
        path = self.app.get("path", "")
        if path.startswith("macshell:"):
            self.on_internal(path.split(":", 1)[1])
            return
        try:
            if hasattr(os, "startfile"):
                os.startfile(path)          # exe, .bat, URLs, ms-settings:
            else:
                subprocess.Popen([path])
        except OSError as exc:
            print(f"dock: could not launch {path}: {exc}")


class Dock(GlassWindow):
    """The window is tall enough for magnified icons, but the glass panel sits only
    behind the icon row. A window mask (panel + any popped-up icons) keeps the
    Windows Acrylic blur from frosting the empty space above the dock."""

    PAD = 7  # panel padding around icons

    def __init__(self, screen_geo, apps, on_internal):
        super().__init__()
        self.root = QWidget(self)
        self.panel = QWidget(self.root)
        self.panel.setObjectName("dockpanel")
        self.panel.setStyleSheet(
            f"QWidget#dockpanel {{ background:{T.GLASS}; border:1px solid {T.BORDER};"
            f" border-radius:{T.RADIUS_DOCK}px; }}")
        lay = QHBoxLayout(self.root)
        lay.setContentsMargins(10, 0, 10, self.PAD)
        lay.setSpacing(0)
        self.icons = [DockIcon(a, on_internal) for a in apps]
        for ic in self.icons:
            lay.addWidget(ic)
            ic._anim.valueChanged.connect(lambda _: self.update_mask())
        self.root.adjustSize()
        self.resize(self.root.size())
        h = T.DOCK_ICON + 2 * self.PAD
        self.panel.setGeometry(0, self.height() - h, self.width(), h)
        self.panel.lower()
        self.move(screen_geo.x() + (screen_geo.width() - self.width()) // 2,
                  screen_geo.y() + screen_geo.height() - self.height() - 10)
        self.update_mask()

    def update_mask(self):
        path = QPainterPath()
        path.addRoundedRect(QRectF(self.panel.geometry()), T.RADIUS_DOCK, T.RADIUS_DOCK)
        region = QRegion(path.toFillPolygon().toPolygon())
        for ic in self.icons:
            pad = int(T.DOCK_ICON * T.MAG) - ic._px
            g = ic.geometry().adjusted(pad // 2, pad, -(pad // 2), 0)
            region = region.united(QRegion(g))
        self.setMask(region)

    def icon_named(self, name):
        return next((i for i in self.icons if i.app.get("name") == name), None)
