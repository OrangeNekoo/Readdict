#include "SettingsStore.h"
#include <QDebug>
#include <QFile>
#include <QJsonDocument>

// 沿 key 链逐级下钻：每层取现有子对象（保留兄弟键）递归写入，再写回父对象。
// 等价于"沿 key 链逐级下钻"的引用式写法；QJsonValueRef 是临时值，无法取其地址
// （&(*cursor)[parts[i]] 是编译错误），故用逐层拷贝回写实现同样的语义。
static void insertPath(QJsonObject &obj, const QStringList &parts, int idx, const QJsonValue &value) {
    if (idx == parts.size() - 1) {
        obj.insert(parts[idx], value);
        return;
    }
    QJsonObject child = obj.value(parts[idx]).toObject(); // 中间层为标量时按简报注视为可接受（toObject 得空对象）
    insertPath(child, parts, idx + 1, value);
    obj.insert(parts[idx], child);
}

SettingsStore::SettingsStore(const QString &path, QObject *parent) : QObject(parent), m_path(path) {
    QFile f(m_path);
    if (f.open(QIODevice::ReadOnly))
        m_root = QJsonDocument::fromJson(f.readAll()).object();
    // 默认值
    if (!m_root.contains("theme")) m_root.insert("theme", QJsonObject{{"mode", "auto"}});
    if (!m_root.contains("typography"))
        m_root.insert("typography", QJsonObject{{"fontFamily", "思源黑体 VF"}, {"fontSize", 18},
                                                {"lineHeight", 1.6}, {"align", "left"}, {"pageWidth", "normal"}});
    if (!m_root.contains("tts")) m_root.insert("tts", QJsonObject{{"engine", "system"}, {"rate", 1.0}});
    if (!m_root.contains("webdav"))
        m_root.insert("webdav", QJsonObject{{"url", ""}, {"user", ""}, {"password", ""},
                                            {"syncSettings", true}, {"syncProgress", true},
                                            {"syncHighlights", false}, {"syncBooks", false},
                                            {"autoSync", false}});
    save();
}

QJsonValue SettingsStore::value(const QString &dottedKey) const {
    const QStringList parts = dottedKey.split('/');
    QJsonObject obj = m_root;
    for (int i = 0; i < parts.size() - 1; ++i) obj = obj.value(parts[i]).toObject();
    return obj.value(parts.last());
}

void SettingsStore::setValue(const QString &dottedKey, const QJsonValue &value) {
    insertPath(m_root, dottedKey.split('/'), 0, value);
    save();
}

void SettingsStore::save() {
    QFile f(m_path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("SettingsStore: 无法写入 %s: %s", qPrintable(m_path), qPrintable(f.errorString()));
        return;
    }
    const QByteArray data = QJsonDocument(m_root).toJson(QJsonDocument::Indented);
    if (f.write(data) != data.size())
        qWarning("SettingsStore: 写入 %s 不完整: %s", qPrintable(m_path), qPrintable(f.errorString()));
}
