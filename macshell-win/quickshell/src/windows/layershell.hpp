#pragma once

// Windows stand-ins for the rest of Quickshell.Wayland that MacShell uses, so its QML loads
// unchanged: WlrLayershell (attached to PanelWindow), WlrLayer, WlrKeyboardFocus and
// ScreencopyView.

#include <qobject.h>
#include <qpointer.h>
#include <qqmlintegration.h>
#include <qquickitem.h>
#include <qimage.h>
#include <qsize.h>
#include <qsgnode.h>
#include <qtimer.h>
#include <qtmetamacros.h>

class WinPanelInterface;

namespace qs::windows {

namespace WlrLayer { // NOLINT
Q_NAMESPACE;
QML_ELEMENT;

enum Enum : quint8 {
	Background = 0,
	Bottom = 1,
	Top = 2,
	Overlay = 3,
};
Q_ENUM_NS(Enum);

} // namespace WlrLayer

namespace WlrKeyboardFocus { // NOLINT
Q_NAMESPACE;
QML_ELEMENT;

enum Enum : quint8 {
	None = 0,
	Exclusive = 1,
	OnDemand = 2,
};
Q_ENUM_NS(Enum);

} // namespace WlrKeyboardFocus

// Background/Bottom -> stays below app windows, Top/Overlay -> above them.
// Any keyboard focus mode -> the panel can take focus.
class WlrLayershell: public QObject {
	Q_OBJECT;
	// clang-format off
	Q_PROPERTY(qs::windows::WlrLayer::Enum layer READ layer WRITE setLayer NOTIFY layerChanged);
	Q_PROPERTY(QString namespace READ ns WRITE setNamespace NOTIFY namespaceChanged);
	Q_PROPERTY(qs::windows::WlrKeyboardFocus::Enum keyboardFocus READ keyboardFocus WRITE setKeyboardFocus NOTIFY keyboardFocusChanged);
	// clang-format on
	QML_ELEMENT;
	QML_UNCREATABLE("WlrLayershell is only available as an attached property of PanelWindow");
	QML_ATTACHED(WlrLayershell);

public:
	explicit WlrLayershell(WinPanelInterface* panel);

	[[nodiscard]] WlrLayer::Enum layer() const { return this->mLayer; }
	void setLayer(WlrLayer::Enum layer);

	[[nodiscard]] QString ns() const { return this->mNamespace; }
	void setNamespace(const QString& ns);

	[[nodiscard]] WlrKeyboardFocus::Enum keyboardFocus() const { return this->mKeyboardFocus; }
	void setKeyboardFocus(WlrKeyboardFocus::Enum focus);

	static WlrLayershell* qmlAttachedProperties(QObject* object);

signals:
	void layerChanged();
	void namespaceChanged();
	void keyboardFocusChanged();

private:
	WinPanelInterface* panel;
	WlrLayer::Enum mLayer = WlrLayer::Top;
	WlrKeyboardFocus::Enum mKeyboardFocus = WlrKeyboardFocus::None;
	QString mNamespace = "quickshell";
};

// Live picture of an app window (a Toplevel from ToplevelManager) for the Dock's previews,
// Mission Control and the app switcher: PrintWindow(PW_RENDERFULLCONTENT) into an image,
// twice a second while live and visible. Screens are not captured (the picture would contain
// the shell's own glass), so screen sources have no content, which MacShell handles.
class ScreencopyView: public QQuickItem {
	Q_OBJECT;
	// clang-format off
	Q_PROPERTY(QObject* captureSource READ captureSource WRITE setCaptureSource NOTIFY captureSourceChanged);
	Q_PROPERTY(bool paintCursor READ paintCursor WRITE setPaintCursor NOTIFY paintCursorChanged);
	Q_PROPERTY(bool live READ live WRITE setLive NOTIFY liveChanged);
	Q_PROPERTY(bool hasContent READ hasContent NOTIFY hasContentChanged);
	Q_PROPERTY(QSize sourceSize READ sourceSize NOTIFY sourceSizeChanged);
	Q_PROPERTY(QSizeF constraintSize READ constraintSize WRITE setConstraintSize NOTIFY constraintSizeChanged);
	// clang-format on
	QML_ELEMENT;

public:
	explicit ScreencopyView(QQuickItem* parent = nullptr);

	Q_INVOKABLE void captureFrame();

	[[nodiscard]] QObject* captureSource() const { return this->mCaptureSource; }
	void setCaptureSource(QObject* source);
	[[nodiscard]] bool paintCursor() const { return this->mPaintCursor; }
	void setPaintCursor(bool paintCursor);
	[[nodiscard]] bool live() const { return this->mLive; }
	void setLive(bool live);
	[[nodiscard]] bool hasContent() const { return !this->mImage.isNull(); }
	[[nodiscard]] QSize sourceSize() const { return this->mSourceSize; }
	[[nodiscard]] QSizeF constraintSize() const { return this->mConstraintSize; }
	void setConstraintSize(QSizeF size);

signals:
	void captureSourceChanged();
	void paintCursorChanged();
	void liveChanged();
	void hasContentChanged();
	void sourceSizeChanged();
	void constraintSizeChanged();

protected:
	QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;
	void itemChange(ItemChange change, const ItemChangeData& value) override;

private:
	void updateTimer();
	void updateImplicitSize();

	QPointer<QObject> mCaptureSource;
	bool mPaintCursor = false;
	bool mLive = false;
	QSizeF mConstraintSize;
	QImage mImage;
	QSize mSourceSize;
	bool mImageDirty = false;
	QTimer mTimer;
};

} // namespace qs::windows
