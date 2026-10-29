#include "panel_window.hpp"
#include <array>
#include <map>

#include <qevent.h>
#include <qlist.h>
#include <qnamespace.h>
#include <qobject.h>
#include <qqmlengine.h>
#include <qqmllist.h>
#include <qquickwindow.h>
#include <qscreen.h>
#include <qtenvironmentvariables.h>
#include <qtimer.h>
#include <qtmetamacros.h>
#include <qtypes.h>
// clang-format off
#include <windows.h> // must precede shellapi.h
#include <shellapi.h>
// clang-format on

#include "../core/generation.hpp"
#include "../core/qmlscreen.hpp"
#include "../core/types.hpp"
#include "../window/panelinterface.hpp"
#include "../window/proxywindow.hpp"

class WinPanelStack {
public:
	static WinPanelStack* instance() {
		static WinPanelStack* stack = nullptr; // NOLINT

		if (stack == nullptr) {
			stack = new WinPanelStack();
		}

		return stack;
	}

	[[nodiscard]] const QList<WinPanelWindow*>& panels(WinPanelWindow* panel) {
		return this->mPanels[EngineGeneration::findObjectGeneration(panel)];
	}

	void addPanel(WinPanelWindow* panel) {
		panel->engineGeneration = EngineGeneration::findObjectGeneration(panel);
		auto& panels = this->mPanels[panel->engineGeneration];
		if (!panels.contains(panel)) {
			panels.push_back(panel);
		}
	}

	void removePanel(WinPanelWindow* panel) {
		if (!panel->engineGeneration) return;

		auto& panels = this->mPanels[panel->engineGeneration];
		if (panels.removeOne(panel)) {
			if (panels.isEmpty()) {
				this->mPanels.erase(panel->engineGeneration);
			}

			// from the bottom up, update all panels
			for (auto* panel: this->mPanels[panel->engineGeneration]) {
				panel->updateDimensions();
			}
		}
	}

	void updateLowerDimensions(WinPanelWindow* exclude) {
		if (!exclude->engineGeneration) return;
		auto& panels = this->mPanels[exclude->engineGeneration];

		// update all panels lower than the one we start from
		auto found = false;
		for (auto* panel: panels) {
			if (panel == exclude) found = true;
			else if (found) panel->updateDimensions(false);
		}
	}

private:
	std::map<EngineGeneration*, QList<WinPanelWindow*>> mPanels;
};

bool WinPanelEventFilter::eventFilter(QObject* watched, QEvent* event) {
	if (event->type() == QEvent::PlatformSurface) {
		auto* surfaceEvent = static_cast<QPlatformSurfaceEvent*>(event); // NOLINT

		if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
			emit this->surfaceCreated();
		}
	}

	return this->QObject::eventFilter(watched, event);
}

WinPanelWindow::WinPanelWindow(QObject* parent): ProxyWindowBase(parent) {
	QObject::connect(
	    &this->eventFilter,
	    &WinPanelEventFilter::surfaceCreated,
	    this,
	    &WinPanelWindow::nativeInit
	);

	this->bcExclusiveZone.setBinding([this]() -> qint32 {
		switch (this->bExclusionMode.value()) {
		case ExclusionMode::Ignore: return 0;
		case ExclusionMode::Normal: return this->bExclusiveZone;
		case ExclusionMode::Auto:
			auto edge = this->bcExclusionEdge.value();
			auto margins = this->bMargins.value();

			if (edge == Qt::TopEdge || edge == Qt::BottomEdge) {
				return this->bImplicitHeight + margins.top + margins.bottom;
			} else if (edge == Qt::LeftEdge || edge == Qt::RightEdge) {
				return this->bImplicitWidth + margins.left + margins.right;
			} else {
				return 0;
			}
		}

		return 0;
	});

	this->bcExclusionEdge.setBinding([this] { return this->bAnchors.value().exclusionEdge(); });
}

WinPanelWindow::~WinPanelWindow() {
	this->removeAppBar();
	WinPanelStack::instance()->removePanel(this);
}

