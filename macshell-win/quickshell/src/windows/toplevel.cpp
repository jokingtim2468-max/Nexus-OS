#include "toplevel.hpp"

#include <dwmapi.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qimage.h>
#include <qguiapplication.h>
#include <qscreen.h>
#include <windows.h>

#include "../core/qmlglobal.hpp"

namespace qs::windows {

namespace {

HWND toHwnd(quintptr hwnd) { return reinterpret_cast<HWND>(hwnd); } // NOLINT

// The windows Explorer's taskbar would show a button for.
bool isAppWindow(HWND hwnd) {
	if (!IsWindowVisible(hwnd)) return false;
	if (GetAncestor(hwnd, GA_ROOT) != hwnd) return false;

	auto exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	if (exStyle & WS_EX_TOOLWINDOW) return false;
	if (GetWindow(hwnd, GW_OWNER) != nullptr && !(exStyle & WS_EX_APPWINDOW)) return false;
	if (exStyle & WS_EX_NOACTIVATE && !(exStyle & WS_EX_APPWINDOW)) return false;

	// Cloaked = on another virtual desktop, or a suspended UWP frame.
	DWORD cloaked = 0;
	DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
	if (cloaked) return false;

	// Our own shell surfaces are not apps.
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (pid == GetCurrentProcessId()) return false;

	return GetWindowTextLengthW(hwnd) > 0;
}

// The equivalent of a Wayland app_id: the executable's base name, lower case
// ("firefox", "code", "explorer"), which the Windows DesktopEntries use as their id too.
QString exePathFor(HWND hwnd) {
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);

	auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!process) return QString();

	wchar_t path[MAX_PATH] = {};
	DWORD size = MAX_PATH;
	auto ok = QueryFullProcessImageNameW(process, 0, path, &size);
	CloseHandle(process);
	if (!ok) return QString();
	return QString::fromWCharArray(path, static_cast<qsizetype>(size));
}

QString appIdFor(HWND hwnd) { return QFileInfo(exePathFor(hwnd)).completeBaseName().toLower(); }

// The app's own icon, saved as %LOCALAPPDATA%\FreeForm\icons\apps\<app id>.png, so apps without
// a Start Menu shortcut (portable tools, games...) still get their real icon in the Dock.
void saveAppIcon(HWND hwnd, const QString& appId) {
	if (appId.isEmpty()) return;
	auto dir = QDir(qEnvironmentVariable("LOCALAPPDATA") + "/FreeForm/icons/apps");
	auto file = dir.filePath(appId + ".png");
	if (QFileInfo::exists(file)) return;

	auto exe = exePathFor(hwnd);
	if (exe.isEmpty()) return;
	HICON icon = nullptr;
	UINT id = 0;
	auto wexe = exe.toStdWString();
	if (PrivateExtractIconsW(wexe.c_str(), 0, 256, 256, &icon, &id, 1, 0) == 0 || icon == nullptr) return;
	auto image = QImage::fromHICON(icon);
	DestroyIcon(icon);
	if (image.isNull()) return;
	dir.mkpath(".");
	image.save(file, "PNG");
}

void CALLBACK winEventProc(
    HWINEVENTHOOK /*hook*/,
    DWORD event,
    HWND hwnd,
    LONG idObject,
    LONG idChild,
    DWORD /*thread*/,
    DWORD /*time*/
) {
	if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF || hwnd == nullptr) return;
	ToplevelManager::instance()->onWindowEvent(reinterpret_cast<quintptr>(hwnd), event); // NOLINT
}

} // namespace

// Toplevel

Toplevel::Toplevel(quintptr hwnd, QObject* parent)
    : QObject(parent)
    , mHwnd(hwnd)
    , mAppId(appIdFor(toHwnd(hwnd))) {
	saveAppIcon(toHwnd(hwnd), this->mAppId);
	this->refresh();
}

