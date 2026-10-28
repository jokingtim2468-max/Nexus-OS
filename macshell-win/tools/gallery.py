"""Show MacShell's own components (unmodified) in a window on plain Qt.

    python tools/gallery.py           # open a window (use this on Windows)
    python tools/gallery.py out.png   # render to a PNG and exit
"""
import os
import sys

from PyQt6.QtCore import QTimer, QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView

HERE = os.path.dirname(os.path.abspath(__file__))

app = QGuiApplication(sys.argv)
view = QQuickView()
view.setTitle("MacShell components on Windows")
view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "gallery.qml")))
for e in view.errors():
    print("QML ERROR:", e.toString())
view.show()

if len(sys.argv) > 1:
    def grab():
        view.grabWindow().save(sys.argv[1])
        app.quit()
    QTimer.singleShot(1500, grab)

sys.exit(app.exec())
