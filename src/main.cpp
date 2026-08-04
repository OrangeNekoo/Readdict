#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QLocale>
#include <QTranslator>

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

    QQmlApplicationEngine engine;
    engine.loadFromModule("Readdict", "Main");
    if (engine.rootObjects().isEmpty()) return -1;
    return app.exec();
}
