// QML 测试自定义入口：注册 Readdict.Backend 单例（生产 main.cpp 中注册，测试
// 进程需自行注册），并暴露 TestEnv 供 QML 用例在临时目录造 TXT 书。
// 注意：不用 qt_add_executable 的 QUICK_TEST_SOURCE_DIR 自动 main（该关键字在
// Qt 6.11 公开 CMake API 中不存在），QUICK_TEST_SOURCE_DIR 宏由 tests/CMakeLists.txt
// 通过 target_compile_definitions 定义为 tests/qml 的绝对路径。
#include <QColor>
#include <QBuffer>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QQuickStyle>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>
#include <QtQuickTest/quicktest.h>
#include <qqml.h>

#include <zip.h>   // minizip 写端：合成带封面 EPUB（B2 封面刷新冒烟 fixture）
#include <zlib.h>

#include "core/BookImporter.h"
#include "core/BookManager.h"
#include "core/HighlightManager.h"
#include "core/SearchEngine.h"
#include "core/SettingsStore.h"
#include "sync/SyncController.h"
#include "tts/TtsController.h"
#include "ui/ReaderTextHelper.h"
#include "ui/LanguageController.h"

// B2：合成带真实封面的最小 EPUB（OPF <meta name="cover"> 指向纯红图 850x1214，
// 与 tst_bookimporter 的 makeCoverEpub 同构）——封面刷新冒烟 fixture。
// 标题即文件名 coverepub（completeBaseName 语义与导入流程一致）。
static bool writeCoverEpub(const QString &zipPath) {
    const QByteArray container =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
        "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" "
        "media-type=\"application/oebps-package+xml\"/></rootfiles></container>";
    const QByteArray opf =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"id\" version=\"2.0\">"
        "<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
        "<dc:title>封面刷新书</dc:title><dc:creator>测试作者</dc:creator>"
        "<meta name=\"cover\" content=\"cover-img\"/>"
        "</metadata>"
        "<manifest>"
        "<item href=\"Text/cover.xhtml\" id=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
        "<item href=\"Images/coverA.png\" id=\"cover-img\" media-type=\"image/png\"/>"
        "</manifest>"
        "<spine toc=\"ncx\"><itemref idref=\"cover.xhtml\"/></spine>"
        "</package>";
    const QByteArray coverXhtml =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Cover</title></head>"
        "<body><p>封面刷新测试正文。</p></body></html>";
    QImage img(850, 1214, QImage::Format_RGB32);
    img.fill(QColor("#E00000"));
    QByteArray png;
    QBuffer buf(&png);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    buf.close();
    zipFile zf = zipOpen64(zipPath.toUtf8().constData(), APPEND_STATUS_CREATE);
    if (!zf) return false;
    struct Entry { const char *name; QByteArray data; };
    const Entry entries[] = {
        {"META-INF/container.xml", container},
        {"OEBPS/content.opf", opf},
        {"OEBPS/Text/cover.xhtml", coverXhtml},
        {"OEBPS/Images/coverA.png", png},
    };
    bool ok = true;
    for (const Entry &e : entries) {
        zip_fileinfo zi = {};
        if (zipOpenNewFileInZip(zf, e.name, &zi, nullptr, 0, nullptr, 0, nullptr,
                                Z_DEFLATED, Z_DEFAULT_COMPRESSION) != ZIP_OK) {
            ok = false; break;
        }
        if (zipWriteInFileInZip(zf, e.data.constData(),
                                static_cast<unsigned>(e.data.size())) != ZIP_OK) {
            ok = false; break;
        }
        zipCloseFileInZip(zf);
    }
    zipClose(zf, nullptr);
    return ok;
}

