#include <QtTest>
#include "Fb2Parser.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

// 编译期注入 fixture 目录（构建目录与源码目录不同，ctest 工作目录为 build/tests）
#ifndef FB2_FIXTURES_DIR
#  define FB2_FIXTURES_DIR "tests/fixtures"
#endif

class TestFb2Parser : public QObject {
    Q_OBJECT
private slots:
    void parsesStructure() {
        Fb2Parser p;
        DocumentModel m = p.parse(QStringLiteral(FB2_FIXTURES_DIR) + "/sample.fb2");
        QCOMPARE(m.title, QStringLiteral("测试书"));
        QCOMPARE(m.author, QStringLiteral("作者甲"));
        QCOMPARE(m.publisher, QStringLiteral("测试出版社"));
        QCOMPARE(m.chapters.size(), 1);
        QCOMPARE(m.chapters[0].title, QStringLiteral("第一章"));
        // 章标题只进 Chapter.title，不入段落列表；段落 0=第一段，1=第二段（含 <b>）
        QCOMPARE(m.chapters[0].paragraphs.size(), 2);
        QCOMPARE(m.chapters[0].paragraphs[0].text, QStringLiteral("第一段。"));
        QVERIFY(m.chapters[0].paragraphs[1].html.contains("<b>段</b>"));
        // 纯文本与 html 分离
        QCOMPARE(m.chapters[0].paragraphs[1].text, QStringLiteral("第二段。"));
    }
    void missingFileReturnsEmpty() {
        Fb2Parser p;
        QVERIFY(p.parse(QStringLiteral(FB2_FIXTURES_DIR) + "/nope.fb2").empty());
    }
    void invalidXmlReturnsEmpty() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/bad.fb2");
        QVERIFY(f.open(QIODevice::WriteOnly));
        // 元数据良构、正文错配标签：解析必须整体失败，不能带出部分元数据
        f.write("<?xml version=\"1.0\"?><FictionBook><description><title-info>"
                "<book-title>坏书</book-title></title-info></description>"
                "<body><section><p>未闭合</section></body></FictionBook>");
        f.close();
        Fb2Parser p;
        const DocumentModel m = p.parse(f.fileName());
        QVERIFY(m.empty());
        QVERIFY(m.title.isEmpty()); // 出错时元数据也不带出
    }
    // 任务4 复审：description 良构但其后正文 XML 错配——readMetadataOnly 必须
    // 完整扫描整份文档并检查 QXmlStreamReader error，不能读完 <description>
    // 就 break 放行（与 parse() 的整文档良构校验语义一致）。
    void readMetadataOnlyRejectsTrailingXmlError() {
        QTemporaryDir dir;
        QFile f(dir.path() + "/badmeta.fb2");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("<?xml version=\"1.0\"?><FictionBook><description><title-info>"
                "<book-title>坏书</book-title><author><first-name>坏</first-name>"
                "<last-name>作者</last-name></author></title-info></description>"
                "<body><section><p>未闭合</section></body></FictionBook>");
        f.close();
        Fb2Parser p;
        const DocumentModel m = p.readMetadataOnly(f.fileName());
        QVERIFY(m.title.isEmpty());
        QVERIFY(m.author.isEmpty());
        QVERIFY(m.publisher.isEmpty());
        // 与完整 parse 语义一致：同一份文件 parse() 也必须失败
        QVERIFY(p.parse(f.fileName()).empty());
    }
    void extractsImagesToTemp() {
        // 自带一张 1x1 PNG（base64）的临时 FB2：<image l:href> 引用 <binary>，
        // 解出到临时目录并写入 Paragraph.imagePath；二进制置于 body 之后
        // （FB2 规范位置），验证两遍解析的收集顺序
        QTemporaryDir tmp;
        const QString path = tmp.path() + "/img.fb2";
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QStringLiteral(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            "<FictionBook xmlns=\"http://www.gribuser.ru/xml/fictionbook/2.0\""
            " xmlns:l=\"http://www.w3.org/1999/xlink\">"
            "  <description><title-info><book-title>图</book-title></title-info></description>"
            "  <body><section><title><p>章</p></title>"
            "    <p>前文。<image l:href=\"#pic1\"/>后文。</p>"
            "    <section><title><p>小节</p></title><p>嵌套段。</p></section>"
            "  </section></body>"
            "  <binary id=\"pic1\" content-type=\"image/png\">"
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
            "</binary>"
            "</FictionBook>").toUtf8());
        f.close();
        Fb2Parser p;
        DocumentModel m = p.parse(path);
        QCOMPARE(m.chapters.size(), 1); // 嵌套小节并入本章
        // 嵌套小节标题成为 level=1 标题段落（html 带 <h1> 包裹）
        QCOMPARE(m.chapters[0].paragraphs.size(), 3);
        QCOMPARE(m.chapters[0].paragraphs[1].level, 1);
        QCOMPARE(m.chapters[0].paragraphs[1].html, QStringLiteral("<h1>小节</h1>"));
        QCOMPARE(m.chapters[0].paragraphs[2].text, QStringLiteral("嵌套段。"));
        const Paragraph *imgPara = nullptr;
        for (const Chapter &c : m.chapters)
            for (const Paragraph &pp : c.paragraphs)
                if (!pp.imagePath.isEmpty()) imgPara = &pp;
        QVERIFY(imgPara);
        QFileInfo fi(imgPara->imagePath);
        QVERIFY(fi.exists());
        QVERIFY(fi.size() > 0);
        QVERIFY(imgPara->imagePath.startsWith(QDir::tempPath()));
        // content-type 补扩展名：binary content-type=image/png → pic1.png
        QCOMPARE(fi.fileName(), QStringLiteral("pic1.png"));
        // html 中保留 img 标签并指向本地解出文件
        QVERIFY(imgPara->html.contains("<img src="));
        QVERIFY(imgPara->html.contains(fi.fileName()));
        // 图片前后文本都在（base64 解码不干扰正文）
        QVERIFY(imgPara->text.contains(QStringLiteral("前文")));
        QVERIFY(imgPara->text.contains(QStringLiteral("后文")));
    }
    void presplitsSentences() {
        Fb2Parser p;
        DocumentModel m = p.parse(QStringLiteral(FB2_FIXTURES_DIR) + "/sample.fb2");
        // 正文段 "第一段。" 预分句为 1 句
        QCOMPARE(m.chapters[0].paragraphs[0].sentences.size(), 1);
        QCOMPARE(m.chapters[0].paragraphs[0].sentences[0],
                 QStringLiteral("第一段。"));
    }
    void parsesMultipleSectionsAndInlineTags() {
        // 两个 body 级 section 分两章；i/strong/em 内联标签保留在 html、
        // 不进纯文本
        Fb2Parser p;
        DocumentModel m = p.parse(QStringLiteral(FB2_FIXTURES_DIR) + "/multi.fb2");
        QCOMPARE(m.chapters.size(), 2);
        QCOMPARE(m.chapters[0].title, QStringLiteral("第一章"));
        QCOMPARE(m.chapters[1].title, QStringLiteral("第二章"));
        QCOMPARE(m.chapters[0].paragraphs.size(), 1);
        QVERIFY(m.chapters[0].paragraphs[0].html.contains("<i>重点</i>"));
        QVERIFY(m.chapters[0].paragraphs[0].html.contains("<strong>粗体</strong>"));
        QVERIFY(m.chapters[0].paragraphs[0].html.contains("<em>强调</em>"));
        QCOMPARE(m.chapters[0].paragraphs[0].text,
                 QStringLiteral("斜体重点与粗体及强调。"));
    }
    void rejectsPathTraversalImageId() {
        // binary id 含路径分隔符（"../../evil"）：图片引用整体拒绝，不写盘、
        // 不崩溃，正文继续解析
        QTemporaryDir tmp;
        const QString path = tmp.path() + "/evil.fb2";
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QStringLiteral(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            "<FictionBook xmlns=\"http://www.gribuser.ru/xml/fictionbook/2.0\""
            " xmlns:l=\"http://www.w3.org/1999/xlink\">"
            "  <description><title-info><book-title>恶</book-title></title-info></description>"
            "  <body><section><title><p>章</p></title>"
            "    <p>文本。<image l:href=\"#../../evil\"/>尾文。</p>"
            "  </section></body>"
            "  <binary id=\"../../evil\" content-type=\"image/png\">aGVsbG8=</binary>"
            "</FictionBook>").toUtf8());
        f.close();
        Fb2Parser p;
        const DocumentModel m = p.parse(path);
        QCOMPARE(m.chapters.size(), 1);
        bool sawImage = false;
        for (const Chapter &c : m.chapters)
            for (const Paragraph &pp : c.paragraphs)
                if (!pp.imagePath.isEmpty()) sawImage = true;
        QVERIFY(!sawImage); // 图片未写盘
        QVERIFY(!m.chapters[0].paragraphs[0].html.contains("<img"));
        QVERIFY(m.chapters[0].paragraphs[0].text.contains(QStringLiteral("文本")));
        QVERIFY(m.chapters[0].paragraphs[0].text.contains(QStringLiteral("尾文")));
    }
};
QTEST_MAIN(TestFb2Parser)
#include "tst_fb2parser.moc"
