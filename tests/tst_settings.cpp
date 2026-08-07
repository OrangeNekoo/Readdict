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
    // D5 复审：B8 时代的 reader/background 旧键（三态）应在预置 background 默认分区时迁移——
    // 迁移必须发生在 QML 加载前（构造函数），否则 QML 读到的 background/mode 恒为 light 默认值，
    // 升级用户的深色/米白背景静默回退浅色。迁移后删除旧键，再启动不重复迁移。
    void legacyReaderBackgroundMigrates() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        {
            QFile f(path);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("{\"reader\":{\"background\":\"dark\"}}");
        }
        SettingsStore s(path);
        QCOMPARE(s.value("background/mode").toString(), QString("dark"));
        QVERIFY(s.value("reader/background").isUndefined()); // 旧键已删除
        // 重开（新键已就位）：保持 dark 且不再有旧键
        SettingsStore s2(path);
        QCOMPARE(s2.value("background/mode").toString(), QString("dark"));
        QVERIFY(s2.value("reader/background").isUndefined());
    }
    void legacyReaderBackgroundPaperMigrates() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        {
            QFile f(path);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("{\"reader\":{\"background\":\"paper\"}}");
        }
        SettingsStore s(path);
        QCOMPARE(s.value("background/mode").toString(), QString("paper"));
    }
    void legacyReaderBackgroundInvalidFallsBackToLight() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        {
            QFile f(path);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("{\"reader\":{\"background\":\"weird\"}}");
        }
        SettingsStore s(path);
        QCOMPARE(s.value("background/mode").toString(), QString("light"));
    }
};
QTEST_MAIN(TestSettings)
#include "tst_settings.moc"
