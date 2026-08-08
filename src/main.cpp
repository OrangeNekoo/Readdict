#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QLocale>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QPair>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <qqml.h>
#include "core/BookManager.h"
#include "core/BookImporter.h"
#include "core/HighlightManager.h"
#include "core/SearchEngine.h"
#include "core/SettingsStore.h"
#include "sync/SyncController.h"
#include "tts/TtsController.h"
#include "ui/ReaderTextHelper.h"
#include "ui/LanguageController.h"

// D7：加载 fronts/ 下的可变字体（思源黑体 VF / 思源宋体 VF / 得意黑）。
// 三组路径互备，失败仅告警不崩溃：
//  1. 开发期——仓库根 fronts/ 相对当前工作目录（构建目录启动时 CWD 为仓库根，嵌套布局）
//  2. 打包态（macOS）——.app 内 Contents/Resources/fonts（扁平布局，CMake POST_BUILD 拷入）
//  3. 打包态（其他平台）——安装目录 ../share/readdict/fonts（扁平布局，install(FILES)）
static void loadBundledFonts() {
    // 仓库内嵌套布局（与 fronts/ 实际文件路径一致）
    const QStringList devRels = {
        QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSans-VF.otf.ttc"),
        QStringLiteral("02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSansHW-VF.otf.ttc"),
        QStringLiteral("02_SourceHanSerif-VF/02_SourceHanSerif-VF/Variable/SourceHanSerif-VF.otf.ttc"),
        QStringLiteral("smiley-sans-v2.0.1/SmileySans-Oblique.otf"),
    };
    // bundle/安装目录扁平布局（CMake 以实际文件名拷贝）
    const QStringList flatRels = {
        QStringLiteral("SourceHanSans-VF.otf.ttc"),
        QStringLiteral("SourceHanSansHW-VF.otf.ttc"),
        QStringLiteral("SourceHanSerif-VF.otf.ttc"),
        QStringLiteral("SmileySans-Oblique.otf"),
    };
    const QList<QPair<QString, QStringList>> dirs = {
        { QDir::currentPath() + "/fronts", devRels },
        { QCoreApplication::applicationDirPath() + "/../Resources/fonts", flatRels },
        { QCoreApplication::applicationDirPath() + "/../share/readdict/fonts", flatRels },
    };
    int loaded = 0;
    QStringList seen; // 规范路径去重：CWD 兜底与绝对路径兜底可能指向同一文件
    for (const auto &dir : dirs) {
        for (const QString &rel : dir.second) {
            const QString path = dir.first + "/" + rel;
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
        qWarning() << "未找到任何 bundled 字体，检查路径:" << dirs
                   << "（开发期从仓库根运行 build/Readdict.app/Contents/MacOS/Readdict 以命中 CWD 下的 fronts/）";
    else
        qInfo() << "字体加载完成，共" << loaded << "个字体文件";
}

// D6：启动语言——settings.json 的 ui/language 优先；未设置时按系统语言映射到
// zh_CN/zh_TW/en（简/繁/英三语），仍无匹配默认 zh_CN。
static QString resolveStartupLanguage(const SettingsStore &settings) {
    const QString saved = settings.value("ui/language").toString();
    if (!saved.isEmpty()) return saved;
    const QStringList uiLanguages = QLocale::system().uiLanguages();
    for (const QString &locale : uiLanguages) {
        const QLocale loc(locale);
        if (loc.language() == QLocale::Chinese) {
            const QLocale::Territory t = loc.territory();
            if (t == QLocale::Taiwan || t == QLocale::HongKong || t == QLocale::Macau)
                return QStringLiteral("zh_TW");
            return QStringLiteral("zh_CN");
        }
        if (loc.language() == QLocale::English)
            return QStringLiteral("en");
    }
    return QStringLiteral("zh_CN");
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Material");
    app.setApplicationName("Readdict");
    app.setOrganizationName("Readdict");

    // 确保 AppData 目录存在：SettingsStore 直接写 settings.json、数据库与书库目录都在其下，
    // 父目录缺失会导致写入/打开失败（A4 记录的问题）。
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));

    loadBundledFonts();

    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    auto *settings = new SettingsStore(appData + "/settings.json");
    // D6：语言控制器（zh_CN/zh_TW/en）。启动按 Settings ui/language（或系统语言，默认 zh_CN）
    // 加载翻译；语言切换由设置页下拉触发 applyLanguage，languageChanged 驱动 QML 重译。
    auto *lang = new LanguageController(resolveStartupLanguage(*settings));
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Lang", lang);
    // U1：Kindle 设计 Token 单例（QML 文件单例）。与 C++ 单例同机制注册，但走
    // qmlRegisterSingletonType(QUrl)——Theme.qml 是纯 QML 文件（无 C++ 对应）。
    // 注意资源路径带 src/ui/qml：生产模块（qt_add_qml_module）按 QML_FILES 相对
    // 路径嵌入；测试进程的资源路径不同（见 tst_qmlmain.cpp 注释）。
    qmlRegisterSingletonType(QUrl("qrc:/qt/qml/Readdict/src/ui/qml/Theme.qml"),
                             "Readdict.UI", 1, 0, "UITheme");
    auto *books = new BookManager(appData + "/Readdict.db");
    // 阅读器进度（progress/<bookId>）与 Books 单例解耦读写 settings.json（B8）
    books->setSettingsStore(settings);
    // importer 内部 BookManager 使用独立连接名 readdict_importer，避免 addDatabase
    // 同名连接时移除 Books 单例的 readdict_main 连接（Books->m_db 会随之失效）。
    auto *importer = new BookImporter(appData, appData + "/Readdict.db");
    // 导入成功（importer.imported）后驱动 Books 单例刷新，UI 的 booksModel 依赖其 booksChanged。
    QObject::connect(importer, &BookImporter::imported, books, [books] { emit books->booksChanged(); });
    // B2：refreshCovers 更新了封面后同样驱动 Books 单例刷新（importer 内部连接
    // 的 updateCover 不会触发 UI 的 booksChanged），书架封面即时生效。
    QObject::connect(importer, &BookImporter::coversRefreshed, books, [books] { emit books->booksChanged(); });
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
    // D3：WebDAV 同步控制器（手动/每 30 分钟自动）。SyncManager 内部直连 SQLite
    // （独立连接名 readdict_sync），与各单例连接隔离；dbPath=AppDataLocation/Readdict.db，
    // libraryDir=AppDataLocation（同 Books 单例）。启动时恢复上次的自动同步开关。
    auto *syncController = new SyncController(appData + "/Readdict.db", appData);
    // L2（P0#2）：注入设置单例——同步合并结果经 SettingsStore::setRoot 原子落盘并刷新
    // 内存，杜绝 SyncManager 直写文件后单例旧快照再保存覆盖合并结果。
    syncController->setSettingsStore(settings);
    syncController->setAutoSync(settings->value("webdav/autoSync").toBool());
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Sync", syncController);
    // B10：应用退出时结算阅读计时（页面 onDestruction 只在正常退出 QML 引擎销毁时触发，
    // 直接退进程/崩溃时兜底由这里结算，保证已读秒数不丢失）。
    QObject::connect(&app, &QCoreApplication::aboutToQuit, books, &BookManager::stopTracking);

    QQmlApplicationEngine engine;
    // D6：翻译切换后重估全部 qsTr 绑定（含 StackView 中不可见页面），即时全量刷新文本
    QObject::connect(lang, &LanguageController::languageChanged, &engine, &QQmlEngine::retranslate);
    engine.loadFromModule("Readdict", "Main");
    if (engine.rootObjects().isEmpty()) return -1;
    return app.exec();
}
