#include "SettingsStore.h"
#include <QFile>
#include <QJsonDocument>

SettingsStore::SettingsStore(const QString &path) : m_path(path) {
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
                                            {"syncHighlights", false}, {"syncBooks", false}});
    save();
}

QJsonValue SettingsStore::value(const QString &dottedKey) const {
    const QStringList parts = dottedKey.split('/');
    QJsonObject obj = m_root;
    for (int i = 0; i < parts.size() - 1; ++i) obj = obj.value(parts[i]).toObject();
    return obj.value(parts.last());
}

void SettingsStore::setValue(const QString &dottedKey, const QJsonValue &value) {
    const QStringList parts = dottedKey.split('/');
    // 自底向上重建路径：sub 初始为叶子值，逐层挂回 m_root 中对应父对象（保留该层已有键），
    // 最后整条路径写回根。避免简报中悬垂引用（&(*cursor)[parts[i]]）导致的丢失修改。
    QJsonValue sub = value;
    for (int i = parts.size() - 2; i >= 0; --i) {
        QJsonObject parent = m_root.value(parts[i]).toObject();
        parent.insert(parts[i + 1], sub);
        sub = parent;
    }
    m_root.insert(parts.first(), sub);
    save();
}

void SettingsStore::save() {
    QFile f(m_path);
    if (f.open(QIODevice::WriteOnly))
        f.write(QJsonDocument(m_root).toJson(QJsonDocument::Indented));
}
