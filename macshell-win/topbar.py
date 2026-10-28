"""MacShell-style menu bar: workspaces left, clock center, status right."""
from PyQt6.QtCore import QDateTime, QTimer, pyqtSignal
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QWidget

import config
import theme as T
from glass import GlassWindow


class TopBar(GlassWindow):
    control_center_clicked = pyqtSignal()

    def __init__(self, screen_geo):
        super().__init__()
        self.setGeometry(screen_geo.x(), screen_geo.y(), screen_geo.width(), T.BAR_HEIGHT)
        self.setStyleSheet(f"""
            QWidget#bar {{ background:{T.GLASS}; border-bottom:1px solid {T.BORDER}; }}
            QLabel, QPushButton {{ color:{T.TEXT}; font:13px '{T.FONT}'; background:transparent; border:none; }}
            QPushButton {{ padding:2px 8px; border-radius:6px; }}
            QPushButton:hover {{ background:{T.GLASS_HI}; }}
            QPushButton[active="true"] {{ background:{T.GLASS_HI}; font-weight:600; }}
        """)
        root = QWidget(self); root.setObjectName("bar")
        root.setGeometry(0, 0, self.width(), self.height())
        lay = QHBoxLayout(root); lay.setContentsMargins(12, 0, 12, 0); lay.setSpacing(4)

        brand = QLabel("FF"); brand.setStyleSheet("font-weight:700;")
        lay.addWidget(brand)
        self.ws = []
        for i in range(1, config.WORKSPACES + 1):
            b = QPushButton(str(i)); b.setProperty("active", i == 1)
            b.clicked.connect(lambda _, n=i: self.set_workspace(n))
            self.ws.append(b); lay.addWidget(b)
        lay.addStretch(1)
        self.clock = QLabel(); lay.addWidget(self.clock)
        lay.addStretch(1)
        self.vpn = QLabel("● Mullvad"); self.vpn.setStyleSheet(f"color:{T.GREEN};")
        self.tor = QLabel("◉ Tor"); self.tor.setStyleSheet(f"color:{T.PURPLE};")
        cc = QPushButton("☰"); cc.clicked.connect(self.control_center_clicked.emit)
        for w in (self.vpn, self.tor, cc):
            lay.addWidget(w)

        t = QTimer(self); t.timeout.connect(self._tick); t.start(1000); self._tick()

    def _tick(self):
        self.clock.setText(QDateTime.currentDateTime().toString("ddd d MMM  h:mm AP"))

    def set_workspace(self, n):
        for i, b in enumerate(self.ws, 1):
            b.setProperty("active", i == n)
            b.style().unpolish(b); b.style().polish(b)

    def set_status(self, vpn_on, tor_on):
        self.vpn.setStyleSheet(f"color:{T.GREEN if vpn_on else T.RED};")
        self.tor.setStyleSheet(f"color:{T.PURPLE if tor_on else T.TEXT_DIM};")