// 仅测试进程可见：在临时目录预生成 TXT 源书，QML 侧经 Importer.doImport 导入。
class TestEnv : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList sourceFiles READ sourceFiles CONSTANT)
    // 真实 PDF 路径（环境变量 READDICT_REAL_PDF，未设置时为空串）：供 PdfReaderPage
    // 冒烟测试加载真实源文件验证 QtQuick.Pdf 可用（B9）
    Q_PROPERTY(QString pdfSource READ pdfSource CONSTANT)
    // 真实 EPUB 路径（环境变量 READDICT_REAL_EPUB，未设置时为空串）：真实书进度恢复验证（B10）
    Q_PROPERTY(QString realEpubSource READ realEpubSource CONSTANT)
    // 多章节 EPUB fixture（sample.epub，2 章）：章节恢复冒烟（B10）
    Q_PROPERTY(QString epubFixture READ epubFixture CONSTANT)
    // 长文本书（300 段，单章）：滚动恢复冒烟（内容高度远大于视口，滚动值可区分）（B10）
    Q_PROPERTY(QString longSource READ longSource CONSTANT)
    // 多章节长书（3 章：首章=文件名 100 段，后两章各 60 段）：章末自动续章冒烟（规格 §7，
    // 首章内容高度远大于视口，可滚动接近底部触发自动换章）
    Q_PROPERTY(QString multiSource READ multiSource CONSTANT)
    // 重复 h2 标题 TXT（4 章，后 3 章 h2 同名）：划线查重键跨章碰撞回归（C7b）
    Q_PROPERTY(QString dupTitlesSource READ dupTitlesSource CONSTANT)
    // 真实背景图片（64x64 PNG，file:// URL）：D5 冒烟经此验证 copyToBackgrounds 导入路径
    // 与 ReaderBackground 图片加载/模糊亮度渲染
    Q_PROPERTY(QString backgroundImage READ backgroundImage CONSTANT)
    // B1：删除冒烟专属书源（标题 delme）——不与共享的 zeta/alpha/mike 混用，
    // 删除用例可安全删书+删文件而不影响其他用例
    Q_PROPERTY(QString deleteSource READ deleteSource CONSTANT)
    // B2：带真实封面的 EPUB（标题 coverepub，OPF cover 声明指向红图）——
    // 封面刷新冒烟：导入 → cover 改回占位 → refreshCovers 恢复真实封面
    Q_PROPERTY(QString coverEpubSource READ coverEpubSource CONSTANT)
