#include "hotkey.hpp"

#include <qabstractnativeeventfilter.h>
#include <qcoreapplication.h>
#include <qhash.h>
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
