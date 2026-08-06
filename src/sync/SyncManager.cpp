#include "SyncManager.h"
#include "../core/DatabaseManager.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>

namespace {

// settings 同步白名单分区：theme/typography/tts。
// webdav（url/账号/密码）与 progress（章内滚动位置）永不出本机、永不写入本地
// （webdav 含凭据；progress 属瞬态阅读状态，且书籍进度由 progress.json 单独同步）。
const QStringList kSyncSections = {QStringLiteral("theme"), QStringLiteral("typography"),
                                   QStringLiteral("tts")};

// 深合并：src 叶子覆盖 target 对应键；两侧都是对象则递归；target 独有键保留。
void mergeSection(QJsonObject &target, const QJsonObject &src) {
    for (auto it = src.constBegin(); it != src.constEnd(); ++it) {
        const QJsonValue &sv = it.value();
        if (sv.isObject() && target.value(it.key()).isObject()) {
            QJsonObject child = target.value(it.key()).toObject();
            mergeSection(child, sv.toObject());
            target.insert(it.key(), child);
        } else {
            target.insert(it.key(), sv);
        }
    }
}

QDateTime parseIso(const QString &text) {
    return QDateTime::fromString(text, Qt::ISODate);
}

} // namespace

SyncManager::SyncManager(const QString &dbPath, const QString &libraryDir, const QString &connection)
    : m_dbPath(dbPath), m_libraryDir(libraryDir) {
    // 打开并迁移 schema（books/highlights 表）；连接名独立于应用各单例
    DatabaseManager dbm(dbPath, connection);
    m_db = dbm.database();
}

QString SyncManager::settingsPath() const {
    return QFileInfo(m_dbPath).absoluteDir().filePath(QStringLiteral("settings.json"));
}

void SyncManager::log(const QString &line) {
    m_log.append(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))
                 + QStringLiteral(" ") + line);
}

// ---- 打包 ----

QByteArray SyncManager::buildSettingsJson() const {
    QFile f(settingsPath());
    if (!f.open(QIODevice::ReadOnly))
        return QJsonDocument(QJsonObject()).toJson(QJsonDocument::Compact); // 无本地设置 → {}
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    // 文件损坏/不可解析 → 空载荷：syncOne 视为"本地数据不可解析"跳过该步并 log，
    // 绝不用空对象覆盖远端（否则 KeepLocal 会把远端设置冲掉）
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QByteArray();
    QJsonObject out;
    const QJsonObject root = doc.object();
    for (const QString &key : kSyncSections)
        if (root.contains(key))
            out.insert(key, root.value(key));
    return QJsonDocument(out).toJson(QJsonDocument::Compact);
}

QByteArray SyncManager::buildProgressJson(const QVector<QPair<qint64, double>> &progress) const {
    // ts 语义：优先该书 last_read_at（本地无时区 → 解析后转 UTC 序列化，跨设备不偏移），
    // 无记录时回退打包时刻。以"最近阅读时刻"而非"打包时刻"作 ts，避免未阅读的同步
    // 以较新打包时间覆盖他端更新的阅读进度（见报告）。
    QHash<qint64, QDateTime> lastRead;
    QSqlQuery q(m_db);
    if (q.exec(QStringLiteral("SELECT id,last_read_at FROM books"))) {
        while (q.next()) {
            const QDateTime d = parseIso(q.value(1).toString());
            if (d.isValid())
                lastRead.insert(q.value(0).toLongLong(), d.toUTC());
        }
    }
    QJsonArray arr;
    for (const auto &p : progress) {
        const auto it = lastRead.constFind(p.first);
        const QDateTime ts = it != lastRead.constEnd() ? it.value() : QDateTime::currentDateTimeUtc();
        arr.append(QJsonObject{{"bookId", p.first},
                               {"progress", p.second},
                               {"ts", ts.toString(Qt::ISODate)}});
    }
    return QJsonDocument(QJsonObject{{"books", arr}}).toJson(QJsonDocument::Compact);
}

QByteArray SyncManager::buildHighlightsJson() const {
    QJsonArray arr;
    QSqlQuery q(m_db);
    if (q.exec(QStringLiteral(
            "SELECT id,book_id,chapter,sentence_index,text,color,note,created_at FROM highlights"))) {
        while (q.next()) {
            arr.append(QJsonObject{
                {"id", q.value(0).toLongLong()},
                {"bookId", q.value(1).toLongLong()},
                {"chapter", q.value(2).toString()},
                {"sentenceIndex", q.value(3).toInt()},
                {"text", q.value(4).toString()},
                {"color", q.value(5).toString()},
                {"note", q.value(6).toString()},
                {"createdAt", q.value(7).toString()},
            });
        }
    }
    return QJsonDocument(QJsonObject{{"highlights", arr}}).toJson(QJsonDocument::Compact);
}

