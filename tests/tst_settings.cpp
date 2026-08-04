#include <QtTest>
#include "core/SettingsStore.h"

class TestSettings : public QObject {
    Q_OBJECT
private slots:
    void defaults() {
        QTemporaryDir dir;
        SettingsStore s(dir.path() + "/settings.json");
        QCOMPARE(s.value("theme/mode").toString(), QString("auto"));
        QCOMPARE(s.value("typography/fontSize").toInt(), 18);
        QCOMPARE(s.value("webdav/syncBooks").toBool(), false);
    }
    void roundTrip() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        { SettingsStore s(path); s.setValue("tts/engine", "openai"); }
        SettingsStore s2(path);
        QCOMPARE(s2.value("tts/engine").toString(), QString("openai"));
    }
    void typePreserved() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        { SettingsStore s(path); s.setValue("webdav/port", 8080); }
        SettingsStore s2(path);
        QCOMPARE(s2.value("webdav/port").toInt(), 8080);
    }
    void deepPathPreservesSiblings() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        {
            SettingsStore s(path);
            s.setValue("a/b/c", 1);
            s.setValue("a/b/d", 2);
            QCOMPARE(s.value("a/b/c").toInt(), 1); // 写 d 时不得丢弃同层已写入的 c
            QCOMPARE(s.value("a/b/d").toInt(), 2);
        }
        SettingsStore s2(path);
        QCOMPARE(s2.value("a/b/c").toInt(), 1);
        QCOMPARE(s2.value("a/b/d").toInt(), 2);
    }
};
QTEST_MAIN(TestSettings)
#include "tst_settings.moc"
