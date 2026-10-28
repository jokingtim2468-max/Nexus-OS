"""Owns the running desktop: bar, dock, Control Center, takeover, tutorial."""
import atexit
import subprocess

from PyQt6.QtCore import QObject

import settings_store
import theme
from control_center import ControlCenter
from dock import Dock
from override import Takeover
from settings_app import SettingsWindow
from topbar import TopBar
from tutorial import Tutorial


class Shell(QObject):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.takeover = Takeover()
        atexit.register(self.takeover.release)   # never leave Windows half-hidden
        self.widgets = []
        self.settings_win = None
        self.tour = None

    # --- lifecycle ----------------------------------------------------------
    def start(self):
        self.s = settings_store.load()
        self.takeover.engage(self.s)
        self.build()
        if self.s.get("first_run", True):
            self.show_tutorial()

    def build(self):
        theme.apply(self.s)
        self.geo = self.app.primaryScreen().geometry()
        self.bar = TopBar(self.geo, self.s)
        self.dock = Dock(self.geo, self.s["dock_apps"], self.open_internal)
        self.cc = ControlCenter(self.geo, self.s)
        self.widgets = [self.bar, self.dock, self.cc]

        self.bar.control_center_clicked.connect(lambda: self.cc.setVisible(not self.cc.isVisible()))
        self.bar.settings_requested.connect(self.open_settings)
        self.bar.tutorial_requested.connect(self.show_tutorial)
        self.bar.quit_requested.connect(self.quit)
        self.cc.mullvad.toggled.connect(lambda on: self.run_hook("mullvad", on))
        self.cc.tor.toggled.connect(self._tor_toggled)

        self.bar.show()
        self.dock.show()

    def teardown(self):
        for w in self.widgets:
            w.close()
            w.deleteLater()
        self.widgets = []

    def rebuild(self, s):
        """Called after Settings → Apply: redraw everything with the new settings."""
        changed_takeover = any(self.s.get(k) != s.get(k) for k in
                               ("override_taskbar", "override_wallpaper_engine", "wallpaper"))
        self.s = s
        if changed_takeover:
            self.takeover.release()
            self.takeover.engage(s)
        self.teardown()
        self.build()

    def quit(self):
        self.takeover.release()
        self.teardown()
        self.app.quit()

    # --- actions ------------------------------------------------------------
    def open_internal(self, what):
        if what == "settings":
            self.open_settings()

    def open_settings(self):
        if self.settings_win and self.settings_win.isVisible():
            self.settings_win.raise_()
            return
        self.settings_win = SettingsWindow(self.s)
        self.settings_win.applied.connect(self.rebuild)
        self.settings_win.tutorial_requested.connect(self.show_tutorial)
        self.settings_win.restore_requested.connect(self.quit)
        g = self.settings_win.frameGeometry()
        g.moveCenter(self.geo.center())
        self.settings_win.move(g.topLeft())
        self.settings_win.show()

    def show_tutorial(self):
        self.tour = Tutorial(self)
        self.tour.finished.connect(self._tutorial_done)
        self.tour.show()
        self.tour.raise_()
        self.tour.activateWindow()

    def _tutorial_done(self):
        if self.s.get("first_run", True):
            self.s["first_run"] = False
            settings_store.save(self.s)

    def _tor_toggled(self, on):
        self.run_hook("tor", on)
        self.bar.set_status(self.cc.mullvad.switch.isChecked(), on)

    def run_hook(self, name, on):
        cmd = self.s.get("hooks", {}).get(name)
        if not cmd:
            return
        cmd = [c.replace("{state}", "on" if on else "off")
                .replace("{connect}", "connect" if on else "disconnect") for c in cmd]
        try:
            subprocess.Popen(cmd)
        except OSError as exc:
            print(f"hook {name} failed: {exc}")
