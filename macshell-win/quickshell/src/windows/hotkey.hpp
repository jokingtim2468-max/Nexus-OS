#pragma once

// WinHotkey — a system-wide keyboard shortcut on Windows (RegisterHotKey), for QML:
//   WinHotkey { sequence: "Alt+Space"; onPressed: spotlight.toggle() }
// Modifiers: Ctrl, Alt, Shift, Win. Keys: A-Z, 0-9, F1-F24, Space, Tab, Enter, Esc, Left/Right/Up/Down.

#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmlparserstatus.h>
#include <qtmetamacros.h>

namespace qs::windows {

class WinHotkey: public QObject, public QQmlParserStatus {
	Q_OBJECT;
	Q_INTERFACES(QQmlParserStatus);
	Q_PROPERTY(QString sequence READ sequence WRITE setSequence NOTIFY sequenceChanged);
	Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged);
	/// False when Windows (or another app) already owns this shortcut.
	Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged);
	QML_ELEMENT;

public:
	explicit WinHotkey(QObject* parent = nullptr): QObject(parent) {}
	~WinHotkey() override;

	void classBegin() override {}
	void componentComplete() override;

	[[nodiscard]] QString sequence() const { return this->mSequence; }
	void setSequence(const QString& sequence);
	[[nodiscard]] bool enabled() const { return this->mEnabled; }
	void setEnabled(bool enabled);
	[[nodiscard]] bool registered() const { return this->mId != 0; }

	void trigger() { emit this->pressed(); }

signals:
	void pressed();
	void sequenceChanged();
	void enabledChanged();
	void registeredChanged();

private:
	void update();
	void unregister();

	QString mSequence;
	bool mEnabled = true;
	bool mComplete = false;
	int mId = 0;
};

} // namespace qs::windows

namespace qs::windows {

// WinStartKey — takes over the Start menu key: pressing and releasing Win on its own emits
// pressed() instead of opening Start; Win+<key> shortcuts keep working. One low-level keyboard
// hook for the process, removed when the last WinStartKey goes away or is disabled.
//   WinStartKey { onPressed: launchpad.toggle() }
class WinStartKey: public QObject {
	Q_OBJECT;
	Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged);
	QML_ELEMENT;

public:
	explicit WinStartKey(QObject* parent = nullptr);
	~WinStartKey() override;

	[[nodiscard]] bool enabled() const { return this->mEnabled; }
	void setEnabled(bool enabled);

	void trigger() { emit this->pressed(); }

signals:
	void pressed();
	void enabledChanged();

private:
	bool mEnabled = true;
};

/// Alt+Tab / Alt+Shift+Tab, taken over from Windows' switcher while this object exists.
/// next()/prev() on each Tab, commit() when Alt is let go, cancel() on Esc.
class WinAltTab: public QObject {
	Q_OBJECT;
	Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged);
	QML_ELEMENT;

public:
	explicit WinAltTab(QObject* parent = nullptr);
	~WinAltTab() override;

	[[nodiscard]] bool enabled() const { return this->mEnabled; }
	void setEnabled(bool enabled);

	void emitNext() { emit this->next(); }
	void emitPrev() { emit this->prev(); }
	void emitCommit() { emit this->commit(); }
	void emitCancel() { emit this->cancel(); }

signals:
	void next();
	void prev();
	void commit();
	void cancel();
	void enabledChanged();

private:
	bool mEnabled = true;
};

} // namespace qs::windows
