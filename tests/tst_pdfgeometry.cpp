// 任务4：PDF 朗读逐句高亮 C++ 桥（PdfTextGeometry）测试。
// 确定性两页文本 PDF 夹具（QPdfWriter 生成，同 tst_qmlmain.cpp 的 writeTextPdf）：
// 第 0 页 drawText 一句含两个句号的长串；桥的 sentenceBounds 把字符区间
// （getSelectionAtIndex 的 startIndex/maxLength，即 getAllText 的字符偏移）
// 映射为页坐标 points 矩形。
#include <QtTest>
#include <QFont>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QTemporaryDir>
#include <QtPdf/QPdfDocument>
#include <QtPdf/QPdfSelection>

#include "ui/PdfTextGeometry.h"

namespace {

// 与 tst_qmlmain.cpp::writeTextPdf 同构：两页 A4，每页一句 drawText（两个句子）。
// 页 0 文本："第一页第一句，用于PDF文本朗读验证。第一页第二句，紧随其后。"
bool writeFixture(const QString &path) {
    QPdfWriter writer(path);
    writer.setPageSize(QPageSize(QPageSize::A4));
    writer.setResolution(300);
    QPainter painter(&writer);
    if (!painter.isActive()) return false;
    QFont font = painter.font();
    font.setFamily(QStringLiteral("PingFang SC"));
    font.setPointSize(24);
    painter.setFont(font);
    painter.drawText(120, 180, QString::fromUtf8("第一页第一句，用于PDF文本朗读验证。第一页第二句，紧随其后。"));
    writer.newPage();
    painter.drawText(120, 180, QString::fromUtf8("第二页第一句，属于第二页内容。第二页第二句，读完即停。"));
    painter.end();
    return QFile::exists(path);
}

// 加载并等待 Ready（QPdfDocument::load 是异步的，Ready 由后台线程发出）
QPdfDocument *loadReady(const QString &path) {
    auto *doc = new QPdfDocument;
    doc->load(path);
    for (int i = 0; i < 200 && doc->status() != QPdfDocument::Status::Ready; ++i)
        QTest::qWait(50);   // 最多 10s
    return doc;
}

} // namespace

class TestPdfGeometry : public QObject {
    Q_OBJECT
private slots:
    // 核心契约：字符区间 → 页坐标矩形（points），合法区间返回有效矩形
    void sentenceBoundsReturnsRect();
    // 选区字符语义：与 getAllText 同串，取整句长度时选中的文本应与夹具句子一致
    void selectionTextMatchesFixtureText();
    // 非法入参（空文档/越界页/负起始/零长）一律返回空矩形，不崩溃
    void invalidArgsReturnEmptyRect();
};

void TestPdfGeometry::sentenceBoundsReturnsRect() {
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath("fix.pdf");
    QVERIFY(writeFixture(path));
    QPdfDocument *doc = loadReady(path);
    QVERIFY(doc->pageCount() == 2);

    PdfTextGeometry g;
    const QRectF r = g.sentenceBounds(doc, 0, 0, 5);
    QVERIFY2(r.isValid(), "第 0 页前 5 字符应返回有效矩形");
    QVERIFY2(r.width() > 0 && r.height() > 0, "矩形应有非零宽高");
    // points 坐标系：A4 页 595x842pt，文本在页内非负坐标
    QVERIFY2(r.left() >= 0 && r.top() >= 0, "矩形应在页内（左上角非负）");

    // 整句（19 字符）应比前 5 字符更宽（同句单行，文字更长）
    const QRectF full = g.sentenceBounds(doc, 0, 0, 19);
    QVERIFY2(full.isValid(), "整句应返回有效矩形");
    QVERIFY2(full.width() >= r.width(), "整句矩形宽度应不小于前 5 字符矩形");

    // 第 1 页同样可查
    const QRectF p1 = g.sentenceBounds(doc, 1, 0, 5);
    QVERIFY2(p1.isValid(), "第 1 页前 5 字符应返回有效矩形");
    delete doc;
}

void TestPdfGeometry::selectionTextMatchesFixtureText() {
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath("fix.pdf");
    QVERIFY(writeFixture(path));
    QPdfDocument *doc = loadReady(path);
    QVERIFY(doc->pageCount() == 2);

    // 验证 getSelectionAtIndex 的索引语义与 getAllText 一致：
    // 第 0 页字符 [0,5) 选中文本 = 夹具串前 5 字符
    const QString pageText = doc->getAllText(0).text();
    const QString first5 = pageText.left(5);
    const QPdfSelection sel = doc->getSelectionAtIndex(0, 0, 5);
    QVERIFY2(sel.isValid(), "选区应有效");
    QCOMPARE(sel.text(), first5);

    PdfTextGeometry g;
    const QRectF r = g.sentenceBounds(doc, 0, 0, 5);
    QVERIFY(r.isValid());
    // 桥返回的矩形与直接取选区的 boundingRectangle 一致
    QCOMPARE(r, sel.boundingRectangle());
    delete doc;
}

void TestPdfGeometry::invalidArgsReturnEmptyRect() {
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = dir.filePath("fix.pdf");
    QVERIFY(writeFixture(path));
    QPdfDocument *doc = loadReady(path);
    QVERIFY(doc->pageCount() == 2);

    PdfTextGeometry g;
    // 空文档（显式转 QPdfDocument* 消除 QObject* 重载歧义）
    QVERIFY(!g.sentenceBounds(static_cast<QPdfDocument *>(nullptr), 0, 0, 5).isValid());
    // 负页 / 越界页
    QVERIFY(!g.sentenceBounds(doc, -1, 0, 5).isValid());
    QVERIFY(!g.sentenceBounds(doc, 99, 0, 5).isValid());
    // 负起始 / 零长 / 负长
    QVERIFY(!g.sentenceBounds(doc, 0, -1, 5).isValid());
    QVERIFY(!g.sentenceBounds(doc, 0, 0, 0).isValid());
    QVERIFY(!g.sentenceBounds(doc, 0, 0, -1).isValid());
    delete doc;
}

QTEST_MAIN(TestPdfGeometry)
#include "tst_pdfgeometry.moc"
