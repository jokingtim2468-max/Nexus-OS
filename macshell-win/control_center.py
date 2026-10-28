"""MacShell-style Control Center: volume/brightness sliders + Mullvad/Tor toggles.

Toggles emit Qt signals; main.py connects them to the commands in config.HOOKS.
"""
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtWidgets import (QHBoxLayout, QLabel, QSlider, QVBoxLayout,
                             QWidget, QCheckBox)

import theme as T
from glass import GlassWindow

QSS = f"""
QWidget#cc {{ background:{T.GLASS}; border:1px solid {T.BORDER}; border-radius:{T.RADIUS_MENU + 4}px; }}
QWidget.card {{ background:{T.GLASS_HI}; border:1px solid {T.BORDER}; border-radius:{T.RADIUS_MENU}px; }}
QLabel {{ color:{T.TEXT}; font:13px '{T.FONT}'; background:transparent; }}
QLabel.cap {{ color:{T.TEXT_DIM}; font-size:10px; font-weight:700; letter-spacing:1px; }}
QLabel.sub {{ color:{T.TEXT_DIM}; font-size:11px; }}
QSlider::groove:horizontal {{ height:22px; border-radius:11px; background:rgba(0,0,0,0.30); }}
QSlider::sub-page:horizontal {{ border-radius:11px; background:rgba(255,255,255,0.85); }}
QSlider::handle:horizontal {{ width:20px; margin:1px; border-radius:10px; background:#fff; }}
QCheckBox::indicator {{ width:38px; height:22px; border-radius:11px; background:rgba(120,120,128,0.5); }}
QCheckBox::indicator:checked {{ background:{T.ACCENT}; }}
QCheckBox::indicator:disabled {{ background:rgba(48,209,88,0.45); }}
"""


def _card():
    w = QWidget(); w.setProperty("class", "card")
    w.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
    return w


class SliderRow(QWidget):
    changed = pyqtSignal(int)

    def __init__(self, caption, icon, value):
        super().__init__()
        card = _card(); v = QVBoxLayout(self); v.setContentsMargins(0, 0, 0, 0); v.addWidget(card)
        lay = QVBoxLayout(card); lay.setContentsMargins(12, 8, 12, 10)
        cap = QLabel(caption); cap.setProperty("class", "cap"); lay.addWidget(cap)
        row = QHBoxLayout(); row.addWidget(QLabel(icon))
        self.slider = QSlider(Qt.Orientation.Horizontal); self.slider.setRange(0, 100)
        self.slider.setValue(value); self.slider.valueChanged.connect(self.changed.emit)
        row.addWidget(self.slider); lay.addLayout(row)


class ToggleRow(QWidget):
    toggled = pyqtSignal(bool)

    def __init__(self, title, status, dot, checked=True, locked=False):
        super().__init__()
        card = _card(); v = QVBoxLayout(self); v.setContentsMargins(0, 0, 0, 0); v.addWidget(card)
        lay = QHBoxLayout(card); lay.setContentsMargins(12, 10, 12, 10)
        badge = QLabel("●"); badge.setStyleSheet(f"color:{dot}; font-size:22px;")
        lay.addWidget(badge)
        text = QVBoxLayout()
        t = QLabel(title); t.setStyleSheet("font-weight:600;"); text.addWidget(t)
        self.status = QLabel(status); self.status.setProperty("class", "sub"); text.addWidget(self.status)
        lay.addLayout(text); lay.addStretch(1)
        self.switch = QCheckBox(); self.switch.setChecked(checked)
        self.switch.setEnabled(not locked)
        self.switch.toggled.connect(self.toggled.emit)
        lay.addWidget(self.switch)
        if locked:
            lay.addWidget(QLabel("🔒"))


class ControlCenter(GlassWindow):
    def __init__(self, screen_geo):
        super().__init__()
        self.setStyleSheet(QSS)
        root = QWidget(self); root.setObjectName("cc")
        root.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
        lay = QVBoxLayout(root); lay.setContentsMargins(12, 12, 12, 12); lay.setSpacing(8)

        self.volume = SliderRow("VOLUME", "🔊", 65)
        self.brightness = SliderRow("BRIGHTNESS", "☀", 80)
        # Kill switch keeps Mullvad locked on — the toggle is shown but disabled.
        self.mullvad = ToggleRow("MULLVAD VPN", "CONNECTED", T.ACCENT, checked=True, locked=True)
        self.tor = ToggleRow("TOR ROUTE", "ACTIVE", T.PURPLE, checked=True)
        for w in (self.volume, self.brightness, self.mullvad, self.tor):
            lay.addWidget(w)

        root.setFixedWidth(320); root.adjustSize(); self.resize(root.size())
        self.move(screen_geo.x() + screen_geo.width() - self.width() - 10,
                  screen_geo.y() + T.BAR_HEIGHT + 8)

    def toggle_visible(self):
        self.setVisible(not self.isVisible())
