"""The window the desktop shortcut opens.

- Auto-start toggle: ON = start at sign-in and take over Windows.
                     OFF = never start on its own.
- Launch button: dips down, bounces up, slides right, then expands to fill
  the whole desktop, and the shell takes over.
"""
from PyQt6.QtCore import (QEasingCurve, QParallelAnimationGroup, QPoint,
                          QPropertyAnimation, QRect, QSequentialAnimationGroup,
                          Qt, pyqtSignal)
from PyQt6.QtWidgets import QCheckBox, QLabel, QPushButton, QVBoxLayout, QWidget

import autostart
import settings_store
import theme as T
from glass import GlassWindow

W, H = 440, 330


def _anim(target, prop, start, end, ms, curve=QEasingCurve.Type.OutCubic):
    a = QPropertyAnimation(target, prop)
    a.setStartValue(start)
    a.setEndValue(end)
    a.setDuration(ms)
    a.setEasingCurve(curve)
    return a


class Launcher(GlassWindow):
    launched = pyqtSignal()

    def __init__(self, s):
        super().__init__(tool=False, on_top=False)
        self.s = s
        self.setWindowTitle("MacShell")
        self.resize(W, H)
        self._drag = None

        self.root = QWidget(self)
        self.root.setObjectName("card")
        self.root.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
        self.root.setStyleSheet(f"""
            QWidget#card {{ background:{T.GLASS}; border:1px solid {T.BORDER}; border-radius:22px; }}
            QLabel {{ color:{T.TEXT}; font-family:'{T.FONT}'; background:transparent; }}
            QLabel#logo {{ font-size:54px; font-weight:800; }}
            QLabel#title {{ font-size:20px; font-weight:700; }}
            QLabel#cap {{ color:{T.TEXT_DIM}; font-size:11px; }}
            QCheckBox {{ color:{T.TEXT}; font:13px '{T.FONT}'; spacing:10px; }}
            QPushButton#launch {{ background:{T.ACCENT}; color:#fff; border:none; border-radius:14px;
                                  font:600 15px '{T.FONT}'; }}
            QPushButton#close {{ background:#FF5F57; border:none; border-radius:6px; }}
        """ + T.switch_qss())
        lay = QVBoxLayout(self.root)
        lay.setContentsMargins(26, 22, 26, 86)   # bottom space for the button
        lay.setSpacing(6)
        logo = QLabel("FF"); logo.setObjectName("logo")
        title = QLabel("MacShell"); title.setObjectName("title")
        sub = QLabel("Turn Windows into a Mac."); sub.setObjectName("cap")
        for w in (logo, title, sub):
            w.setAlignment(Qt.AlignmentFlag.AlignHCenter)
            lay.addWidget(w)
        lay.addSpacing(10)
        self.auto = QCheckBox("Start automatically when I sign in")
        self.auto.setChecked(autostart.is_enabled() or s.get("autostart", False))
        self.auto.toggled.connect(self._set_autostart)
        cap = QLabel("On: takes over the Windows taskbar and Wallpaper Engine at sign-in.\n"
                     "Off: only runs when you press Launch.")
        cap.setObjectName("cap")
        cap.setWordWrap(True)
        lay.addWidget(self.auto)
        lay.addWidget(cap)
        self._info = [logo, title, sub, self.auto, cap]

        self.close_btn = QPushButton(self.root)
        self.close_btn.setObjectName("close")
        self.close_btn.setGeometry(14, 14, 12, 12)
        self.close_btn.clicked.connect(self.close)

        self.btn = QPushButton("Launch", self.root)
        self.btn.setObjectName("launch")
        self.btn.clicked.connect(self.launch)
        self._group = None

    # --- layout -----------------------------------------------------------
    def resizeEvent(self, e):
        self.root.setGeometry(0, 0, self.width(), self.height())
        if self._group is None:            # don't fight the animation
            self.btn.setGeometry(self._btn_home())
        super().resizeEvent(e)

    def _btn_home(self):
        return QRect((W - 160) // 2, H - 66, 160, 44)

    def showEvent(self, e):
        scr = self.screen().availableGeometry()
        self.move(scr.center() - QPoint(W // 2, H // 2))
        super().showEvent(e)

    # drag the card around
    def mousePressEvent(self, e):
        self._drag = e.globalPosition().toPoint() - self.pos()

    def mouseMoveEvent(self, e):
        if self._drag is not None and self._group is None:
            self.move(e.globalPosition().toPoint() - self._drag)

    def mouseReleaseEvent(self, e):
        self._drag = None

    # --- actions ----------------------------------------------------------
    def _set_autostart(self, on):
        autostart.set_enabled(on)
        self.s["autostart"] = on
        settings_store.save(self.s)

    def launch(self):
        if self._group is not None:
            return
        if T.REDUCE_MOTION:
            self._done()
            return
        home = self._btn_home()
        down = home.translated(0, 7)
        right = QRect(W - home.width() - 18, home.y(), home.width(), home.height())

        seq = QSequentialAnimationGroup(self)
        seq.addAnimation(_anim(self.btn, b"geometry", home, down, 90, QEasingCurve.Type.OutQuad))
        seq.addAnimation(_anim(self.btn, b"geometry", down, home.translated(0, -4), 120, QEasingCurve.Type.OutBack))
        seq.addAnimation(_anim(self.btn, b"geometry", home.translated(0, -4), right, 230, QEasingCurve.Type.InOutCubic))

        scr = self.screen().geometry()
        expand = QParallelAnimationGroup(self)
        expand.addAnimation(_anim(self, b"geometry", self.geometry(), scr, 420))
        expand.addAnimation(_anim(self.btn, b"geometry", right,
                                  QRect(0, 0, scr.width(), scr.height()), 420))
        expand.stateChanged.connect(lambda new, _old: new == QPropertyAnimation.State.Running
                                    and self._start_expand())
        seq.addAnimation(expand)
        seq.finished.connect(self._done)
        self._group = seq
        seq.start()

    def _start_expand(self):
        for w in self._info + [self.close_btn]:
            w.hide()
        self.btn.setText("")
        self.btn.setStyleSheet("border-radius:0;")
        self.raise_()
        self.activateWindow()

    def _done(self):
        self.launched.emit()                # shell builds underneath
        fade = _anim(self, b"windowOpacity", 1.0, 0.0, 0 if T.REDUCE_MOTION else 320)
        fade.finished.connect(self.close)
        fade.start()
        self._fade = fade
