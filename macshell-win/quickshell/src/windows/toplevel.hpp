#pragma once

// Windows implementation of Quickshell.Wayland's ToplevelManager: the list of open app
// windows (for the Dock, Alt+Tab, the menu bar's app name), backed by Win32 instead of
// zwlr_foreign_toplevel_manager_v1. Same QML API as ../wayland/toplevel/qml.hpp.

#include <qhash.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qtimer.h>
#include <qtmetamacros.h>

#include "../core/model.hpp"
#include "../core/qmlscreen.hpp"

namespace qs::windows {

class Toplevel: public QObject {
	Q_OBJECT;
	Q_PROPERTY(QString appId READ appId NOTIFY appIdChanged);
	Q_PROPERTY(QString title READ title NOTIFY titleChanged);
	Q_PROPERTY(qs::windows::Toplevel* parent READ parent NOTIFY parentChanged);
	Q_PROPERTY(bool activated READ activated NOTIFY activatedChanged);
	Q_PROPERTY(QList<QuickshellScreenInfo*> screens READ screens NOTIFY screensChanged);
	Q_PROPERTY(bool maximized READ maximized WRITE setMaximized NOTIFY maximizedChanged);
	Q_PROPERTY(bool minimized READ minimized WRITE setMinimized NOTIFY minimizedChanged);
	Q_PROPERTY(bool fullscreen READ fullscreen WRITE setFullscreen NOTIFY fullscreenChanged);
	QML_ELEMENT;
	QML_UNCREATABLE("Toplevels must be acquired from the ToplevelManager.");

public:
	explicit Toplevel(quintptr hwnd, QObject* parent);

	Q_INVOKABLE void activate();
	Q_INVOKABLE void close();
	Q_INVOKABLE void fullscreenOn(QuickshellScreenInfo* screen);
	Q_INVOKABLE void setRectangle(QObject* window, QRect rect);
	Q_INVOKABLE void unsetRectangle();

	[[nodiscard]] QString appId() const { return this->mAppId; }
	[[nodiscard]] QString title() const { return this->mTitle; }
	[[nodiscard]] Toplevel* parent() const { return nullptr; }
	[[nodiscard]] bool activated() const { return this->mActivated; }
	[[nodiscard]] QList<QuickshellScreenInfo*> screens() const;

	[[nodiscard]] bool maximized() const { return this->mMaximized; }
	void setMaximized(bool maximized);
	[[nodiscard]] bool minimized() const { return this->mMinimized; }
	void setMinimized(bool minimized);
	[[nodiscard]] bool fullscreen() const { return this->mFullscreen; }
	void setFullscreen(bool fullscreen);

	[[nodiscard]] quintptr hwnd() const { return this->mHwnd; }

	// Re-reads title, state and screen from the window.
	void refresh();
	void setActivated(bool activated);

signals:
	void closed();
	void appIdChanged();
	void titleChanged();
	void parentChanged();
	void activatedChanged();
	void screensChanged();
	void maximizedChanged();
	void minimizedChanged();
	void fullscreenChanged();

private:
	quintptr mHwnd;
	quintptr mMonitor = 0;
	QString mAppId;
	QString mTitle;
	bool mActivated = false;
	bool mMaximized = false;
	bool mMinimized = false;
	bool mFullscreen = false;
};

class ToplevelManager: public QObject {
	Q_OBJECT;

public:
	[[nodiscard]] ObjectModel<Toplevel>* toplevels() { return &this->mToplevels; }
	[[nodiscard]] Toplevel* activeToplevel() const { return this->mActiveToplevel; }

	static ToplevelManager* instance();

	// Called from the WinEvent hook.
	void onWindowEvent(quintptr hwnd, quint32 event);

signals:
	void activeToplevelChanged();

private slots:
	void rescan();

private:
	explicit ToplevelManager();
	void setForeground(quintptr hwnd);

	ObjectModel<Toplevel> mToplevels {this};
	QHash<quintptr, Toplevel*> byHwnd;
	Toplevel* mActiveToplevel = nullptr;
	QTimer rescanTimer;
};

class ToplevelManagerQml: public QObject {
	Q_OBJECT;
	// clang-format off
	Q_PROPERTY(UntypedObjectModel* toplevels READ toplevels CONSTANT);
	Q_PROPERTY(qs::windows::Toplevel* activeToplevel READ activeToplevel NOTIFY activeToplevelChanged);
	// clang-format on
	QML_NAMED_ELEMENT(ToplevelManager);
	QML_SINGLETON;

public:
	explicit ToplevelManagerQml(QObject* parent = nullptr);

	[[nodiscard]] static ObjectModel<Toplevel>* toplevels();
	[[nodiscard]] static Toplevel* activeToplevel();

signals:
	void activeToplevelChanged();
};

} // namespace qs::windows
