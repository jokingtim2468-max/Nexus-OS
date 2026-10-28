#include "layershell.hpp"

#include <windows.h>
#include <dwmapi.h>

#include <qquickwindow.h>
#include <qsgimagenode.h>
#include <qsgtexture.h>

#include "toplevel.hpp"

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

ScreencopyView::ScreencopyView(QQuickItem* parent): QQuickItem(parent) {
	this->setFlag(QQuickItem::ItemHasContents);
	this->mTimer.setInterval(500);
	QObject::connect(&this->mTimer, &QTimer::timeout, this, &ScreencopyView::captureFrame);
}

void ScreencopyView::setCaptureSource(QObject* source) {
	if (source == this->mCaptureSource) return;
	this->mCaptureSource = source;
	emit this->captureSourceChanged();
	if (!this->mImage.isNull()) {
		this->mImage = QImage();
		this->mImageDirty = true;
		emit this->hasContentChanged();
		this->update();
	}
	this->captureFrame();
	this->updateTimer();
}

void ScreencopyView::setLive(bool live) {
	if (live == this->mLive) return;
	this->mLive = live;
	emit this->liveChanged();
	this->updateTimer();
}

void ScreencopyView::setPaintCursor(bool paintCursor) {
	if (paintCursor == this->mPaintCursor) return;
	this->mPaintCursor = paintCursor;
	emit this->paintCursorChanged();
}

void ScreencopyView::setConstraintSize(QSizeF size) {
	if (size == this->mConstraintSize) return;
	this->mConstraintSize = size;
	emit this->constraintSizeChanged();
	this->updateImplicitSize();
}

void ScreencopyView::itemChange(ItemChange change, const ItemChangeData& value) {
	QQuickItem::itemChange(change, value);
	if (change == ItemVisibleHasChanged || change == ItemSceneChange) {
		if (this->isVisible() && this->mImage.isNull()) this->captureFrame();
		this->updateTimer();
	}
}

void ScreencopyView::updateTimer() {
	auto want = this->mLive && this->mCaptureSource != nullptr && this->isVisible() && this->window() != nullptr;
	if (want && !this->mTimer.isActive()) this->mTimer.start();
	else if (!want) this->mTimer.stop();
}

void ScreencopyView::captureFrame() {
	auto* toplevel = qobject_cast<Toplevel*>(this->mCaptureSource.data());
	if (toplevel == nullptr || !this->isVisible()) return;

	auto* hwnd = reinterpret_cast<HWND>(toplevel->hwnd()); // NOLINT
	if (!IsWindow(hwnd) || IsIconic(hwnd)) return; // minimized: keep the last picture

	RECT wr;
	if (!GetWindowRect(hwnd, &wr)) return;
	// the visible frame, without the invisible resize borders Windows 10/11 add around windows
	RECT fr = wr;
	DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &fr, sizeof(fr));
	auto w = wr.right - wr.left;
	auto h = wr.bottom - wr.top;
	if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return;

	BITMAPINFO bi = {};
	bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bi.bmiHeader.biWidth = w;
	bi.bmiHeader.biHeight = -h; // top-down
	bi.bmiHeader.biPlanes = 1;
	bi.bmiHeader.biBitCount = 32;
	bi.bmiHeader.biCompression = BI_RGB;
	void* bits = nullptr;
	auto* screenDc = GetDC(nullptr);
	auto* dc = CreateCompatibleDC(screenDc);
	auto* bmp = CreateDIBSection(screenDc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
	ReleaseDC(nullptr, screenDc);
	if (bmp == nullptr || bits == nullptr) {
		DeleteDC(dc);
		return;
	}
	auto* old = SelectObject(dc, bmp);
	auto ok = PrintWindow(hwnd, dc, 0x2 /* PW_RENDERFULLCONTENT */);
	GdiFlush();

	if (ok) {
		auto full = QImage(static_cast<const uchar*>(bits), w, h, w * 4, QImage::Format_RGB32);
		auto crop = QRect(fr.left - wr.left, fr.top - wr.top, fr.right - fr.left, fr.bottom - fr.top).intersected(full.rect());
		auto img = full.copy(crop.isEmpty() ? full.rect() : crop);
		if (img.width() > 960) img = img.scaledToWidth(960, Qt::SmoothTransformation);

		auto hadContent = !this->mImage.isNull();
		auto sizeChanged = crop.size() != this->mSourceSize;
		this->mSourceSize = crop.isEmpty() ? QSize(w, h) : crop.size();
		this->mImage = img;
		this->mImageDirty = true;
		if (sizeChanged) {
			emit this->sourceSizeChanged();
			this->updateImplicitSize();
		}
		if (!hadContent) emit this->hasContentChanged();
		this->update();
	}

	SelectObject(dc, old);
	DeleteObject(bmp);
	DeleteDC(dc);
}

void ScreencopyView::updateImplicitSize() {
	auto size = QSizeF(this->mSourceSize);
	if (size.isEmpty()) return;
	if (this->mConstraintSize.isValid() && !this->mConstraintSize.isEmpty()) {
		size = size.scaled(this->mConstraintSize, Qt::KeepAspectRatio);
	}
	this->setImplicitSize(size.width(), size.height());
}

QSGNode* ScreencopyView::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* /*data*/) {
	auto* node = static_cast<QSGImageNode*>(oldNode); // NOLINT
	if (this->mImage.isNull() || this->window() == nullptr) {
		delete node;
		return nullptr;
	}
	if (node == nullptr) {
		node = this->window()->createImageNode();
		node->setOwnsTexture(true);
		node->setFiltering(QSGTexture::Linear);
		this->mImageDirty = true;
	}
	if (this->mImageDirty) {
		node->setTexture(this->window()->createTextureFromImage(this->mImage));
		this->mImageDirty = false;
	}
	node->setRect(this->boundingRect());
	return node;
}

} // namespace qs::windows