QByteArray SyncManager::buildBooksJson() const {
    QJsonArray arr;
    QSqlQuery q(m_db);
    if (q.exec(QStringLiteral(
            "SELECT id,title,author,publisher,category,format,path,cover,added_at FROM books"))) {
        while (q.next()) {
            arr.append(QJsonObject{
                {"id", q.value(0).toLongLong()},
                {"title", q.value(1).toString()},
                {"author", q.value(2).toString()},
                {"publisher", q.value(3).toString()},
                {"category", q.value(4).toString()},
                {"format", q.value(5).toString()},
                {"path", QDir(m_libraryDir).relativeFilePath(q.value(6).toString())},
                {"cover", q.value(7).toString()},
                {"addedAt", q.value(8).toString()},
            });
        }
    }
    return QJsonDocument(QJsonObject{{"books", arr}}).toJson(QJsonDocument::Compact);
}

// ---- 合并（写回本地） ----

void SyncManager::applySettingsJson(const QByteArray &data) {
    const QJsonObject remote = QJsonDocument::fromJson(data).object();
    if (remote.isEmpty())
        return;
    QJsonObject local;
    QFile f(settingsPath());
    if (f.open(QIODevice::ReadOnly))
        local = QJsonDocument::fromJson(f.readAll()).object();
    for (const QString &key : kSyncSections) {
        if (!remote.contains(key))
            continue;
        const QJsonValue rv = remote.value(key);
        if (rv.isObject()) {
            QJsonObject section = local.value(key).toObject();
            mergeSection(section, rv.toObject());
            local.insert(key, section);
        } else {
            local.insert(key, rv);
        }
    }
    QFile w(settingsPath());
    if (!w.open(QIODevice::WriteOnly))
        return;
    // 与 SettingsStore::save 同格式（Indented），应用侧下次启动读取无差异
    w.write(QJsonDocument(local).toJson(QJsonDocument::Indented));
}

void SyncManager::applyProgressJson(const QByteArray &data) {
    const QJsonObject root = QJsonDocument::fromJson(data).object();
    const QJsonArray arr = root[QStringLiteral("books")].toArray();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        const qint64 id = o[QStringLiteral("bookId")].toVariant().toLongLong();
        const double p = o[QStringLiteral("progress")].toDouble();
        const QDateTime remoteTs = parseIso(o[QStringLiteral("ts")].toString());
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral("SELECT last_read_at FROM books WHERE id=?"));
        q.addBindValue(id);
        if (!q.exec() || !q.next())
            continue; // 本地无此书：进度不能凭空建书，跳过
        const QDateTime localTs = parseIso(q.value(0).toString());
        // 合并语义：远端 ts 有效且不晚于本地最近阅读 → 保留本地（等值重放不写，保证
        // 幂等——同载荷再次同步即 Skip）；否则采用远端（含本地无 last_read_at、
        // 远端 ts 缺失/无法解析两种兜底）
        if (remoteTs.isValid() && localTs.isValid() && remoteTs <= localTs)
            continue;
        QSqlQuery up(m_db);
        up.prepare(QStringLiteral("UPDATE books SET progress=?, last_read_at=? WHERE id=?"));
        up.addBindValue(p);
        // last_read_at 取载荷 ts（转本地无时区格式，与 setProgress 存储一致，MAX 排序不混）：
        // 采用远端后本地内容版本 = 载荷版本，下次同步比较即 Skip，不会"合并即刷新"循环下载
        const QString stamp = remoteTs.isValid()
            ? remoteTs.toLocalTime().toString(Qt::ISODate)
            : QDateTime::currentDateTime().toString(Qt::ISODate);
        up.addBindValue(stamp);
        up.addBindValue(id);
        up.exec();
    }
}

