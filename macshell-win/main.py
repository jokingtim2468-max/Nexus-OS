"""MacShell for Windows — entry point.

    python main.py              open the launcher (what the desktop shortcut runs)
    python main.py --autostart  sign-in start: skip the launcher, take over directly
    python main.py --restore    emergency: bring the Windows taskbar back
"""
import sys

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import QApplication

import settings_store
import theme


def main():
    if "--restore" in sys.argv:
        import override
        override.emergency_restore()
        return

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    s = settings_store.load()
    theme.apply(s)

    from shell import Shell
    shell = Shell(app)

    if "--autostart" in sys.argv:
        shell.start()
    else:
        from launcher import Launcher
        launcher = Launcher(s)
        launcher.launched.connect(shell.start)
        # closing the launcher without launching quits the app
        launcher.destroyed.connect(lambda: shell.widgets or app.quit())
        launcher.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
        launcher.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
