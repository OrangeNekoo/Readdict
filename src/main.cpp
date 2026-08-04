#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QLocale>
#include <QTranslator>
#include <QDir>
#include <QStandardPaths>
#include <qqml.h>
#include "core/BookManager.h"
#include "core/BookImporter.h"
#include "core/SettingsStore.h"

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

    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    auto *settings = new SettingsStore(appData + "/settings.json");
    auto *books = new BookManager(appData + "/Readdict.db");
    // importer 内部 BookManager 使用独立连接名 readdict_importer，避免 addDatabase
    // 同名连接时移除 Books 单例的 readdict_main 连接（Books->m_db 会随之失效）。
    auto *importer = new BookImporter(appData, appData + "/Readdict.db");
    // 导入成功（importer.imported）后驱动 Books 单例刷新，UI 的 booksModel 依赖其 booksChanged。
    QObject::connect(importer, &BookImporter::imported, books, [books] { emit books->booksChanged(); });
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Settings", settings);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Books", books);
    qmlRegisterSingletonInstance("Readdict.Backend", 1, 0, "Importer", importer);

    QQmlApplicationEngine engine;
    engine.loadFromModule("Readdict", "Main");
    if (engine.rootObjects().isEmpty()) return -1;
    return app.exec();
}
