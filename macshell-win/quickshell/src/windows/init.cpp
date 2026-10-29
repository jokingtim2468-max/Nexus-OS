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
			}
		}
		return false;
	}
};

class WindowsPlugin: public QsEnginePlugin {
	QList<QString> dependencies() override { return {"window"}; }

	bool applies() override { return QGuiApplication::platformName() == "windows"; }

	void init() override { QGuiApplication::instance()->installEventFilter(new RoundCorners()); }

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