void WinPanelWindow::connectWindow() {
	this->ProxyWindowBase::connectWindow();

	this->window->installEventFilter(&this->eventFilter);
	this->updateScreen();

	QObject::connect(
	    this->window,
	    &QQuickWindow::visibleChanged,
	    this,
	    &WinPanelWindow::updatePanelStack
	);
	// a panel that wants the keyboard (Spotlight, Launchpad) takes it as soon as it's shown
	QObject::connect(this->window, &QQuickWindow::visibleChanged, this, [this]() {
		if (this->mGrabFocus && this->window->isVisible()) this->takeFocus();
	});

	this->window->setFlag(Qt::FramelessWindowHint);
	this->window->setProperty("qsPanel", true); // not an app window: no rounded corners (init.cpp)
	this->updateAboveWindows();
	this->updateFocusable();

	if (this->window->handle() != nullptr) {
		this->nativeInit();
		this->updatePanelStack();
	}
}

void WinPanelWindow::trySetWidth(qint32 implicitWidth) {
	// only update the actual size if not blocked by anchors
	if (!this->bAnchors.value().horizontalConstraint()) {
		this->ProxyWindowBase::trySetWidth(implicitWidth);
		this->updateDimensions();
	}
}

void WinPanelWindow::trySetHeight(qint32 implicitHeight) {
	// only update the actual size if not blocked by anchors
	if (!this->bAnchors.value().verticalConstraint()) {
		this->ProxyWindowBase::trySetHeight(implicitHeight);
		this->updateDimensions();
	}
}

void WinPanelWindow::setScreen(QuickshellScreenInfo* screen) {
	this->ProxyWindowBase::setScreen(screen);
	this->updateScreen();
}

