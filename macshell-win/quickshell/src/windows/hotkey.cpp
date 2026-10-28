#include "hotkey.hpp"

#include <qabstractnativeeventfilter.h>
#include <qcoreapplication.h>
#include <qhash.h>
#include <qlist.h>
#include <qmetaobject.h>
#include <qlogging.h>
#include <windows.h>

namespace qs::windows {

namespace {

// WM_HOTKEY arrives on the thread's message queue; one filter hands it to the right WinHotkey.
class HotkeyFilter: public QAbstractNativeEventFilter {
public:
	static HotkeyFilter* instance() {
		static auto* filter = []() {
			auto* f = new HotkeyFilter();
			QCoreApplication::instance()->installNativeEventFilter(f);
			return f;
		}();
		return filter;
	}

	bool nativeEventFilter(const QByteArray& /*type*/, void* message, qintptr* /*result*/) override {
		auto* msg = static_cast<MSG*>(message);
		if (msg->message != WM_HOTKEY) return false;
		if (auto* hk = this->byId.value(static_cast<int>(msg->wParam))) {
			hk->trigger();
			return true;
		}
		return false;
	}

	QHash<int, WinHotkey*> byId;
	int next = 0xB000; // app-defined hotkey ids
};

bool parse(const QString& sequence, UINT* mods, UINT* vk) {
	*mods = MOD_NOREPEAT;
	*vk = 0;
	for (auto part: sequence.split('+', Qt::SkipEmptyParts)) {
		auto p = part.trimmed().toLower();
		if (p == "ctrl" || p == "control") *mods |= MOD_CONTROL;
		else if (p == "alt") *mods |= MOD_ALT;
		else if (p == "shift") *mods |= MOD_SHIFT;
		else if (p == "win" || p == "super" || p == "meta") *mods |= MOD_WIN;
		else if (p.length() == 1 && p[0].isLetterOrNumber()) *vk = p[0].toUpper().unicode();
		else if (p.length() >= 2 && p[0] == 'f' && p.mid(1).toInt() >= 1 && p.mid(1).toInt() <= 24)
			*vk = VK_F1 + p.mid(1).toInt() - 1;
		else if (p == "space") *vk = VK_SPACE;
		else if (p == "tab") *vk = VK_TAB;
		else if (p == "enter" || p == "return") *vk = VK_RETURN;
		else if (p == "esc" || p == "escape") *vk = VK_ESCAPE;
		else if (p == "left") *vk = VK_LEFT;
		else if (p == "right") *vk = VK_RIGHT;
		else if (p == "up") *vk = VK_UP;
		else if (p == "down") *vk = VK_DOWN;
		else return false;
	}
	return *vk != 0;
}

} // namespace

WinHotkey::~WinHotkey() { this->unregister(); }

void WinHotkey::componentComplete() {
	this->mComplete = true;
	this->update();
}

void WinHotkey::setSequence(const QString& sequence) {
	if (sequence == this->mSequence) return;
	this->mSequence = sequence;
	emit this->sequenceChanged();
	this->update();
}

void WinHotkey::setEnabled(bool enabled) {
	if (enabled == this->mEnabled) return;
	this->mEnabled = enabled;
	emit this->enabledChanged();
	this->update();
}

void WinHotkey::unregister() {
	if (this->mId == 0) return;
	UnregisterHotKey(nullptr, this->mId);
	HotkeyFilter::instance()->byId.remove(this->mId);
	this->mId = 0;
	emit this->registeredChanged();
}

void WinHotkey::update() {
	if (!this->mComplete) return;
	this->unregister();
	if (!this->mEnabled || this->mSequence.isEmpty()) return;

	UINT mods = 0;
	UINT vk = 0;
	if (!parse(this->mSequence, &mods, &vk)) {
		qWarning() << "WinHotkey: can't understand" << this->mSequence;
		return;
	}

	auto* filter = HotkeyFilter::instance();
	auto id = filter->next++;
	if (!RegisterHotKey(nullptr, id, mods, vk)) {
		qWarning() << "WinHotkey:" << this->mSequence << "is already taken by Windows or another app";
		return;
	}

	this->mId = id;
	filter->byId.insert(id, this);
	emit this->registeredChanged();
}

} // namespace qs::windows

namespace qs::windows {

namespace {

// State of the hook: is Win down, and was anything else pressed while it was?
struct StartKeyHook {
	HHOOK hook = nullptr;
	bool winDown = false;
	bool combo = false;
	QList<WinStartKey*> listeners;

	static StartKeyHook& get() {
		static StartKeyHook h;
		return h;
	}

	static LRESULT CALLBACK proc(int code, WPARAM wParam, LPARAM lParam) {
		auto& h = get();
		if (code != HC_ACTION) return CallNextHookEx(nullptr, code, wParam, lParam);

		auto* kb = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam); // NOLINT
		if (kb->flags & LLKHF_INJECTED) return CallNextHookEx(nullptr, code, wParam, lParam);

		auto isWin = kb->vkCode == VK_LWIN || kb->vkCode == VK_RWIN;
		auto down = wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN;

		if (isWin && down) {
			if (!h.winDown) h.combo = false;
			h.winDown = true;
		} else if (isWin && !down) {
			h.winDown = false;
			if (!h.combo && !h.listeners.isEmpty()) {
				// A key nobody uses between Win down and up: Windows then treats it as a shortcut,
				// not a Start-menu tap (the same trick PowerToys uses).
				// So: swallow this Win-up, then inject dummy-down, dummy-up, Win-up (injected events
				// skip this hook).
				INPUT seq[3] = {}; // NOLINT
				seq[0].type = INPUT_KEYBOARD;
				seq[0].ki.wVk = 0xFF;
				seq[1] = seq[0];
				seq[1].ki.dwFlags = KEYEVENTF_KEYUP;
				seq[2].type = INPUT_KEYBOARD;
				seq[2].ki.wVk = static_cast<WORD>(kb->vkCode);
				seq[2].ki.dwFlags = KEYEVENTF_KEYUP;
				SendInput(3, seq, sizeof(INPUT));
				for (auto* l: h.listeners) QMetaObject::invokeMethod(l, &WinStartKey::trigger, Qt::QueuedConnection);
				return 1;
			}
		} else if (h.winDown && down) {
			h.combo = true; // Win+E, Win+L, Win+Shift+S ... stay Windows'
		}

		return CallNextHookEx(nullptr, code, wParam, lParam);
	}

	void update() {
		auto want = !this->listeners.isEmpty();
		if (want && !this->hook) {
			this->hook = SetWindowsHookExW(WH_KEYBOARD_LL, &StartKeyHook::proc, GetModuleHandleW(nullptr), 0);
			if (!this->hook) qWarning() << "WinStartKey: could not install the keyboard hook";
		} else if (!want && this->hook) {
			UnhookWindowsHookEx(this->hook);
			this->hook = nullptr;
		}
	}
};

} // namespace

WinStartKey::WinStartKey(QObject* parent): QObject(parent) {
	StartKeyHook::get().listeners.append(this);
	StartKeyHook::get().update();
}

WinStartKey::~WinStartKey() {
	StartKeyHook::get().listeners.removeAll(this);
	StartKeyHook::get().update();
}

void WinStartKey::setEnabled(bool enabled) {
	if (enabled == this->mEnabled) return;
	this->mEnabled = enabled;
	auto& h = StartKeyHook::get();
	if (enabled) {
		if (!h.listeners.contains(this)) h.listeners.append(this);
	} else {
		h.listeners.removeAll(this);
	}
	h.update();
	emit this->enabledChanged();
}

} // namespace qs::windows