void SyncManager::applyHighlightsJson(const QByteArray &data) {
    const QJsonObject root = QJsonDocument::fromJson(data).object();
    const QJsonArray arr = root[QStringLiteral("highlights")].toArray();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        const qint64 bookId = o[QStringLiteral("bookId")].toVariant().toLongLong();
        const QString chapter = o[QStringLiteral("chapter")].toString();
        const int sentenceIndex = o[QStringLiteral("sentenceIndex")].toInt();
        const QString text = o[QStringLiteral("text")].toString();
        // 去重键 (bookId, chapter, sentenceIndex, text)：id 不参与（跨设备 id 不可信）。
        // IS 匹配正确处理 NULL 字段（chapter/sentence_index 可空）。
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral("SELECT id,color,note FROM highlights WHERE book_id IS ?"
                                 " AND chapter IS ? AND sentence_index IS ? AND text IS ?"));
        q.addBindValue(bookId);
        q.addBindValue(chapter);
        q.addBindValue(sentenceIndex);
        q.addBindValue(text);
        if (q.exec() && q.next()) {
            // 已存在：不重复插入；但远端对同一划线修改过 note/color 时合并过来
            // （LWW：远端为准；无差异不写，保持幂等）
            const QString rColor = o[QStringLiteral("color")].toString();
            const QString rNote = o[QStringLiteral("note")].toString();
            if (q.value(1).toString() != rColor || q.value(2).toString() != rNote) {
                QSqlQuery up(m_db);
                up.prepare(QStringLiteral("UPDATE highlights SET color=?,note=? WHERE id=?"));
                up.addBindValue(rColor);
                up.addBindValue(rNote);
                up.addBindValue(q.value(0).toLongLong());
                up.exec();
            }
            continue;
        }
        QSqlQuery ins(m_db);
        ins.prepare(QStringLiteral("INSERT INTO highlights(book_id,chapter,sentence_index,text,"
                                   "color,note,created_at) VALUES(?,?,?,?,?,?,?)"));
        ins.addBindValue(bookId);
        ins.addBindValue(chapter);
        ins.addBindValue(sentenceIndex);
        ins.addBindValue(text);
        ins.addBindValue(o[QStringLiteral("color")].toString());
        ins.addBindValue(o[QStringLiteral("note")].toString());
        const QString created = o[QStringLiteral("createdAt")].toString();
        ins.addBindValue(created.isEmpty() ? QDateTime::currentDateTime().toString(Qt::ISODate)
                                           : created);
        ins.exec();
    }
}

void SyncManager::applyBooksJson(const QByteArray &data) {
    const QJsonObject root = QJsonDocument::fromJson(data).object();
    const QJsonArray arr = root[QStringLiteral("books")].toArray();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        const qint64 id = o[QStringLiteral("id")].toVariant().toLongLong();
        QSqlQuery chk(m_db);
        chk.prepare(QStringLiteral("SELECT 1 FROM books WHERE id=?"));
        chk.addBindValue(id);
        if (!chk.exec() || !chk.next())
            continue; // 本地无此书：不建书（建书需导入流程/书籍文件，见报告）
        // 只更新静态元数据；path 不覆盖（本机路径指向本机文件），progress/read_seconds
        // 归 progress 项管理，added_at/last_read_at 归本地
        QSqlQuery up(m_db);
        up.prepare(QStringLiteral("UPDATE books SET title=?,author=?,publisher=?,category=?,"
                                  "format=?,cover=? WHERE id=?"));
        up.addBindValue(o[QStringLiteral("title")].toString());
        up.addBindValue(o[QStringLiteral("author")].toString());
        up.addBindValue(o[QStringLiteral("publisher")].toString());
        up.addBindValue(o[QStringLiteral("category")].toString());
        up.addBindValue(o[QStringLiteral("format")].toString());
        up.addBindValue(o[QStringLiteral("cover")].toString());
        up.addBindValue(id);
        up.exec();
    }
}

// ---- 冲突解决 ----

SyncManager::Conflict SyncManager::resolveConflict(const QDateTime &local, const QDateTime &remote) const {
    if (local == remote)
        return Skip;
    return local > remote ? KeepLocal : TakeRemote;
}

// ---- 同步流程 ----

QVector<QPair<qint64, double>> SyncManager::progressPairs() const {
    QVector<QPair<qint64, double>> out;
    QSqlQuery q(m_db);
    if (q.exec(QStringLiteral("SELECT id,progress FROM books WHERE progress > 0"))) {
        while (q.next())
            out.append({q.value(0).toLongLong(), q.value(1).toDouble()});
    }
    return out;
}

