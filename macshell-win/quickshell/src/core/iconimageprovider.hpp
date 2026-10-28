#pragma once

#include <qpixmap.h>
#include <qquickimageprovider.h>

class IconImageProvider: public QQuickImageProvider {
public:
	explicit IconImageProvider(): QQuickImageProvider(QQuickImageProvider::Pixmap) {}

	QPixmap requestPixmap(const QString& id, QSize* size, const QSize& requestedSize) override;

	static QPixmap missingPixmap(const QSize& size);
	// An icon given as a file path, cleaned up: URL-decoded, and "/D:/x" (from a file:///D:/x URL) -> "D:/x".
	static QString localIconFile(const QString& icon);

	static QString requestString(
	    const QString& icon,
	    const QString& path = QString(),
	    const QString& fallback = QString()
	);
};
