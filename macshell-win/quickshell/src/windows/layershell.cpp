#include "layershell.hpp"

#include "panel_window.hpp"

namespace qs::windows {

WlrLayershell::WlrLayershell(WinPanelInterface* panel): QObject(panel), panel(panel) {}

void WlrLayershell::setLayer(WlrLayer::Enum layer) {
	if (layer == this->mLayer) return;
	this->mLayer = layer;
	this->panel->setAboveWindows(layer >= WlrLayer::Top);
	this->panel->setLowest(layer == WlrLayer::Background);
	emit this->layerChanged();
}

void WlrLayershell::setNamespace(const QString& ns) {
	if (ns == this->mNamespace) return;
	this->mNamespace = ns;
	emit this->namespaceChanged();
}

void WlrLayershell::setKeyboardFocus(WlrKeyboardFocus::Enum focus) {
	if (focus == this->mKeyboardFocus) return;
	this->mKeyboardFocus = focus;
	this->panel->setFocusable(focus != WlrKeyboardFocus::None);
	emit this->keyboardFocusChanged();
}

WlrLayershell* WlrLayershell::qmlAttachedProperties(QObject* object) {
	auto* panel = qobject_cast<WinPanelInterface*>(object);
	if (!panel) return nullptr;

	auto* existing = panel->findChild<WlrLayershell*>(QString(), Qt::FindDirectChildrenOnly);
	return existing ? existing : new WlrLayershell(panel);
}

#define SETTER(name, type, member, signal)                                                         \
	void ScreencopyView::name(type value) {                                                          \
		if (this->member == value) return;                                                             \
		this->member = value;                                                                          \
		emit this->signal();                                                                           \
	}

SETTER(setCaptureSource, QObject*, mCaptureSource, captureSourceChanged);
SETTER(setPaintCursor, bool, mPaintCursor, paintCursorChanged);
SETTER(setLive, bool, mLive, liveChanged);
SETTER(setConstraintSize, QSizeF, mConstraintSize, constraintSizeChanged);

#undef SETTER

} // namespace qs::windows
