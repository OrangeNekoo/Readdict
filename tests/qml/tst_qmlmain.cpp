// QML 测试自定义入口：注册 Readdict.Backend 单例（生产 main.cpp 中注册，测试
// 进程需自行注册），并暴露 TestEnv 供 QML 用例在临时目录造 TXT 书。
// 注意：不用 qt_add_executable 的 QUICK_TEST_SOURCE_DIR 自动 main（该关键字在
// Qt 6.11 公开 CMake API 中不存在），QUICK_TEST_SOURCE_DIR 宏由 tests/CMakeLists.txt
// 通过 target_compile_definitions 定义为 tests/qml 的绝对路径。
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQuickStyle>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>
#include <QtQuickTest/quicktest.h>
#include <qqml.h>

#include "core/BookImporter.h"
#include "core/BookManager.h"
#include "core/HighlightManager.h"
#include "core/SettingsStore.h"
#include "tts/TtsController.h"
#include "ui/ReaderTextHelper.h"

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
    }
    QStringList sourceFiles() const { return m_files; }
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
private:
    QStringList m_files;
    QString m_longSource;
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
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Settings", settings);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Books", books);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Importer", importer);
    // C5：Tts 单例（无引擎桩——测试不发声；engineAvailable=false 用于断言
    // TtsBar 禁用播放；seekTo/setSentences 仍驱动 QML 高亮游标）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Tts", new TtsController);
    // C7：Highlights 单例（独立连接名，与生产 main.cpp 对齐）——划线数据流测试经真实 SQLite
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Highlights",
                                 new HighlightManager(appData + "/t.db", QStringLiteral("readdict_highlights")));
    // C7：TextEdit 行距助手（同生产 main.cpp）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "ReaderText", new ReaderTextHelper);
    qmlRegisterSingletonInstance("Readdict.Test", 1, 0, "TestEnv", new TestEnv(appData));
    return quick_test_main(argc, argv, "tst_qml", QUICK_TEST_SOURCE_DIR);
}

#include "tst_qmlmain.moc"
