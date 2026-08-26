#pragma once
#include <QObject>
#include <QRectF>
class QPdfDocument;
class PdfTextGeometry : public QObject {
    Q_OBJECT
public:
    // QML 侧调用：PdfDocument 项（QQuickPdfDocument）→ QObject* 入参，桥内经
    // qmlExtendedObject 取真实 QPdfDocument（QML_EXTENDED 扩展对象）；原生
    // QPdfDocument* 直接传入时由另一重载处理（C++ 测试路径）。
    Q_INVOKABLE QRectF sentenceBounds(QObject *docObj, int page, int startIndex, int maxLength);
    // C++ 直接调用（单元测试）：字符区间 → 页坐标 points 矩形。
    QRectF sentenceBounds(QPdfDocument *doc, int page, int startIndex, int maxLength);
};