void SyncManager::syncOne(WebDavClient &client, const QVector<DavEntry> &remote, const QString &name,
                          const std::function<QByteArray()> &build,
                          const std::function<void(const QByteArray &)> &apply,
                          const QDateTime &localVersion, bool hasLocalData,
                          const std::function<QDateTime(const QByteArray &)> &remoteVersionOf) {
    const DavEntry *remoteEntry = nullptr;
    for (const DavEntry &e : remote) {
        if (e.name == name) {
            remoteEntry = &e;
            break;
        }
    }
    if (!remoteEntry) {
        // 远端不存在：本地有数据 → 上传（首次同步/远端被清空）
        if (hasLocalData) {
            const QByteArray payload = build();
            if (payload.isEmpty()) {
                log(QStringLiteral("跳过 %1: 本地数据不可解析").arg(name));
                return;
            }
            if (client.put(name, payload))
                log(QStringLiteral("上传 %1").arg(name));
            else
                log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
        }
        return;
    }
    if (!hasLocalData) {
        // 本地无数据：下载并应用（新设备首次同步）
        const QByteArray data = client.get(name);
        if (!client.lastError().isEmpty()) {
            log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
            return;
        }
        apply(data);
        log(QStringLiteral("下载 %1").arg(name));
        return;
    }
    // 两边都有：取远端版本。内容类项目需先 GET 载荷提取内容 ts（与本地同钟，比较才收敛）；
    // 载荷无法解析时退回文件 mtime。settings 缺省直接比文件 mtime（同钟，见 sync() 截断）。
    QByteArray remoteData;
    QDateTime remoteVersion = remoteEntry->modified;
    if (remoteVersionOf) {
        remoteData = client.get(name);
        if (!client.lastError().isEmpty()) {
            log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
            return;
        }
        const QDateTime content = remoteVersionOf(remoteData);
        if (content.isValid())
            remoteVersion = content;
    }
    switch (resolveConflict(localVersion, remoteVersion)) {
    case KeepLocal:
        // 本地内容较新 → 主动重传（新进度借此传播），同时远端版本前移、下次同内容即 Skip
        {
            const QByteArray payload = build();
            if (payload.isEmpty()) {
                log(QStringLiteral("跳过 %1: 本地数据不可解析").arg(name));
                return;
            }
            if (client.put(name, payload))
                log(QStringLiteral("保留本地 %1").arg(name));
            else
                log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
        }
        break;
    case TakeRemote: {
        if (remoteData.isEmpty())
            remoteData = client.get(name);
        if (!client.lastError().isEmpty()) {
            log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
            return;
        }
        apply(remoteData);
        log(QStringLiteral("采用远端 %1").arg(name));
        break;
    }
    case Skip:
        log(QStringLiteral("跳过 %1").arg(name));
        break;
    }
}

void SyncManager::syncBookBodies(WebDavClient &client, const QVector<DavEntry> &remote) {
    // 上传：本地书籍文件体缺失于远端 → 远端名 b<id>_<basename>（扁平命名，list() depth 1 可见）
    QSqlQuery q(m_db);
    if (q.exec(QStringLiteral("SELECT id,path FROM books"))) {
        while (q.next()) {
            const qint64 id = q.value(0).toLongLong();
            const QString path = q.value(1).toString();
            if (!QFileInfo::exists(path))
                continue;
            const QString name = QStringLiteral("b%1_%2").arg(id).arg(QFileInfo(path).fileName());
            bool present = false;
            for (const DavEntry &e : remote) {
                if (e.name == name) {
                    present = true;
                    break;
                }
            }
            if (present)
                continue; // 远端已有同名校验体：按需跳过
            QFile f(path);
            if (!f.open(QIODevice::ReadOnly))
                continue;
            if (client.put(name, f.readAll()))
                log(QStringLiteral("上传书籍 %1").arg(name));
            else
                log(QStringLiteral("失败 %1: %2").arg(name, client.lastError()));
        }
    }
    // 下载：远端书籍文件体缺失于本地 → 写入 libraryDir/books/<basename>
    // 文件名白名单校验：仅接受 b<id>_<basename> 且 basename 无路径分隔符/无 ".."，
    // 防恶意远端用路径穿越写出 libraryDir（见报告）。
    const QRegularExpression re(QStringLiteral("^b(\\d+)_([^/]+)$"));
    for (const DavEntry &e : remote) {
        const QRegularExpressionMatch m = re.match(e.name);
        if (!m.hasMatch())
            continue;
        const QString basename = m.captured(2);
        if (basename.contains(QStringLiteral("..")))
            continue;
        const QString dest = m_libraryDir + QStringLiteral("/books/") + basename;
        if (QFile::exists(dest))
            continue;
        const QByteArray data = client.get(e.name);
        if (!client.lastError().isEmpty())
            continue;
        QDir().mkpath(QFileInfo(dest).absolutePath());
        QFile out(dest);
        if (out.open(QIODevice::WriteOnly) && out.write(data) == data.size())
            log(QStringLiteral("下载书籍 %1").arg(e.name));
    }
}

