#include "PdfTextGeometry.h"
#include <QPdfDocument>
#include <QPdfSelection>
#include <QtQml/QQmlEngine>

QRectF PdfTextGeometry::sentenceBounds(QPdfDocument *doc, int page, int startIndex, int maxLength) {
    if (!doc || page < 0 || page >= doc->pageCount() || startIndex < 0 || maxLength <= 0)
        return {};
    const QPdfSelection sel = doc->getSelectionAtIndex(page, startIndex, maxLength);
    if (!sel.isValid()) return {};
    return sel.boundingRectangle();
}

QRectF PdfTextGeometry::sentenceBounds(QObject *docObj, int page, int startIndex, int maxLength) {
    // QML 的 PdfDocument 项（QQuickPdfDocument）不能直接转成 QPdfDocument*
    //（QML 引擎报 "Passing incompatible arguments"），其 QML_EXTENDED(QPdfDocument)
    // 扩展对象（qmlExtendedObject）即真实文档实例；非 QML 创建的原生文档兜底
    // qobject_cast 后走 QPdfDocument* 重载。
    QPdfDocument *doc = qobject_cast<QPdfDocument *>(docObj);
    if (!doc && docObj)
        doc = qobject_cast<QPdfDocument *>(qmlExtendedObject(docObj));
    return sentenceBounds(doc, page, startIndex, maxLength);
}
