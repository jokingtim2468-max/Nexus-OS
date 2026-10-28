"""MacShell Settings — laid out like macOS System Settings.

Every option in settings_store.DEFAULTS has a control here. "Apply" saves to
%APPDATA%\\MacShellWin\\settings.json and rebuilds the shell with the changes.
"""
import copy
import shlex

from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtWidgets import (QCheckBox, QFileDialog, QHBoxLayout, QLabel,
                             QLineEdit, QListWidget, QPushButton, QSlider,
                             QSpinBox, QStackedWidget, QTableWidget,
                             QTableWidgetItem, QVBoxLayout, QWidget)

import autostart
import settings_store
import theme as T
from glass import GlassWindow

ACCENTS = ["#0A84FF", "#BF5AF2", "#FF375F", "#FF453A", "#FF9F0A",
           "#FFD60A", "#30D158", "#8E8E93"]


class SettingsWindow(GlassWindow):
    applied = pyqtSignal(dict)
    tutorial_requested = pyqtSignal()
    restore_requested = pyqtSignal()

    def __init__(self, s):
        super().__init__(tool=False, on_top=True)
        self.s = copy.deepcopy(s)
        self.setWindowTitle("MacShell Settings")
        self.resize(760, 520)
        self._drag = None

        root = QWidget(self)
        root.setObjectName("win")
        root.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
        root.setStyleSheet(f"""
            QWidget#win {{ background:{T.GLASS}; border:1px solid {T.BORDER}; border-radius:14px; }}
            QLabel, QCheckBox {{ color:{T.TEXT}; font:13px '{T.FONT}'; background:transparent; }}
            QLabel#h {{ font-size:20px; font-weight:700; }}
            QLabel#cap {{ color:{T.TEXT_DIM}; font-size:11px; }}
            QWidget.row {{ background:{T.GLASS_HI}; border-radius:10px; }}
            QListWidget {{ background:transparent; border:none; color:{T.TEXT}; font:13px '{T.FONT}'; }}
            QListWidget::item {{ padding:7px 10px; border-radius:7px; }}
            QListWidget::item:selected {{ background:{T.ACCENT}; color:#fff; }}
            QPushButton {{ color:{T.TEXT}; background:{T.GLASS_HI}; border:1px solid {T.BORDER};
                           border-radius:7px; padding:5px 12px; font:13px '{T.FONT}'; }}
            QPushButton#primary {{ background:{T.ACCENT}; color:#fff; border:none; }}
            QPushButton#danger {{ background:{T.RED}; color:#fff; border:none; }}
            QLineEdit, QSpinBox, QTableWidget {{ color:{T.TEXT}; background:rgba(0,0,0,0.20);
                           border:1px solid {T.BORDER}; border-radius:6px; padding:3px; }}
            QHeaderView, QHeaderView::section, QTableCornerButton::section {{
                background:transparent; color:{T.TEXT_DIM}; border:none; padding:4px; }}
            QTableWidget {{ gridline-color:{T.BORDER}; }}
            QTableWidget::item:selected {{ background:{T.ACCENT}; color:#fff; }}
        """ + T.switch_qss())
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(root)
        lay = QHBoxLayout(root)
        lay.setContentsMargins(12, 12, 16, 12)

        side = QVBoxLayout()
        lights = QHBoxLayout()
        close = QPushButton()
        close.setFixedSize(12, 12)
        close.setStyleSheet("background:#FF5F57;border:none;border-radius:6px;padding:0;")
        close.clicked.connect(self.close)
        lights.addWidget(close); lights.addStretch(1)
        side.addLayout(lights)
        self.nav = QListWidget()
        self.nav.setFixedWidth(190)
        side.addWidget(self.nav)
        lay.addLayout(side)

        right = QVBoxLayout()
        self.stack = QStackedWidget()
        right.addWidget(self.stack, 1)
        buttons = QHBoxLayout()
        buttons.addStretch(1)
        revert = QPushButton("Revert")
        revert.clicked.connect(self.close)
        apply_btn = QPushButton("Apply")
        apply_btn.setObjectName("primary")
        apply_btn.clicked.connect(self.apply)
        buttons.addWidget(revert); buttons.addWidget(apply_btn)
        right.addLayout(buttons)
        lay.addLayout(right, 1)

        for name, build in [("General", self._general), ("Appearance", self._appearance),
                            ("Wallpaper", self._wallpaper), ("Dock", self._dock),
                            ("Menu Bar", self._menubar), ("Control Center", self._cc),
                            ("Startup & Takeover", self._startup),
                            ("Network & Privacy", self._network), ("About", self._about)]:
            self.nav.addItem(name)
            self.stack.addWidget(self._page(name, build))
        self.nav.currentRowChanged.connect(self.stack.setCurrentIndex)
        self.nav.setCurrentRow(0)

    # --- helpers ------------------------------------------------------------
    def _page(self, title, build):
        w = QWidget()
        v = QVBoxLayout(w)
        h = QLabel(title); h.setObjectName("h")
        v.addWidget(h)
        build(v)
        v.addStretch(1)
        return w

    def _row(self, v, label, widget, caption=None):
        row = QWidget(); row.setProperty("class", "row")
        row.setAttribute(Qt.WidgetAttribute.WA_StyledBackground)
        h = QHBoxLayout(row); h.setContentsMargins(12, 8, 12, 8)
        text = QVBoxLayout()
        text.addWidget(QLabel(label))
        if caption:
            c = QLabel(caption); c.setObjectName("cap"); c.setWordWrap(True)
            text.addWidget(c)
        h.addLayout(text, 1)
        h.addWidget(widget)
        v.addWidget(row)

    def _switch(self, key):
        c = QCheckBox()
        c.setChecked(bool(self.s.get(key)))
        c.toggled.connect(lambda on: self.s.__setitem__(key, on))
        return c

    def _slider(self, key, lo, hi, scale=1):
        sl = QSlider(Qt.Orientation.Horizontal)
        sl.setFixedWidth(200)
        sl.setRange(lo, hi)
        sl.setValue(int(round(self.s.get(key) * scale)))
        sl.valueChanged.connect(lambda val: self.s.__setitem__(key, val / scale if scale != 1 else val))
        return sl

    # --- pages --------------------------------------------------------------
    def _general(self, v):
        self._row(v, "Reduce motion", self._switch("reduce_motion"),
                  "Skips the launch animation and dock magnification easing.")
        tour = QPushButton("Show Tutorial")
        tour.clicked.connect(self.tutorial_requested.emit)
        self._row(v, "First-launch tour", tour)

    def _appearance(self, v):
        seg = QWidget(); h = QHBoxLayout(seg); h.setContentsMargins(0, 0, 0, 0)
        for mode in ("light", "dark"):
            b = QPushButton(mode.title())
            b.setCheckable(True)
            b.setChecked(self.s["theme"] == mode)
            b.clicked.connect(lambda _, m=mode, btn=b: self._pick_theme(m, seg))
            h.addWidget(b)
        self._row(v, "Appearance", seg)

        sw = QWidget(); h = QHBoxLayout(sw); h.setContentsMargins(0, 0, 0, 0); h.setSpacing(6)
        for c in ACCENTS:
            b = QPushButton()
            b.setFixedSize(22, 22)
            b.setStyleSheet(f"background:{c};border-radius:11px;border:2px solid "
                            f"{'#fff' if c == self.s['accent'] else 'transparent'};padding:0;")
            b.clicked.connect(lambda _, col=c: self._pick_accent(col, sw))
            b.setProperty("color", c)
            h.addWidget(b)
        self._row(v, "Accent color", sw)
        self._row(v, "Glass opacity", self._slider("glass_alpha", 40, 240),
                  "How solid the frosted glass is behind panels.")

    def _pick_theme(self, mode, seg):
        self.s["theme"] = mode
        for b in seg.findChildren(QPushButton):
            b.setChecked(b.text().lower() == mode)

    def _pick_accent(self, col, sw):
        self.s["accent"] = col
        for b in sw.findChildren(QPushButton):
            c = b.property("color")
            b.setStyleSheet(f"background:{c};border-radius:11px;border:2px solid "
                            f"{'#fff' if c == col else 'transparent'};padding:0;")

    def _wallpaper(self, v):
        self.wp_label = QLabel(self.s.get("wallpaper") or "Keep current Windows wallpaper")
        self.wp_label.setObjectName("cap"); self.wp_label.setWordWrap(True)
        pick = QPushButton("Choose…"); pick.clicked.connect(self._choose_wallpaper)
        clear = QPushButton("Clear"); clear.clicked.connect(lambda: self._set_wp(""))
        box = QWidget(); h = QHBoxLayout(box); h.setContentsMargins(0, 0, 0, 0)
        h.addWidget(pick); h.addWidget(clear)
        self._row(v, "Desktop picture", box,
                  "Applied while MacShell runs; your old wallpaper comes back when you quit.")
        v.addWidget(self.wp_label)

    def _choose_wallpaper(self):
        path, _ = QFileDialog.getOpenFileName(self, "Choose wallpaper", "",
                                              "Images (*.jpg *.jpeg *.png *.bmp)")
        if path:
            self._set_wp(path)

    def _set_wp(self, path):
        self.s["wallpaper"] = path
        self.wp_label.setText(path or "Keep current Windows wallpaper")

    def _dock(self, v):
        self._row(v, "Icon size", self._slider("dock_size", 32, 80))
        self._row(v, "Magnification", self._slider("dock_magnification", 100, 200, 100),
                  "1.0× = off.")
        self.table = QTableWidget(0, 3)
        self.table.setHorizontalHeaderLabels(["Icon", "Name", "Program, file or URL"])
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.verticalHeader().setVisible(False)
        for app in self.s["dock_apps"]:
            self._add_dock_row(app)
        v.addWidget(QLabel("Dock apps"))
        v.addWidget(self.table)
        h = QHBoxLayout()
        add = QPushButton("+ Add"); add.clicked.connect(lambda: self._add_dock_row({"glyph": "•", "name": "App", "path": ""}))
        browse = QPushButton("Browse…"); browse.clicked.connect(self._browse_app)
        rm = QPushButton("− Remove"); rm.clicked.connect(lambda: self.table.removeRow(self.table.currentRow()))
        for b in (add, browse, rm):
            h.addWidget(b)
        h.addStretch(1)
        v.addLayout(h)

    def _add_dock_row(self, app):
        r = self.table.rowCount()
        self.table.insertRow(r)
        for col, key in enumerate(("glyph", "name", "path")):
            self.table.setItem(r, col, QTableWidgetItem(app.get(key, "")))

    def _browse_app(self):
        path, _ = QFileDialog.getOpenFileName(self, "Choose program", "",
                                              "Programs (*.exe *.bat *.cmd *.lnk);;All files (*)")
        if path:
            name = path.replace("\\", "/").rsplit("/", 1)[-1].rsplit(".", 1)[0]
            self._add_dock_row({"glyph": "▣", "name": name, "path": path})

    def _menubar(self, v):
        self._row(v, "24-hour clock", self._switch("clock_24h"))
        self._row(v, "Show seconds", self._switch("clock_seconds"))
        spin = QSpinBox(); spin.setRange(1, 10); spin.setValue(int(self.s["workspaces"]))
        spin.valueChanged.connect(lambda n: self.s.__setitem__("workspaces", n))
        self._row(v, "Workspaces", spin)
        self._row(v, "Show Mullvad / Tor status", self._switch("show_net_status"))

    def _cc(self, v):
        self._row(v, "Volume slider", self._switch("cc_volume"))
        self._row(v, "Brightness slider", self._switch("cc_brightness"))

    def _startup(self, v):
        self._row(v, "Start automatically when I sign in", self._switch("autostart"),
                  "On: MacShell launches at sign-in and takes over. Off: it only runs "
                  "when you press Launch.")
        self._row(v, "Replace the Windows taskbar", self._switch("override_taskbar"))
        self._row(v, "Close Wallpaper Engine while running", self._switch("override_wallpaper_engine"),
                  "Restarted automatically when you quit MacShell.")
        sc = QPushButton("Create")
        sc.clicked.connect(lambda: sc.setText("Created ✓" if autostart.create_desktop_shortcut() else "Failed"))
        self._row(v, "Desktop shortcut", sc, "Opens the launcher.")
        rest = QPushButton("Quit and Restore Windows"); rest.setObjectName("danger")
        rest.clicked.connect(self.restore_requested.emit)
        self._row(v, "Restore normal Windows now", rest)

    def _network(self, v):
        self.hook_edits = {}
        for key, label in (("mullvad", "Mullvad command"), ("tor", "Tor route command")):
            e = QLineEdit(" ".join(self.s["hooks"].get(key, [])))
            e.setMinimumWidth(320)
            self.hook_edits[key] = e
            self._row(v, label, e)
        cap = QLabel("Use {connect} (connect/disconnect) or {state} (on/off); they're filled in "
                     "when you flip the switch in Control Center.")
        cap.setObjectName("cap"); cap.setWordWrap(True)
        v.addWidget(cap)

    def _about(self, v):
        for t in ("MacShell for Windows",
                  "A port of MacShell's look (github.com/0-ss/MacShell, MIT, © 2026 Rickky).",
                  f"Settings file: {settings_store.PATH}"):
            l = QLabel(t); l.setWordWrap(True)
            v.addWidget(l)

    # --- save ---------------------------------------------------------------
    def apply(self):
        apps = []
        for r in range(self.table.rowCount()):
            cell = lambda c: (self.table.item(r, c).text() if self.table.item(r, c) else "").strip()
            if cell(2):
                apps.append({"glyph": cell(0) or "•", "name": cell(1) or "App", "path": cell(2)})
        self.s["dock_apps"] = apps
        self.s["hooks"] = {k: shlex.split(e.text(), posix=False) for k, e in self.hook_edits.items()}
        autostart.set_enabled(self.s["autostart"])
        settings_store.save(self.s)
        self.applied.emit(copy.deepcopy(self.s))
        self.close()

    # drag by the background
    def mousePressEvent(self, e):
        self._drag = e.globalPosition().toPoint() - self.pos()

    def mouseMoveEvent(self, e):
        if self._drag is not None:
            self.move(e.globalPosition().toPoint() - self._drag)

    def mouseReleaseEvent(self, e):
        self._drag = None