void WinPanelWindow::nativeInit() {
	if (this->window == nullptr || this->window->handle() == nullptr) return;

	// Like a dock window on X11: no taskbar button and no Alt+Tab entry.
	auto* hwnd = reinterpret_cast<HWND>(this->window->winId()); // NOLINT
	auto exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	exStyle = (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
	SetWindowLongPtrW(hwnd, GWL_EXSTYLE, exStyle);
	this->appBarHwnd = reinterpret_cast<quintptr>(hwnd); // NOLINT

	this->updateFocusable();
	this->updateDimensions();
	// TODO(windows): pin to all virtual desktops (IVirtualDesktopPinnedApps).
}

void WinPanelWindow::updateScreen() {
	auto* newScreen =
	    this->mScreen ? this->mScreen : (this->window ? this->window->screen() : nullptr);

	if (newScreen == this->mTrackedScreen) return;

	if (this->mTrackedScreen != nullptr) {
		QObject::disconnect(this->mTrackedScreen, nullptr, this, nullptr);
	}

	this->mTrackedScreen = newScreen;

	if (this->mTrackedScreen != nullptr) {
		QObject::connect(
		    this->mTrackedScreen,
		    &QScreen::geometryChanged,
		    this,
		    &WinPanelWindow::updateDimensionsSlot
		);

		QObject::connect(
		    this->mTrackedScreen,
		    &QScreen::virtualGeometryChanged,
		    this,
		    &WinPanelWindow::onScreenVirtualGeometryChanged
		);
	}

	this->updateDimensions();
}

// For some reason this gets sent multiple times with the same value.
void WinPanelWindow::onScreenVirtualGeometryChanged() {
	auto geometry = this->mTrackedScreen->virtualGeometry();
	if (geometry != this->lastScreenVirtualGeometry) {
		this->lastScreenVirtualGeometry = geometry;
		this->updateStrut(false);
	}
}

void WinPanelWindow::updateDimensionsSlot() { this->updateDimensions(); }

void WinPanelWindow::updateDimensions(bool propagate) {
	if (this->window == nullptr || this->window->handle() == nullptr
	    || this->mTrackedScreen == nullptr)
		return;

	auto screenGeometry = this->mTrackedScreen->geometry();

	if (this->bExclusionMode != ExclusionMode::Ignore) {
		for (auto* panel: WinPanelStack::instance()->panels(this)) {
			// we only care about windows below us
			if (panel == this) break;

			// we only care about windows in the same layer
			if (panel->bAboveWindows != this->bAboveWindows) continue;

			if (panel->mTrackedScreen != this->mTrackedScreen) continue;

			auto edge = panel->bcExclusionEdge.value();
			auto exclusiveZone = panel->bcExclusiveZone.value();

			screenGeometry.adjust(
			    edge == Qt::LeftEdge ? exclusiveZone : 0,
			    edge == Qt::TopEdge ? exclusiveZone : 0,
			    edge == Qt::RightEdge ? -exclusiveZone : 0,
			    edge == Qt::BottomEdge ? -exclusiveZone : 0
			);
		}
	}

	auto geometry = QRect();

	auto anchors = this->bAnchors.value();
	auto margins = this->bMargins.value();

	if (anchors.horizontalConstraint()) {
		geometry.setX(screenGeometry.x() + margins.left);
		geometry.setWidth(screenGeometry.width() - margins.left - margins.right);
	} else {
		if (anchors.mLeft) {
			geometry.setX(screenGeometry.x() + margins.left);
		} else if (anchors.mRight) {
			geometry.setX(
			    screenGeometry.x() + screenGeometry.width() - this->implicitWidth() - margins.right
			);
		} else {
			geometry.setX(screenGeometry.x() + screenGeometry.width() / 2 - this->implicitWidth() / 2);
		}

		geometry.setWidth(this->implicitWidth());
	}

	if (anchors.verticalConstraint()) {
		geometry.setY(screenGeometry.y() + margins.top);
		geometry.setHeight(screenGeometry.height() - margins.top - margins.bottom);
	} else {
		if (anchors.mTop) {
			geometry.setY(screenGeometry.y() + margins.top);
		} else if (anchors.mBottom) {
			geometry.setY(
			    screenGeometry.y() + screenGeometry.height() - this->implicitHeight() - margins.bottom
			);
		} else {
			geometry.setY(screenGeometry.y() + screenGeometry.height() / 2 - this->implicitHeight() / 2);
		}

		geometry.setHeight(this->implicitHeight());
	}

	this->window->setGeometry(geometry);
	this->updateStrut(propagate);
}

void WinPanelWindow::updatePanelStack() {
	if (this->window->isVisible()) {
		WinPanelStack::instance()->addPanel(this);
		this->updateStrut();
	} else {
		this->removeAppBar();
		WinPanelStack::instance()->removePanel(this);
	}
}

// Windows equivalent of _NET_WM_STRUT: register the panel as an AppBar so the shell reserves
// its edge and maximized windows stop at it (the same mechanism the Windows taskbar uses).
void WinPanelWindow::updateStrut(bool propagate) {
	if (this->window == nullptr || this->window->handle() == nullptr) return;

	auto edge = this->bcExclusionEdge.value();
	auto exclusiveZone = this->bcExclusiveZone.value();

	if (edge == 0 || exclusiveZone <= 0 || this->bExclusionMode == ExclusionMode::Ignore
	    || !this->window->isVisible())
	{
		this->removeAppBar();
		if (propagate) WinPanelStack::instance()->updateLowerDimensions(this);
		return;
	}

	auto* hwnd = reinterpret_cast<HWND>(this->window->winId()); // NOLINT
	this->appBarHwnd = reinterpret_cast<quintptr>(hwnd);        // NOLINT

	APPBARDATA abd = {};
	abd.cbSize = sizeof(APPBARDATA);
	abd.hWnd = hwnd;

	if (!this->appBarRegistered) {
		this->appBarRegistered = SHAppBarMessage(ABM_NEW, &abd) != 0;
		if (!this->appBarRegistered) return;
	}

	// AppBar rects are in physical pixels; Qt geometry is device independent.
	auto* monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
	MONITORINFO mi = {};
	mi.cbSize = sizeof(MONITORINFO);
	GetMonitorInfoW(monitor, &mi);
	auto zone = static_cast<LONG>(exclusiveZone * this->window->devicePixelRatio());

	abd.rc = mi.rcMonitor;
	switch (edge) {
	case Qt::LeftEdge:
		abd.uEdge = ABE_LEFT;
		abd.rc.right = abd.rc.left + zone;
		break;
	case Qt::RightEdge:
		abd.uEdge = ABE_RIGHT;
		abd.rc.left = abd.rc.right - zone;
		break;
	case Qt::TopEdge:
		abd.uEdge = ABE_TOP;
		abd.rc.bottom = abd.rc.top + zone;
		break;
	case Qt::BottomEdge:
		abd.uEdge = ABE_BOTTOM;
		abd.rc.top = abd.rc.bottom - zone;
		break;
	default: break;
	}

	SHAppBarMessage(ABM_QUERYPOS, &abd);
	SHAppBarMessage(ABM_SETPOS, &abd);

	if (propagate) WinPanelStack::instance()->updateLowerDimensions(this);
}

void WinPanelWindow::removeAppBar() {
	if (!this->appBarRegistered) return;

	APPBARDATA abd = {};
	abd.cbSize = sizeof(APPBARDATA);
	abd.hWnd = reinterpret_cast<HWND>(this->appBarHwnd); // NOLINT
	SHAppBarMessage(ABM_REMOVE, &abd);
	this->appBarRegistered = false;
}

void WinPanelWindow::updateAboveWindows() {
	if (this->window == nullptr) return;

	auto above = this->bAboveWindows.value();
	// No Qt::WindowStaysOnBottomHint: Qt implements it with HWND_BOTTOM, which is *under* Explorer's
	// desktop window, so desktop panels were hidden behind it. keepOnDesktop() places them instead.
	this->window->setFlag(Qt::WindowStaysOnBottomHint, false);
	this->window->setFlag(Qt::WindowStaysOnTopHint, above);

	if (!above) {
		this->lowestTimer.setInterval(500);
		QObject::connect(&this->lowestTimer, &QTimer::timeout, this, &WinPanelWindow::pushToBottom, Qt::UniqueConnection);
		this->lowestTimer.start();
		this->pushToBottom();
	} else {
		this->lowestTimer.stop();
	}
}

void WinPanelWindow::setLowest(bool lowest) {
	if (lowest == this->mLowest) return;
	this->mLowest = lowest;
	this->pushToBottom();
}

namespace {
HWND gBackgroundPanel = nullptr; // FreeForm's desktop layer (the "lowest" panel)

// Place hwnd directly above anchor in the z-order (below every app window that is above anchor).
void placeAbove(HWND hwnd, HWND anchor) {
	if (anchor == nullptr || hwnd == anchor) return;
	auto* prev = GetWindow(anchor, GW_HWNDPREV); // the window right above the anchor
	if (prev == hwnd) return;                    // already there
	SetWindowPos(
	    hwnd,
	    prev != nullptr ? prev : HWND_TOP,
	    0,
	    0,
	    0,
	    0,
	    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
	);
}
} // namespace

// Desktop panels (below the app windows): the desktop layer right above Explorer's desktop
// window, widgets right above the desktop layer. Re-checked twice a second, since clicking
// one or Explorer redrawing its desktop can reorder them.
// is hwnd stacked above anchor, with only FreeForm's own windows in between? (walk down the z-order from
// hwnd looking for anchor; meeting another program's visible window first means hwnd sits above that app,
// e.g. a freshly opened panel starts on top of everything, so it must be put back down)
bool isAbove(HWND hwnd, HWND anchor) {
	if (anchor == nullptr) return true;
	auto self = GetCurrentProcessId();
	auto* w = GetWindow(hwnd, GW_HWNDNEXT);
	for (int i = 0; w != nullptr && i < 4096; i++, w = GetWindow(w, GW_HWNDNEXT)) {
		if (w == anchor) return true;
		DWORD pid = 0;
		GetWindowThreadProcessId(w, &pid);
		if (pid != self && IsWindowVisible(w) && !(GetWindowLongW(w, GWL_EXSTYLE) & WS_EX_TOOLWINDOW)) return false;
	}
	return false;
}

void WinPanelWindow::pushToBottom() {
	if (this->window == nullptr || this->window->handle() == nullptr || !this->window->isVisible()) return;
	auto* hwnd = reinterpret_cast<HWND>(this->window->winId()); // NOLINT
	auto* desktop = FindWindowW(L"Progman", nullptr);
	if (this->mLowest) {
		gBackgroundPanel = hwnd;
		if (!isAbove(hwnd, desktop)) placeAbove(hwnd, desktop);       // (one per screen: don't make them swap)
	} else {
		auto* anchor = gBackgroundPanel != nullptr && IsWindow(gBackgroundPanel) ? gBackgroundPanel : desktop;
		// already somewhere above the desktop layer: leave it. Re-placing each widget "right above" the
		// layer made several widgets swap places every tick, which flickered.
		if (isAbove(hwnd, anchor)) return;
		placeAbove(hwnd, anchor);
	}
}

void WinPanelWindow::updateFocusable() {
	if (this->window == nullptr) return;
	this->window->setFlag(Qt::WindowDoesNotAcceptFocus, !this->bFocusable);

	// Clicking a non-focusable panel must not steal focus from the app underneath.
	if (this->window->handle() == nullptr) return;
	auto* hwnd = reinterpret_cast<HWND>(this->window->winId()); // NOLINT
	auto exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	if (this->bFocusable) exStyle &= ~WS_EX_NOACTIVATE;
	else exStyle |= WS_EX_NOACTIVATE;
	SetWindowLongPtrW(hwnd, GWL_EXSTYLE, exStyle);

	if (this->mGrabFocus && this->window->isVisible()) this->takeFocus();
}

void WinPanelWindow::setGrabFocus(bool grab) {
	if (grab == this->mGrabFocus) return;
	this->mGrabFocus = grab;
	if (grab && this->window != nullptr && this->window->isVisible()) this->takeFocus();
}

void WinPanelWindow::takeFocus() {
	if (this->window == nullptr || this->window->handle() == nullptr) return;
	auto* hwnd = reinterpret_cast<HWND>(this->window->winId()); // NOLINT
	if (GetForegroundWindow() == hwnd) return;

	// Windows only lets the app in front hand over the keyboard. Joining its input queue for a
	// moment makes us part of it, so the panel really gets focus (without this, typing after
	// pressing Win went on into the app underneath).
	auto* fg = GetForegroundWindow();
	auto fgThread = fg != nullptr ? GetWindowThreadProcessId(fg, nullptr) : 0;
	auto ourThread = GetCurrentThreadId();
	auto attached = fgThread != 0 && fgThread != ourThread && AttachThreadInput(ourThread, fgThread, TRUE);
	SetForegroundWindow(hwnd);
	BringWindowToTop(hwnd);
	SetFocus(hwnd);
	if (attached) AttachThreadInput(ourThread, fgThread, FALSE);
	this->window->requestActivate();
}

// WinPanelInterface

WinPanelInterface::WinPanelInterface(QObject* parent)
    : PanelWindowInterface(parent)
    , panel(new WinPanelWindow(this)) {
	this->connectSignals();

	// clang-format off
	QObject::connect(this->panel, &WinPanelWindow::anchorsChanged, this, &WinPanelInterface::anchorsChanged);
	QObject::connect(this->panel, &WinPanelWindow::marginsChanged, this, &WinPanelInterface::marginsChanged);
	QObject::connect(this->panel, &WinPanelWindow::exclusiveZoneChanged, this, &WinPanelInterface::exclusiveZoneChanged);
	QObject::connect(this->panel, &WinPanelWindow::exclusionModeChanged, this, &WinPanelInterface::exclusionModeChanged);
	QObject::connect(this->panel, &WinPanelWindow::aboveWindowsChanged, this, &WinPanelInterface::aboveWindowsChanged);
	QObject::connect(this->panel, &WinPanelWindow::focusableChanged, this, &WinPanelInterface::focusableChanged);
	// clang-format on
}

void WinPanelInterface::onReload(QObject* oldInstance) {
	QQmlEngine::setContextForObject(this->panel, QQmlEngine::contextForObject(this));

	auto* old = qobject_cast<WinPanelInterface*>(oldInstance);
	this->panel->reload(old != nullptr ? old->panel : nullptr);
}

ProxyWindowBase* WinPanelInterface::proxyWindow() const { return this->panel; }

// NOLINTBEGIN
#define proxyPair(type, get, set)                                                                  \
	type WinPanelInterface::get() const { return this->panel->get(); }                                 \
	void WinPanelInterface::set(type value) { this->panel->set(value); }

proxyPair(Anchors, anchors, setAnchors);
proxyPair(Margins, margins, setMargins);
proxyPair(qint32, exclusiveZone, setExclusiveZone);
proxyPair(ExclusionMode::Enum, exclusionMode, setExclusionMode);
proxyPair(bool, focusable, setFocusable);
proxyPair(bool, aboveWindows, setAboveWindows);

#undef proxyPair
// NOLINTEND
