"""MacShell for Windows — entry point.

Starts the top bar, dock and Control Center, and wires the Control Center
toggles to your own VPN/Tor scripts (config.HOOKS).

    pip install -r requirements.txt
    python main.py
"""
import subprocess
import sys

from PyQt6.QtWidgets import QApplication

import config
from control_center import ControlCenter
from dock import Dock
from topbar import TopBar


def run_hook(name, on):
    cmd = config.HOOKS.get(name)
    if not cmd:
        return
    cmd = [c.replace("{state}", "on" if on else "off")
            .replace("{connect}", "connect" if on else "disconnect") for c in cmd]
    try:
        subprocess.Popen(cmd)
    except OSError as exc:
        print(f"hook {name} failed: {exc}")


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    geo = app.primaryScreen().geometry()

    bar = TopBar(geo)
    dock = Dock(geo)
    cc = ControlCenter(geo)

    bar.control_center_clicked.connect(cc.toggle_visible)
    cc.tor.toggled.connect(lambda on: (run_hook("tor", on),
                                       bar.set_status(cc.mullvad.switch.isChecked(), on)))
    cc.mullvad.toggled.connect(lambda on: run_hook("mullvad", on))

    bar.show()
    dock.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