public:
    explicit TestEnv(const QString &workDir, QObject *parent = nullptr) : QObject(parent) {
        QDir srcDir(workDir + "/src");
        srcDir.mkpath(".");
        // 标题 = 文件名（completeBaseName）：zeta/alpha/mike，导入顺序即 zeta→alpha→mike
        const QStringList titles = {QStringLiteral("zeta"), QStringLiteral("alpha"), QStringLiteral("mike")};
        int i = 0;
        for (const QString &title : titles) {
            const QString path = srcDir.filePath(title + ".txt");
            QFile f(path);
            if (!f.open(QIODevice::WriteOnly)) continue;
            f.write(QStringLiteral("这是第 %1 本测试书的内容行。\n第二行内容，用于验证导入与搜索。\n").arg(++i).toUtf8());
            f.close();
            // 直接给 file:// URL（QML 无 QUrl::fromLocalFile 等价物）
            m_files.append(QUrl::fromLocalFile(path).toString());
        }
        // 长文本书：300 段正文，保证滚动恢复用例中 contentHeight 远大于视口
        const QString longPath = srcDir.filePath("longbook.txt");
        QFile lf(longPath);
        if (lf.open(QIODevice::WriteOnly)) {
            for (int k = 0; k < 300; ++k)
                lf.write(QStringLiteral("这是长文本书的第 %1 段内容，用于滚动位置恢复验证。\n\n").arg(k + 1).toUtf8());
            lf.close();
        }
        m_longSource = QUrl::fromLocalFile(longPath).toString();
        // 多章节长书：首章（文件名标题）100 段 → 距视口底部可滚动距离远大于
        // autoNextThreshold(200px)；"## " 开新章（TextParser level>=2），后两章各 60 段
        const QString multiPath = srcDir.filePath("multibook.txt");
        QFile mf(multiPath);
        if (mf.open(QIODevice::WriteOnly)) {
            for (int k = 0; k < 100; ++k)
                mf.write(QStringLiteral("这是第一章的第 %1 段内容，用于章末自动续章的滚动验证。\n\n").arg(k + 1).toUtf8());
            mf.write("## 第二章\n");
            for (int k = 0; k < 60; ++k)
                mf.write(QStringLiteral("这是第二章的第 %1 段内容。\n\n").arg(k + 1).toUtf8());
            mf.write("## 第三章\n");
            for (int k = 0; k < 60; ++k)
                mf.write(QStringLiteral("这是第三章的第 %1 段内容。\n\n").arg(k + 1).toUtf8());
            mf.close();
        }
        m_multiSource = QUrl::fromLocalFile(multiPath).toString();
        // 重复 h2 标题书：4 章（首章=文件名，后 3 章 h2 均为 "第一章"）——
        // 未去重时第 2/3/4 章标题相同，划线查重键跨章碰撞（C7b 回归用）
        const QString dupPath = srcDir.filePath("duptitles.txt");
        QFile df(dupPath);
        if (df.open(QIODevice::WriteOnly)) {
            df.write(QStringLiteral(
                "这是重复标题书的第一段正文。\n"
                "## 第一章\n"
                "这是第一章的第一段正文。\n"
                "## 第一章\n"
                "这是第二章的第一段正文。\n"
                "## 第一章\n"
                "这是第三章的第一段正文。\n").toUtf8());
            df.close();
        }
        m_dupTitlesSource = QUrl::fromLocalFile(dupPath).toString();
        // D5：真实背景图片（纯色 64x64 PNG，双色渐变不需要——纯色即可验证解码/复制/渲染）
        const QString bgPath = srcDir.filePath("bg_test.png");
        QImage bgImg(64, 64, QImage::Format_RGB32);
        bgImg.fill(QColor(0x3a, 0x7d, 0xbd));
        if (bgImg.save(bgPath))
            m_backgroundImage = QUrl::fromLocalFile(bgPath).toString();
        // B1：删除冒烟专属 TXT 书（标题 delme）
        const QString delPath = srcDir.filePath("delme.txt");
        QFile dlf(delPath);
        if (dlf.open(QIODevice::WriteOnly)) {
            dlf.write(QStringLiteral("待删除测试书的内容行。\n第二行内容。\n").toUtf8());
            dlf.close();
            m_deleteSource = QUrl::fromLocalFile(delPath).toString();
        }
        // B2：带真实封面的 EPUB（标题 coverepub）——封面刷新冒烟 fixture
        const QString coverEpubPath = srcDir.filePath("coverepub.epub");
        if (writeCoverEpub(coverEpubPath))
            m_coverEpubSource = QUrl::fromLocalFile(coverEpubPath).toString();
    }
    QStringList sourceFiles() const { return m_files; }
    // B1：删除冒烟断言书库文件真实消失（QML 侧无文件系统 API）
    Q_INVOKABLE bool fileExists(const QString &path) const { return QFile::exists(path); }
    QString dupTitlesSource() const { return m_dupTitlesSource; }
    QString pdfSource() const {
        const QString p = qEnvironmentVariable("READDICT_REAL_PDF");
        return QFile::exists(p) ? p : QString();
    }
    QString realEpubSource() const {
        // doImport 期望 file:// URL（同 sourceFiles/epubFixture），裸路径会被 QUrl 解析失败
        const QString p = qEnvironmentVariable("READDICT_REAL_EPUB");
        return QFile::exists(p) ? QUrl::fromLocalFile(p).toString() : QString();
    }
    QString epubFixture() const {
        const QString p = QStringLiteral(TEST_FIXTURES_DIR) + "/sample.epub";
        return QFile::exists(p) ? QUrl::fromLocalFile(p).toString() : QString();
    }
    QString longSource() const { return m_longSource; }
    QString multiSource() const { return m_multiSource; }
    QString backgroundImage() const { return m_backgroundImage; }
    QString deleteSource() const { return m_deleteSource; }
    QString coverEpubSource() const { return m_coverEpubSource; }
