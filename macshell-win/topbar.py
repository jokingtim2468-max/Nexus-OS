"""MacShell-style menu bar: FF menu + workspaces left, clock center, status right."""
from PyQt6.QtCore import QDateTime, QTimer, pyqtSignal
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QMenu, QPushButton, QWidget

import theme as T
from glass import GlassWindow


class TopBar(GlassWindow):
    control_center_clicked = pyqtSignal()
    settings_requested = pyqtSignal()
    tutorial_requested = pyqtSignal()
    quit_requested = pyqtSignal()

    def __init__(self, screen_geo, s):
        super().__init__()
        self.s = s
        self.setGeometry(screen_geo.x(), screen_geo.y(), screen_geo.width(), T.BAR_HEIGHT)
        self.setStyleSheet(f"""
            QWidget#bar {{ background:{T.GLASS}; border-bottom:1px solid {T.BORDER}; }}
            QLabel, QPushButton {{ color:{T.TEXT}; font:13px '{T.FONT}'; background:transparent; border:none; }}
            QPushButton {{ padding:2px 8px; border-radius:6px; }}
            QPushButton:hover {{ background:{T.GLASS_HI}; }}
            QPushButton[active="true"] {{ background:{T.GLASS_HI}; font-weight:600; }}
            QPushButton::menu-indicator {{ width:0; }}
            QMenu {{ background:rgb{T.SLAB_RGB}; color:{T.TEXT}; border:1px solid {T.BORDER};
                     border-radius:10px; padding:5px; }}
            QMenu::item {{ padding:6px 18px; border-radius:6px; }}
            QMenu::item:selected {{ background:{T.ACCENT}; color:#fff; }}
        """)
        root = QWidget(self)
        root.setObjectName("bar")
        root.setGeometry(0, 0, self.width(), self.height())
        lay = QHBoxLayout(root)
        lay.setContentsMargins(10, 0, 12, 0)
        lay.setSpacing(4)

        self.brand = QPushButton("FF")
        self.brand.setStyleSheet("font-weight:800;")
        menu = QMenu(self.brand)
        menu.addAction("Settings…", self.settings_requested.emit)
        menu.addAction("Show Tutorial", self.tutorial_requested.emit)
        menu.addSeparator()
        menu.addAction("Quit MacShell (restore Windows)", self.quit_requested.emit)
        self.brand.setMenu(menu)
        lay.addWidget(self.brand)

        self.ws = []
        for i in range(1, int(s.get("workspaces", 5)) + 1):
            b = QPushButton(str(i))
            b.setProperty("active", i == 1)
            b.clicked.connect(lambda _, n=i: self.set_workspace(n))
            self.ws.append(b)
            lay.addWidget(b)
        lay.addStretch(1)
        self.clock = QLabel()
        lay.addWidget(self.clock)
        lay.addStretch(1)

        self.vpn = QLabel("● Mullvad")
        self.tor = QLabel("◉ Tor")
        if s.get("show_net_status", True):
            lay.addWidget(self.vpn)
            lay.addWidget(self.tor)
        self.set_status(True, True)
        self.cc_button = QPushButton("☰")
        self.cc_button.clicked.connect(self.control_center_clicked.emit)
        lay.addWidget(self.cc_button)

        t = QTimer(self)
        t.timeout.connect(self._tick)
        t.start(1000)
        self._tick()

    def _tick(self):
        fmt = "ddd d MMM  " + ("HH:mm" if self.s.get("clock_24h") else "h:mm")
        if self.s.get("clock_seconds"):
            fmt += ":ss"
        if not self.s.get("clock_24h"):
            fmt += " AP"
        self.clock.setText(QDateTime.currentDateTime().toString(fmt))

    def set_workspace(self, n):
        for i, b in enumerate(self.ws, 1):
            b.setProperty("active", i == n)
            b.style().unpolish(b)
            b.style().polish(b)

    def set_status(self, vpn_on, tor_on):
        self.vpn.setStyleSheet(f"color:{T.GREEN if vpn_on else T.RED};")
        self.tor.setStyleSheet(f"color:{T.PURPLE if tor_on else T.TEXT_DIM};")
