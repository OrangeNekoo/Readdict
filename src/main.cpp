#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QLocale>
#include <QTranslator>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QStandardPaths>
#include <QTimer>
#include <qqml.h>
#include "core/BookManager.h"
#include "core/BookImporter.h"
#include "core/HighlightManager.h"
#include "core/SearchEngine.h"
#include "core/SettingsStore.h"
#include "tts/TtsController.h"
#include "ui/ReaderTextHelper.h"

// B8：加载 fronts/ 下的可变字体（思源黑体 VF / 思源宋体 VF / 得意黑）。
// 开发期从仓库根 fronts/ 相对当前工作目录加载（构建目录启动时 CWD 为仓库根），
// 兜底应用包 Resources/fronts（D7 打包完善）；失败仅告警不崩溃。
static void loadBundledFonts() {
    const QStringList baseDirs = {
        QDir::currentPath() + "/fronts",                                 // 从仓库根启动（开发）
        QCoreApplication::applicationDirPath() + "/../Resources/fronts", // .app bundle（D7 打包）
    };
    const QStringList rels = {
        QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSans-VF.otf.ttc"),
        QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSansHW-VF.otf.ttc"),
        QStringLiteral("02_SourceHanSerif-VF/02_SourceHanSerif-VF/Variable/SourceHanSerif-VF.otf.ttc"),
        QStringLiteral("smiley-sans-v2.0.1/SmileySans-Oblique.otf"),
    };
    int loaded = 0;
    QStringList seen; // 规范路径去重：CWD 兜底与绝对路径兜底可能指向同一文件
    for (const QString &base : baseDirs) {
        for (const QString &rel : rels) {
            const QString path = base + "/" + rel;
            const QString canon = QFileInfo(path).canonicalFilePath();
            if (canon.isEmpty() || seen.contains(canon)) continue;
            seen.append(canon);
            const int id = QFontDatabase::addApplicationFont(path);
            if (id < 0) {
                qWarning() << "字体加载失败:" << path;
                continue;
            }
            qInfo() << "已加载字体:" << QFontDatabase::applicationFontFamilies(id);
            ++loaded;
        }
    }
    if (loaded == 0)
        qWarning() << "未找到任何 bundled 字体，检查路径:" << baseDirs
                   << "（开发期从仓库根运行 ./build/Readdict 以命中 CWD 下的 fronts/）";
    else
        qInfo() << "字体加载完成，共" << loaded << "个字体文件";
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Material");
    app.setApplicationName("Readdict");
    app.setOrganizationName("Readdict");

    QTranslator translator;
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &locale : uiLanguages) {
        if (translator.load("readdict_" + QLocale(locale).name(), ":/i18n")) break;
    }
    app.installTranslator(&translator);

    // 确保 AppData 目录存在：SettingsStore 直接写 settings.json、数据库与书库目录都在其下，
    // 父目录缺失会导致写入/打开失败（A4 记录的问题）。
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));

    loadBundledFonts();

    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    auto *settings = new SettingsStore(appData + "/settings.json");
    auto *books = new BookManager(appData + "/Readdict.db");
    // 阅读器进度（progress/<bookId>）与 Books 单例解耦读写 settings.json（B8）
    books->setSettingsStore(settings);
    // importer 内部 BookManager 使用独立连接名 readdict_importer，避免 addDatabase
    // 同名连接时移除 Books 单例的 readdict_main 连接（Books->m_db 会随之失效）。
    auto *importer = new BookImporter(appData, appData + "/Readdict.db");
    // 导入成功（importer.imported）后驱动 Books 单例刷新，UI 的 booksModel 依赖其 booksChanged。
    QObject::connect(importer, &BookImporter::imported, books, [books] { emit books->booksChanged(); });
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Settings", settings);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Books", books);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Importer", importer);
    // C7：划线/笔记单例。独立连接名 readdict_highlights（C6 支持注入），避免与
    // Books 单例的 readdict_main 重名（同名 addDatabase 会移除旧连接，见 DatabaseManager.h）。
    auto *highlights = new HighlightManager(appData + "/Readdict.db", QStringLiteral("readdict_highlights"));
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Highlights", highlights);
    // C8：FTS5 全文搜索单例（书架全文搜索 + 书内搜索共用；固定连接名同 Highlights 模式）。
    auto *search = new SearchEngine(appData + "/Readdict.db", QStringLiteral("readdict_search"));
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Search", search);
    // C8 复审：存量书索引回填——功能上线前已入库的书没有全文索引。延迟到事件循环
    // 起来后逐本执行（书与书之间让出，UI 保持响应），回填失败不影响启动。
    QTimer::singleShot(0, importer, [importer] { importer->backfillMissingIndexes(); });
    // C7：TextEdit 行距助手（段落改 TextEdit 渲染后 lineHeight 属性不可用，见 ReaderTextHelper.h）
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "ReaderText", new ReaderTextHelper);
    // C5：TTS 控制器按 settings.json 的 tts/ 分区构建引擎（system/openai），
    // reconfigure 由设置页在保存后再次调用以热切换引擎。
    auto *tts = new TtsController;
    tts->reconfigure(settings->value("tts/engine").toString("system"),
                     settings->value("tts/url").toString(),
                     settings->value("tts/key").toString(),
                     settings->value("tts/model").toString(),
                     settings->value("tts/voice").toString(),
                     settings->value("tts/rate").toDouble(1.0));
    tts->setRate(settings->value("tts/rate").toDouble(1.0));
    tts->setVoice(settings->value("tts/voice").toString());
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Tts", tts);
    // B10：应用退出时结算阅读计时（页面 onDestruction 只在正常退出 QML 引擎销毁时触发，
    // 直接退进程/崩溃时兜底由这里结算，保证已读秒数不丢失）。
    QObject::connect(&app, &QCoreApplication::aboutToQuit, books, &BookManager::stopTracking);

    QQmlApplicationEngine engine;
    engine.loadFromModule("Readdict", "Main");
    if (engine.rootObjects().isEmpty()) return -1;
    return app.exec();
}
