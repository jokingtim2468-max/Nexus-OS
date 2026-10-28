"""First-launch tour: dims the screen and spotlights one part at a time."""
from PyQt6.QtCore import QRect, QRectF, Qt, pyqtSignal
from PyQt6.QtGui import QColor, QPainter, QPainterPath, QPen
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

import theme as T


class Tutorial(QWidget):
    finished = pyqtSignal()

    def __init__(self, shell):
        super().__init__(None, Qt.WindowType.FramelessWindowHint
                         | Qt.WindowType.WindowStaysOnTopHint | Qt.WindowType.Tool)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.shell = shell
        self.setGeometry(shell.geo)
        self.hole = None
        self.i = 0
        bar, dock = shell.bar, shell.dock
        settings_icon = dock.icon_named("Settings")
        self.steps = [
            ("Welcome to MacShell",
             "Windows now looks and works like a Mac. This quick tour shows you around — "
             "it takes about 20 seconds.", None),
            ("The menu bar",
             "Across the top: the FF menu (Settings, this tour, and Quit MacShell, which "
             "puts normal Windows back), your workspaces, and the clock.", lambda: bar.geometry()),
            ("Status & Control Center",
             "Green Mullvad = VPN connected, purple Tor = traffic routed through Tor. "
             "Click ☰ for volume, brightness and the VPN/Tor switches.",
             lambda: self._global(bar.cc_button)),
            ("The dock",
             "Your apps. Hover to magnify, click to open. Add or remove apps in "
             "Settings → Dock.", lambda: dock.geometry()),
            ("Settings",
             "Everything is customizable here: theme, accent, wallpaper, dock, menu bar, "
             "auto-start and what MacShell takes over.",
             (lambda: self._global(settings_icon)) if settings_icon else None),
            ("You're all set",
             "Re-open this tour any time from the FF menu → Show Tutorial.", None),
        ]

        self.card = QWidget(self)
        self.card.setObjectName("card")
        self.card.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
        self.card.setFixedWidth(340)
        self.card.setStyleSheet(f"""
            QWidget#card {{ background:rgb{T.SLAB_RGB}; border:1px solid {T.BORDER}; border-radius:16px; }}
            QLabel {{ color:{T.TEXT}; font-family:'{T.FONT}'; background:transparent; }}
            QLabel#t {{ font-size:16px; font-weight:700; }}
            QLabel#b {{ font-size:13px; color:{T.TEXT_DIM}; }}
            QPushButton {{ color:{T.TEXT}; background:{T.GLASS_HI}; border:none; border-radius:8px;
                           padding:6px 14px; font:13px '{T.FONT}'; }}
            QPushButton#next {{ background:{T.ACCENT}; color:#fff; }}
        """)
        v = QVBoxLayout(self.card)
        v.setContentsMargins(18, 16, 18, 14)
        self.t = QLabel(); self.t.setObjectName("t")
        self.b = QLabel(); self.b.setObjectName("b"); self.b.setWordWrap(True)
        self.count = QLabel(); self.count.setObjectName("b")
        v.addWidget(self.t); v.addWidget(self.b)
        row = QHBoxLayout()
        row.addWidget(self.count); row.addStretch(1)
        skip = QPushButton("Skip"); skip.clicked.connect(self.finish)
        self.back = QPushButton("Back"); self.back.clicked.connect(lambda: self.go(self.i - 1))
        self.next = QPushButton("Next"); self.next.setObjectName("next")
        self.next.clicked.connect(lambda: self.go(self.i + 1))
        for w in (skip, self.back, self.next):
            row.addWidget(w)
        v.addLayout(row)
        self.go(0)

    def _global(self, w):
        return QRect(w.mapToGlobal(w.rect().topLeft()), w.size())

    def go(self, i):
        if i >= len(self.steps):
            self.finish()
            return
        self.i = max(0, i)
        title, body, target = self.steps[self.i]
        self.t.setText(title)
        self.b.setText(body)
        self.count.setText(f"{self.i + 1} / {len(self.steps)}")
        self.back.setEnabled(self.i > 0)
        self.next.setText("Done" if self.i == len(self.steps) - 1 else "Next")
        self.hole = None
        if target:
            g = target()
            self.hole = QRect(g.topLeft() - self.geometry().topLeft(), g.size())
        self.card.adjustSize()
        self._place_card()
        self.update()

    def _place_card(self):
        cw, ch, W, H = self.card.width(), self.card.height(), self.width(), self.height()
        if not self.hole:
            x, y = (W - cw) // 2, (H - ch) // 2
        else:
            x = self.hole.center().x() - cw // 2
            y = self.hole.bottom() + 22 if self.hole.center().y() < H / 2 else self.hole.top() - ch - 22
        self.card.move(max(16, min(x, W - cw - 16)), max(16, min(y, H - ch - 16)))

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        path = QPainterPath()
        path.addRect(QRectF(self.rect()))
        if self.hole:
            r = QRectF(self.hole.adjusted(-8, -6, 8, 6))
            h = QPainterPath()
            h.addRoundedRect(r, 14, 14)
            path = path.subtracted(h)
            p.setPen(QPen(QColor(T.ACCENT), 2))
            p.drawRoundedRect(r, 14, 14)
        p.fillPath(path, QColor(0, 0, 0, 150))

    def keyPressEvent(self, e):
        if e.key() == Qt.Key.Key_Escape:
            self.finish()
        elif e.key() in (Qt.Key.Key_Right, Qt.Key.Key_Return, Qt.Key.Key_Space):
            self.go(self.i + 1)
        elif e.key() == Qt.Key.Key_Left:
            self.go(self.i - 1)

    def finish(self):
        self.close()
        self.finished.emit()