// 从载荷数组取最大内容时间戳（progress 的 ts / highlights 的 createdAt / books 的 addedAt）；
// 无效（数组空或全无时间戳）→ 返回无效 QDateTime，syncOne 退回文件 mtime 比较
static QDateTime maxContentTs(const QJsonArray &arr, const char *key) {
    QDateTime best;
    for (const QJsonValue &v : arr) {
        const QDateTime t = parseIso(v.toObject().value(QLatin1String(key)).toString());
        if (t.isValid() && (!best.isValid() || t > best))
            best = t;
    }
    return best;
}

void SyncManager::sync(WebDavClient &client, const Options &opts) {
    // 快照式决策：list() 只取一次（简报"client.list() 得远端文件与 mtime"），
    // 单次同步内所有项的 有无/冲突 判定基于同一快照。
    const QVector<DavEntry> remote = client.list();
    if (opts.settings) {
        const QString path = settingsPath();
        // settings 无载荷内版本：用文件 mtime 与远端 mtime 比较（同钟）。本地截断到秒级
        // ——远端 getlastmodified 秒级，同秒内写入视为同一版本，避免毫秒恒胜导致同秒反复
        // 重传（见报告"复审修复"）。
        const QDateTime fileMtime = QFileInfo(path).lastModified();
        const QDateTime localVersion = fileMtime.isValid()
            ? QDateTime::fromSecsSinceEpoch(fileMtime.toSecsSinceEpoch())
            : QDateTime();
        syncOne(client, remote, QStringLiteral("settings.json"),
                [this] { return buildSettingsJson(); },
                [this](const QByteArray &d) { applySettingsJson(d); },
                localVersion, QFile::exists(path));
    }
    if (opts.progress) {
        // 本地版本 = 最新最近阅读时刻（载荷 ts 与本地 last_read_at 同钟，比较收敛）
        QDateTime localVersion;
        QSqlQuery q(m_db);
        if (q.exec(QStringLiteral("SELECT MAX(last_read_at) FROM books WHERE progress > 0"))
            && q.next()) {
            const QDateTime d = parseIso(q.value(0).toString());
            if (d.isValid())
                localVersion = d;
        }
        syncOne(client, remote, QStringLiteral("progress.json"),
                [this] { return buildProgressJson(progressPairs()); },
                [this](const QByteArray &d) { applyProgressJson(d); },
                localVersion, !progressPairs().isEmpty(),
                [](const QByteArray &d) {
                    return maxContentTs(QJsonDocument::fromJson(d).object()
                                            [QStringLiteral("books")].toArray(),
                                        "ts");
                });
    }
    if (opts.highlights) {
        QDateTime localVersion;
        QSqlQuery q(m_db);
        if (q.exec(QStringLiteral("SELECT MAX(created_at) FROM highlights")) && q.next()) {
            const QDateTime d = parseIso(q.value(0).toString());
            if (d.isValid())
                localVersion = d;
        }
        bool hasData = false;
        if (q.exec(QStringLiteral("SELECT COUNT(*) FROM highlights")) && q.next())
            hasData = q.value(0).toLongLong() > 0;
        syncOne(client, remote, QStringLiteral("highlights.json"),
                [this] { return buildHighlightsJson(); },
                [this](const QByteArray &d) { applyHighlightsJson(d); },
                localVersion, hasData,
                [](const QByteArray &d) {
                    return maxContentTs(QJsonDocument::fromJson(d).object()
                                            [QStringLiteral("highlights")].toArray(),
                                        "createdAt");
                });
    }
    if (opts.books) {
        QDateTime localVersion;
        QSqlQuery q(m_db);
        if (q.exec(QStringLiteral("SELECT MAX(added_at) FROM books")) && q.next()) {
            const QDateTime d = parseIso(q.value(0).toString());
            if (d.isValid())
                localVersion = d;
        }
        bool hasData = false;
        if (q.exec(QStringLiteral("SELECT COUNT(*) FROM books")) && q.next())
            hasData = q.value(0).toLongLong() > 0;
        syncOne(client, remote, QStringLiteral("books.json"),
                [this] { return buildBooksJson(); },
                [this](const QByteArray &d) { applyBooksJson(d); },
                localVersion, hasData,
                [](const QByteArray &d) {
                    return maxContentTs(QJsonDocument::fromJson(d).object()
                                            [QStringLiteral("books")].toArray(),
                                        "addedAt");
                });
        syncBookBodies(client, remote);
    }
}
