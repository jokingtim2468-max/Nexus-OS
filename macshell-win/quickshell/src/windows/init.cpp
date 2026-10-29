#include <windows.h>
#include <dwmapi.h>

#include <qcoreevent.h>
#include <qguiapplication.h>
#include <qwindow.h>
#include <qlist.h>
#include <qqml.h>
#include <qstring.h>

#include "../core/plugin.hpp"
#include "panel_window.hpp"

namespace {

// FreeForm's app windows (Widget Studio, Settings...) are frameless Qt windows; Windows 11 only
// rounds the corners of frameless windows when asked. Panels (bar, Dock, widgets) are left alone.
// A window with a QML property `ffBackdrop` also gets Windows 11's own blur behind it (the glass look):
// 2 = Mica, 3 = Acrylic (DWMWA_SYSTEMBACKDROP_TYPE, Windows 11 22H2+; ignored on older Windows).
// `ffDarkGlass: true` asks for the dark variant.
class RoundCorners: public QObject {
public:
	bool eventFilter(QObject* watched, QEvent* event) override {
		if (event->type() == QEvent::Show) {
			auto* window = qobject_cast<QWindow*>(watched);
			if (window != nullptr && window->isTopLevel() && !window->property("qsPanel").toBool()
			    && window->flags().testFlag(Qt::FramelessWindowHint) && window->handle() != nullptr)
			{
				auto* hwnd = reinterpret_cast<HWND>(window->winId()); // NOLINT
				DWORD round = 2; // DWMWCP_ROUND (DWMWA_WINDOW_CORNER_PREFERENCE = 33; Windows 11+)
				DwmSetWindowAttribute(hwnd, 33, &round, sizeof(round));
				auto backdrop = window->property("ffBackdrop");
				if (backdrop.isValid() && backdrop.toInt() > 0) {
					BOOL dark = window->property("ffDarkGlass").toBool() ? TRUE : FALSE;
					DwmSetWindowAttribute(hwnd, 20, &dark, sizeof(dark)); // DWMWA_USE_IMMERSIVE_DARK_MODE
					MARGINS all = {-1, -1, -1, -1};                         // the backdrop shows through the whole window
					DwmExtendFrameIntoClientArea(hwnd, &all);
					DWORD type = backdrop.toInt();
					DwmSetWindowAttribute(hwnd, 38, &type, sizeof(type)); // DWMWA_SYSTEMBACKDROP_TYPE
				}
			}
		}
		return false;
	}
};

class WindowsPlugin: public QsEnginePlugin {
	QList<QString> dependencies() override { return {"window"}; }

	bool applies() override { return QGuiApplication::platformName() == "windows"; }

	void init() override {
		// FreeForm runs many hidden helpers (PowerShell, Python): if one fails to start, Windows must not pop
		// an error box over the desktop (e.g. "unable to start correctly (0xc0000142)"); FreeForm retries it.
		// Child processes inherit this error mode.
		SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
		QGuiApplication::instance()->installEventFilter(new RoundCorners());
	}

	void registerTypes() override {
		qmlRegisterType<WinPanelInterface>("Quickshell._WindowsOverlay", 1, 0, "PanelWindow");

		qmlRegisterModuleImport(
		    "Quickshell",
		    QQmlModuleImportModuleAny,
		    "Quickshell._WindowsOverlay",
		    QQmlModuleImportLatest
		);
	}
};

QS_REGISTER_PLUGIN(WindowsPlugin);

} // namespace
