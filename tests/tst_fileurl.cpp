// FileUrl::fromPath 单元测试：本地路径 → file URL 的平台无关转换逻辑。
// 关键回归：Windows 盘符路径 "F:/x" 曾被 QML "file://"+path 手拼坏成
// file://f/x（盘符当主机名）；fromPath 必须走 QUrl::fromLocalFile。
// 用例为纯字符串断言，在任意平台运行（不依赖真实 F:/ 盘存在）。
#include <QTest>
#include "ui/FileUrl.h"

class TestFileUrl : public QObject {
    Q_OBJECT
private slots:
    void windowsDrivePath();
    void windowsDriveBackslashPath();
    void unixPath();
    void emptyInput();
    void existingUrlPreserved();
    void schemeLikePathNotMistaken();
    void specialCharsEscaped();
};

void TestFileUrl::windowsDrivePath() {
    // 核心回归断言（平台无关）：盘符路径生成的 URL 必须是 file:///F:/...
    // ——手拼 "file://"+path 会生成 file://f/...（盘符沦为主机名）
    const QUrl url = FileUrl().fromPath("F:/Readdict/bin/data/covers/cover_abc.png");
    QCOMPARE(url.toString(), "file:///F:/Readdict/bin/data/covers/cover_abc.png");
    QCOMPARE(url.scheme(), "file");
#ifdef Q_OS_WIN
    // toLocalFile 逆还原按 Windows 规则（F:/x）；非 Windows 平台 QUrl 按
    // POSIX 语义把 F:/ 当普通相对路径，逆还原无意义
    QCOMPARE(url.toLocalFile(), "F:/Readdict/bin/data/covers/cover_abc.png");
#endif
}

void TestFileUrl::windowsDriveBackslashPath() {
#ifdef Q_OS_WIN
    const QUrl url = FileUrl().fromPath("C:\\Users\\WanKe\\AppData\\Local\\Temp\\x.jpg");
    QCOMPARE(url.scheme(), "file");
    QCOMPARE(url.toLocalFile(), "C:/Users/WanKe/AppData/Local/Temp/x.jpg");
#else
    // 反斜杠在 POSIX 是合法文件名字符，QUrl 不做盘符转换——仅 Windows 有意义
    QSKIP("仅 Windows 平台测试反斜杠路径语义");
#endif
}

void TestFileUrl::unixPath() {
    QCOMPARE(FileUrl().fromPath("/Users/t/data/covers/a.png").toString(),
             "file:///Users/t/data/covers/a.png");
}

void TestFileUrl::emptyInput() {
    QVERIFY(!FileUrl().fromPath(QString()).isValid());
    QVERIFY(!FileUrl().fromPath("").isValid());
}

void TestFileUrl::existingUrlPreserved() {
    // 已带 scheme 的输入原样返回（file/http/qrc）
    QCOMPARE(FileUrl().fromPath("file:///F:/x.png").toString(), "file:///F:/x.png");
    QCOMPARE(FileUrl().fromPath("https://example.com/a.png").toString(),
             "https://example.com/a.png");
    QCOMPARE(FileUrl().fromPath("qrc:/qt/qml/Readdict/x.png").toString(),
             "qrc:/qt/qml/Readdict/x.png");
}

void TestFileUrl::schemeLikePathNotMistaken() {
    // 单字母 scheme（Windows 盘符）按本地路径处理：唯一保留盘符集 C-Z
    for (char c = 'C'; c <= 'Z'; ++c) {
        const QString p = QString("%1:/some/path.png").arg(QLatin1Char(c));
        QCOMPARE(FileUrl().fromPath(p).scheme(), "file");
    }
    // 真实多字母 scheme 仍是 URL
    QCOMPARE(FileUrl().fromPath("http://x/y").scheme(), "http");
}

void TestFileUrl::specialCharsEscaped() {
    // round-trip：中文/空格路径经 fromLocalFile 后 toLocalFile 完整还原
    const QUrl url = FileUrl().fromPath("/data/我的 书/cover 1.png");
    QCOMPARE(url.scheme(), "file");
    QCOMPARE(url.toLocalFile(), "/data/我的 书/cover 1.png");
}

QTEST_MAIN(TestFileUrl)
#include "tst_fileurl.moc"