void Toplevel::refresh() {
	auto* hwnd = toHwnd(this->mHwnd);

	auto length = GetWindowTextLengthW(hwnd);
	auto buffer = std::wstring(static_cast<size_t>(length) + 1, L'\0');
	GetWindowTextW(hwnd, buffer.data(), length + 1);
	auto title = QString::fromWCharArray(buffer.c_str(), length);
	if (title != this->mTitle) {
		this->mTitle = title;
		emit this->titleChanged();
	}

	auto minimized = IsIconic(hwnd) != 0;
	if (minimized != this->mMinimized) {
		this->mMinimized = minimized;
		emit this->minimizedChanged();
	}

	auto maximized = IsZoomed(hwnd) != 0;
	if (maximized != this->mMaximized) {
		this->mMaximized = maximized;
		emit this->maximizedChanged();
	}

	auto* monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
	MONITORINFO mi = {};
	mi.cbSize = sizeof(MONITORINFO);
	GetMonitorInfoW(monitor, &mi);
	RECT rect = {};
	GetWindowRect(hwnd, &rect);
	auto fullscreen = !minimized && EqualRect(&rect, &mi.rcMonitor)
	               && !(GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_CAPTION);
	if (fullscreen != this->mFullscreen) {
		this->mFullscreen = fullscreen;
		emit this->fullscreenChanged();
	}

	auto monitorId = reinterpret_cast<quintptr>(monitor); // NOLINT
	if (monitorId != this->mMonitor) {
		this->mMonitor = monitorId;
		emit this->screensChanged();
	}
}

void Toplevel::setActivated(bool activated) {
	if (activated == this->mActivated) return;
	this->mActivated = activated;
	emit this->activatedChanged();
}

QList<QuickshellScreenInfo*> Toplevel::screens() const {
	MONITORINFOEXW mi = {};
	mi.cbSize = sizeof(MONITORINFOEXW);
	if (!GetMonitorInfoW(reinterpret_cast<HMONITOR>(this->mMonitor), &mi)) return {}; // NOLINT

	auto name = QString::fromWCharArray(mi.szDevice);
	for (auto* screen: QGuiApplication::screens()) {
		if (screen->name() == name) return {QuickshellTracked::instance()->screenInfo(screen)};
	}

	return {};
}

void Toplevel::activate() {
	auto* hwnd = toHwnd(this->mHwnd);
	if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);

	// Windows only lets the foreground process change the foreground window; a synthetic
	// Alt press is the documented way a shell gets that right.
	INPUT inputs[2] = {}; // NOLINT
	inputs[0].type = INPUT_KEYBOARD;
	inputs[0].ki.wVk = VK_MENU;
	inputs[1].type = INPUT_KEYBOARD;
	inputs[1].ki.wVk = VK_MENU;
	inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
	SendInput(2, inputs, sizeof(INPUT));

	SetForegroundWindow(hwnd);
}

void Toplevel::close() { PostMessageW(toHwnd(this->mHwnd), WM_CLOSE, 0, 0); }

void Toplevel::fullscreenOn(QuickshellScreenInfo* /*screen*/) {
	// No generic fullscreen request on Windows; apps own their fullscreen mode.
	this->setMaximized(true);
}

void Toplevel::setRectangle(QObject* /*window*/, QRect /*rect*/) {
	// Windows animates minimize toward the taskbar button on its own.
}

void Toplevel::unsetRectangle() {}

void Toplevel::setMaximized(bool maximized) {
	ShowWindow(toHwnd(this->mHwnd), maximized ? SW_MAXIMIZE : SW_RESTORE);
}

void Toplevel::setMinimized(bool minimized) {
	ShowWindow(toHwnd(this->mHwnd), minimized ? SW_MINIMIZE : SW_RESTORE);
}

void Toplevel::setFullscreen(bool fullscreen) { this->setMaximized(fullscreen); }

// ToplevelManager

