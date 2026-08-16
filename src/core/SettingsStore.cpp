#include "SettingsStore.h"
#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QUrl>

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
    if (f.open(QIODevice::ReadOnly)) {
        const QByteArray data = f.readAll();
        f.close();
        QJsonParseError err{};
        m_root = QJsonDocument::fromJson(data, &err).object();
        if (err.error != QJsonParseError::NoError && !data.trimmed().isEmpty()) {
            // 损坏：备份原文件后回退默认，绝不静默覆盖丢失用户数据
            qWarning("SettingsStore: %s 解析失败(%s)，备份后回退默认",
                     qPrintable(m_path), qPrintable(err.errorString()));
            QFile::copy(m_path, m_path + QStringLiteral(".corrupt-")
                        + QString::number(QDateTime::currentSecsSinceEpoch()));
            m_root = QJsonObject();
        }
    }
    applyDefaults();
    save();
}

void SettingsStore::applyDefaults() {
    // 默认值
    if (!m_root.contains("theme")) m_root.insert("theme", QJsonObject{{"mode", "auto"}});
    // C5：Kindle 默认衬线感——默认字体改思源宋体（衬线）；已有配置（含旧默认黑体）
    // 保持用户选择不动，仅影响新配置。设置页外观卡提供 宋体/黑体 切换。
    if (!m_root.contains("typography"))
        m_root.insert("typography", QJsonObject{{"fontFamily", "思源宋体 VF"}, {"fontSize", 18},
                                                {"lineHeight", 1.6}, {"align", "left"}, {"pageWidth", "normal"}});
    if (!m_root.contains("tts")) m_root.insert("tts", QJsonObject{{"engine", "system"}, {"rate", 1.0}});
    // 阅读选项：翻页方式、进度格式/范围与自动续章。范围默认本章，兼容旧配置。
    if (!m_root.contains("reading")) {
        m_root.insert("reading", QJsonObject{{"pageMode", "scroll"},
                                               {"progressDisplay", "pages"},
                                               {"progressScope", "chapter"},
                                               {"autoContinue", true},
                                               {"darkFollow", false}});
    } else {
        QJsonObject reading = m_root.value("reading").toObject();
        const QString progressDisplay = reading.value("progressDisplay").toString();
        if (progressDisplay != QLatin1String("pages") && progressDisplay != QLatin1String("percent"))
            reading.insert("progressDisplay", "pages");
        const QString progressScope = reading.value("progressScope").toString();
        if (progressScope != QLatin1String("chapter") && progressScope != QLatin1String("book"))
            reading.insert("progressScope", "chapter");
        if (!reading.contains("pageMode")) reading.insert("pageMode", "scroll");
        if (!reading.contains("autoContinue")) reading.insert("autoContinue", true);
        if (!reading.contains("darkFollow")) reading.insert("darkFollow", false);
        m_root.insert("reading", reading);
    }
    if (!m_root.contains("webdav"))
        m_root.insert("webdav", QJsonObject{{"url", ""}, {"user", ""}, {"password", ""},
                                            {"syncSettings", true}, {"syncProgress", true},
                                            {"syncHighlights", false}, {"syncBooks", false},
                                            {"autoSync", false}});
    // D5：阅读背景分区（mode 四态 light/dark/paper/image；blur 0..1；brightness 0.5..1.5）。
    // 旧键迁移（D5 复审）：B8 时代写 reader/background 三态键。迁移必须在 QML 加载前完成——
    // 若先预置 background/mode=light 再让 QML 侧迁，QML 读到的恒为默认值，分支不可达，
    // 升级用户的深色/米白背景会静默回退浅色。故在预置默认时读旧键作默认 mode，迁移后删除旧键。
    if (!m_root.contains("background")) {
        QString bgMode = QStringLiteral("light");
        // QJsonObject::value 是字面键查找（无点分路径），需逐层取 reader/background
        const QString legacy = m_root.value(QStringLiteral("reader")).toObject()
                                     .value(QStringLiteral("background")).toString();
        if (legacy == QLatin1String("light") || legacy == QLatin1String("paper") || legacy == QLatin1String("dark"))
            bgMode = legacy;
        m_root.insert("background", QJsonObject{{"mode", bgMode}, {"imagePath", ""},
                                                {"blur", 0.0}, {"brightness", 1.0}});
        // 删除旧键并清理空父对象
        QJsonObject reader = m_root.value(QStringLiteral("reader")).toObject();
        reader.remove(QStringLiteral("background"));
        if (reader.isEmpty())
            m_root.remove(QStringLiteral("reader"));
        else
            m_root.insert(QStringLiteral("reader"), reader);
    }
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

// L9（P2#27）：沿 key 链逐级下钻到父对象 remove 尾键（与 insertPath 同递归模式）。
// 与 setValue 不同：中途层缺失/非对象即无操作返回，不产生空对象副作用。
static void removePath(QJsonObject &obj, const QStringList &parts, int idx) {
    if (idx == parts.size() - 1) {
        obj.remove(parts[idx]);
        return;
    }
    if (!obj.value(parts[idx]).isObject()) return; // 键不存在：无操作
    QJsonObject child = obj.value(parts[idx]).toObject();
    removePath(child, parts, idx + 1);
    obj.insert(parts[idx], child);
}

void SettingsStore::removeValue(const QString &dottedKey) {
    removePath(m_root, dottedKey.split('/'), 0);
    save();
}

// D5：背景图片导入——源文件（file:// URL 或本地路径）复制到 AppData/backgrounds/。
// AppData 由 settings.json 所在目录推导（生产与测试注入的目录一致），不用
// QStandardPaths::AppDataLocation：测试进程若走系统 AppData 会写真实用户目录。
// 同名文件覆盖（settings 的 imagePath 始终指向最新副本，无残留引用）。失败返回空串。
QString SettingsStore::copyToBackgrounds(const QString &sourceUrl) {
    const QUrl url(sourceUrl);
    const QString src = url.isLocalFile() ? url.toLocalFile() : sourceUrl;
    if (src.isEmpty() || !QFile::exists(src)) {
        qWarning("SettingsStore: 背景图片源不存在: %s", qPrintable(src));
        return {};
    }
    const QString dir = QFileInfo(m_path).absoluteDir().filePath(QStringLiteral("backgrounds"));
    if (!QDir().mkpath(dir)) {
        qWarning("SettingsStore: 无法创建背景目录 %s", qPrintable(dir));
        return {};
    }
    const QString dest = dir + QLatin1Char('/') + QFileInfo(src).fileName();
    if (QFile::exists(dest) && !QFile::remove(dest)) {
        qWarning("SettingsStore: 无法覆盖旧背景图片 %s", qPrintable(dest));
        return {};
    }
    if (!QFile::copy(src, dest)) {
        qWarning("SettingsStore: 复制背景图片失败 %s -> %s", qPrintable(src), qPrintable(dest));
        return {};
    }
    return dest;
}

void SettingsStore::save() {
    const QByteArray data = QJsonDocument(m_root).toJson(QJsonDocument::Indented);
    const QString tmp = m_path + QStringLiteral(".tmp");
    QFile f(tmp);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("SettingsStore: 无法写入 %s: %s", qPrintable(tmp), qPrintable(f.errorString()));
        return;
    }
    if (f.write(data) != data.size()) {
        qWarning("SettingsStore: 写入 %s 不完整", qPrintable(tmp));
        return;
    }
    f.close();
    // rename 覆盖是原子的；QFile::rename 不覆盖已存在目标，先移除
    QFile::remove(m_path);
    if (!QFile::rename(tmp, m_path))
        qWarning("SettingsStore: rename %s -> %s 失败", qPrintable(tmp), qPrintable(m_path));
}

void SettingsStore::reloadFromDisk() {
    QFile f(m_path);
    if (!f.open(QIODevice::ReadOnly)) return;
    const QByteArray data = f.readAll();
    QJsonParseError err{};
    QJsonObject root = QJsonDocument::fromJson(data, &err).object();
    if (err.error != QJsonParseError::NoError) return; // 盘上损坏：保留内存，不污染
    m_root = root;
    applyDefaults();
}

void SettingsStore::setRoot(const QJsonObject &root) {
    m_root = root;
    applyDefaults();
    save();
}