private:
    QStringList m_files;
    QString m_longSource;
    QString m_multiSource;
    QString m_dupTitlesSource;
    QString m_backgroundImage;
    QString m_deleteSource;
    QString m_coverEpubSource;
};

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Material");
    // 独立临时数据目录：QTemporaryDir 在进程退出时自动清理，避免 PID 复用后遗留
    // stale t.db（books.path UNIQUE 约束）导致 e2e 重导入失败（审查反馈）；也不污染真实书库
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) return -1;
    const QString appData = tmpDir.path();
    auto *books = new BookManager(appData + "/t.db");
    auto *settings = new SettingsStore(appData + "/settings.json");
    // B10：与生产 main.cpp 对齐——阅读进度（progress/<bookId>、scroll_<bookId>）读写 settings.json
    books->setSettingsStore(settings);
    // importer 内部 BookManager 固定用连接名 readdict_importer（见 BookImporter.cpp），
    // 与 Books 单例的 readdict_main 不冲突；指向同一 db 文件，行为与生产一致。
    auto *importer = new BookImporter(appData, appData + "/t.db");
    QObject::connect(importer, &BookImporter::imported, books, [books] { emit books->booksChanged(); });
    // B2：refreshCovers 更新封面后驱动 Books 单例刷新（同生产 main.cpp 接线）
    QObject::connect(importer, &BookImporter::coversRefreshed, books, [books] { emit books->booksChanged(); });
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Settings", settings);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Books", books);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Importer", importer);
    // C5：Tts 单例（初始无引擎——测试不发声；engineAvailable=false 用于断言
    // TtsBar 禁用播放；用例内切 openai 无 key 引擎后 play/next 驱动 QML 高亮游标）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Tts", new TtsController);
    // C7：Highlights 单例（独立连接名，与生产 main.cpp 对齐）——划线数据流测试经真实 SQLite
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Highlights",
                                 new HighlightManager(appData + "/t.db", QStringLiteral("readdict_highlights")));
    // C8：Search 单例（固定连接名，与生产 main.cpp 对齐）——全文搜索 QML 冒烟
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Search",
                                 new SearchEngine(appData + "/t.db", QStringLiteral("readdict_search")));
    // C7：TextEdit 行距助手（同生产 main.cpp）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "ReaderText", new ReaderTextHelper);
    // D6：语言控制器（同生产 main.cpp；初始 zh_CN，测试资源已编入三份 .qm）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Lang", new LanguageController("zh_CN"));
    // U1：Kindle 设计 Token 单例（QML 文件单例）——同生产 main.cpp 注册，测试进程
    // 的 import Readdict.UI 才能解析 UITheme。测试资源（tests/CMakeLists.txt 的
    // qml_ui，BASE src/ui/qml）路径无 src 前缀：qrc:/qt/qml/Readdict/ui/qml/Theme.qml；
    // 生产模块路径带 src/ui/qml（见 main.cpp 注释），两进程 URL 各自匹配其资源布局。
    qmlRegisterSingletonType(QUrl("qrc:/qt/qml/Readdict/ui/qml/Theme.qml"),
                             "Readdict.UI", 1, 0, "UITheme");
    // D3：Sync 单例（同生产 main.cpp；指向测试临时库，run() 读同一 settings.json）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Sync",
                                 new SyncController(appData + "/t.db", appData));
    qmlRegisterSingletonInstance("Readdict.Test", 1, 0, "TestEnv", new TestEnv(appData));
    return quick_test_main(argc, argv, "tst_qml", QUICK_TEST_SOURCE_DIR);
}

#include "tst_qmlmain.moc"