ToplevelManager::ToplevelManager() {
	// Bursts of window events (a new app opening sends dozens) collapse into one rescan.
	this->rescanTimer.setSingleShot(true);
	this->rescanTimer.setInterval(30);
	QObject::connect(&this->rescanTimer, &QTimer::timeout, this, &ToplevelManager::rescan);

	// Out-of-context hooks are delivered through this thread's message loop (Qt's event loop).
	SetWinEventHook(
	    EVENT_SYSTEM_FOREGROUND,
	    EVENT_SYSTEM_MINIMIZEEND,
	    nullptr,
	    winEventProc,
	    0,
	    0,
	    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
	);

	SetWinEventHook(
	    EVENT_OBJECT_DESTROY,
	    EVENT_OBJECT_HIDE,
	    nullptr,
	    winEventProc,
	    0,
	    0,
	    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
	);

	SetWinEventHook(
	    EVENT_OBJECT_LOCATIONCHANGE,
	    EVENT_OBJECT_NAMECHANGE,
	    nullptr,
	    winEventProc,
	    0,
	    0,
	    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
	);

	SetWinEventHook(
	    EVENT_OBJECT_CLOAKED,
	    EVENT_OBJECT_UNCLOAKED,
	    nullptr,
	    winEventProc,
	    0,
	    0,
	    WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
	);

	this->rescan();
}

ToplevelManager* ToplevelManager::instance() {
	static auto* instance = new ToplevelManager(); // NOLINT
	return instance;
}

void ToplevelManager::onWindowEvent(quintptr hwnd, quint32 event) {
	switch (event) {
	case EVENT_SYSTEM_FOREGROUND: this->setForeground(hwnd); break;
	case EVENT_OBJECT_NAMECHANGE:
	case EVENT_OBJECT_LOCATIONCHANGE:
	case EVENT_SYSTEM_MINIMIZESTART:
	case EVENT_SYSTEM_MINIMIZEEND:
		if (auto* toplevel = this->byHwnd.value(hwnd)) toplevel->refresh();
		// a window can become an app window when it gets its title
		if (event == EVENT_OBJECT_NAMECHANGE && !this->byHwnd.contains(hwnd)) this->rescanTimer.start();
		break;
	default: this->rescanTimer.start(); break;
	}
}

void ToplevelManager::setForeground(quintptr hwnd) {
	auto* toplevel = this->byHwnd.value(hwnd);
	if (toplevel == this->mActiveToplevel) return;

	if (this->mActiveToplevel) this->mActiveToplevel->setActivated(false);
	this->mActiveToplevel = toplevel;
	if (toplevel) toplevel->setActivated(true);
	emit this->activeToplevelChanged();
}

void ToplevelManager::rescan() {
	auto found = QList<quintptr>();

	EnumWindows(
	    [](HWND hwnd, LPARAM data) -> BOOL {
		    if (isAppWindow(hwnd)) {
			    reinterpret_cast<QList<quintptr>*>(data)->push_back(reinterpret_cast<quintptr>(hwnd)); // NOLINT
		    }
		    return TRUE;
	    },
	    reinterpret_cast<LPARAM>(&found) // NOLINT
	);

	for (auto it = this->byHwnd.begin(); it != this->byHwnd.end();) {
		if (found.contains(it.key())) {
			++it;
			continue;
		}

		auto* toplevel = it.value();
		it = this->byHwnd.erase(it);
		if (toplevel == this->mActiveToplevel) {
			this->mActiveToplevel = nullptr;
			emit this->activeToplevelChanged();
		}
		this->mToplevels.removeObject(toplevel);
		emit toplevel->closed();
		toplevel->deleteLater();
	}

	// EnumWindows is top-to-bottom z-order; insert oldest-first like the compositor would.
	for (auto i = found.length() - 1; i >= 0; i--) {
		auto hwnd = found.at(i);
		if (this->byHwnd.contains(hwnd)) continue;

		auto* toplevel = new Toplevel(hwnd, this);
		this->byHwnd.insert(hwnd, toplevel);
		this->mToplevels.insertObject(toplevel);
	}

	this->setForeground(reinterpret_cast<quintptr>(GetForegroundWindow())); // NOLINT
}

// ToplevelManagerQml

ToplevelManagerQml::ToplevelManagerQml(QObject* parent): QObject(parent) {
	QObject::connect(
	    ToplevelManager::instance(),
	    &ToplevelManager::activeToplevelChanged,
	    this,
	    &ToplevelManagerQml::activeToplevelChanged
	);
}

ObjectModel<Toplevel>* ToplevelManagerQml::toplevels() {
	return ToplevelManager::instance()->toplevels();
}

Toplevel* ToplevelManagerQml::activeToplevel() {
	return ToplevelManager::instance()->activeToplevel();
}

} // namespace qs::windows
