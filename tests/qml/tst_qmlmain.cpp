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
#include "core/SettingsStore.h"

// 仅测试进程可见：在临时目录预生成 TXT 源书，QML 侧经 Importer.doImport 导入。
class TestEnv : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList sourceFiles READ sourceFiles CONSTANT)
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
    }
    QStringList sourceFiles() const { return m_files; }
private:
    QStringList m_files;
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
    // importer 内部 BookManager 固定用连接名 readdict_importer（见 BookImporter.cpp），
    // 与 Books 单例的 readdict_main 不冲突；指向同一 db 文件，行为与生产一致。
    auto *importer = new BookImporter(appData, appData + "/t.db");
    QObject::connect(importer, &BookImporter::imported, books, [books] { emit books->booksChanged(); });
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Settings", settings);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Books", books);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Importer", importer);
    qmlRegisterSingletonInstance("Readdict.Test", 1, 0, "TestEnv", new TestEnv(appData));
    return quick_test_main(argc, argv, "tst_qml", QUICK_TEST_SOURCE_DIR);
}

#include "tst_qmlmain.moc"
