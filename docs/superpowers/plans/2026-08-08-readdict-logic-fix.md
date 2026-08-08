# Readdict 后端逻辑修复（L 阶段）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修复规格 `2026-08-08-readdict-kindle-ui2-design.md` §5 列出的 P0×7、P1×11、高价值 P2×15 后端逻辑问题，UI 样式不动（仅必要的调用点接线），为 U 阶段 UI 对齐提供稳定契约。

**架构：** 沿用现有分层（C++ 单例 + QML）。核心收敛：settings.json 唯一写者 = SettingsStore 单例；SyncManager 经单例合并；书体同步哈希命名并经导入管线注册；解析错误上抛 QML。

**技术栈：** Qt 6.11.1（Core/Sql/Network/Multimedia/TextToSpeech）、Qt Test、CMake ≥3.21。

**构建/测试命令（每任务通用）：**
- 构建：`cmake --build build --parallel`（仓库根执行；build/ 已配置）
- 单测：`ctest --test-dir build -R <名称> --output-on-failure`
- 全量：`ctest --test-dir build --output-on-failure`

**commit 约定：** 简体中文 message，格式 `fix:` / `refactor:` / `test:` 前缀。

---

## 文件结构

| 文件 | 职责变更 |
|---|---|
| `src/core/SettingsStore.h/.cpp` | 原子写、reloadFromDisk、损坏备份、root()/setRoot()、applyDefaults 抽取 |
| `src/sync/SyncManager.h/.cpp` | 改 QObject；setSettingsStore/setAdoptHandler；applySettingsJson 经单例；书体哈希命名+adopt 钩子；apply* 事务+孤儿跳过；sync 返回 Result；syncApplied 信号 |
| `src/sync/SyncController.h/.cpp` | 注入 SettingsStore；用结构化 Result 判败；dataChanged 转发 |
| `src/core/BookImporter.h/.cpp` | adoptFile（跳过复制的注册路径）；backfill 失败标记；importFile 删 move 参数 |
| `src/core/BookManager.h/.cpp` | bookByIdModel；reportProgress（进度取 max + 刷新 last_read_at）；chapterCount 缓存；savePosition 变化写；removeBook 级联；loadChapter 去副作用+error 上抛 |
| `src/core/HighlightManager.h/.cpp` | addHighlight 增 chapterIndex；排序 (chapter_index,sentence_index)；backfillChapterIndexes |
| `src/core/DatabaseManager.cpp` | 迁移 v2（highlights.chapter_index）；迁移失败 qFatal |
| `src/parsers/*` | ParserFactory::parse 增 error 出参；各解析器 lastError；TextParser 删 inPre |
| `src/tts/TtsController.h/.cpp` | reconfigure 先 stop；删 currentSentence/atEnd/seekTo |
| `src/main.cpp` | 注入接线（Settings/Sync/Importer）、tts 键迁移 |
| QML 调用点 | ReaderContent（addHighlight 参/错误页）、ReaderPage（reportProgress/错误页/savePosition）、ShelfPage（bookByIdModel/catFilter 按值）、SyncPage（即写）、SettingsPage（三态）、TtsBar（语速/键）、SettingsTtsPage（键）、PdfReaderPage（节流） |
| `tests/*` | 各用例适配与新增 |

---

### 任务 L1：SettingsStore 原子写 + reload + 损坏备份

**文件：**
- 修改：`src/core/SettingsStore.h`、`src/core/SettingsStore.cpp`
- 测试：`tests/tst_settings.cpp`

- [ ] **步骤 1：编写失败测试**

在 `tests/tst_settings.cpp` 的 `private slots:` 内追加：

```cpp
    void atomicSaveLeavesNoTmpAndReloads() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        SettingsStore s(path);
        s.setValue("tts/engine", "openai");
        QVERIFY(!QFile::exists(path + ".tmp"));           // 无临时文件残留
        SettingsStore s2(path);
        QCOMPARE(s2.value("tts/engine").toString(), QString("openai"));
    }
    void reloadFromDiskPicksExternalChange() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        SettingsStore s(path);
        // 外部写者（模拟同步）直接改盘
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("{\"theme\":{\"mode\":\"dark\"},\"tts\":{\"engine\":\"system\"}}");
        f.close();
        QCOMPARE(s.value("theme/mode").toString(), QString("auto")); // 内存仍是旧值
        s.reloadFromDisk();
        QCOMPARE(s.value("theme/mode").toString(), QString("dark"));
    }
    void corruptFileBackedUpNotSilentlyReset() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        {
            QFile f(path);
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write("{\"theme\":{\"mode\":\"dark\"}, trailing garbage");
        }
        SettingsStore s(path);
        QCOMPARE(s.value("theme/mode").toString(), QString("auto")); // 回退默认
        // 原损坏内容已备份，且备份文件存在
        const QStringList backups = QDir(dir.path()).entryList(QStringList() << "settings.json.corrupt-*");
        QCOMPARE(backups.size(), 1);
        QFile b(dir.path() + "/" + backups.first());
        QVERIFY(b.open(QIODevice::ReadOnly));
        QVERIFY(b.readAll().contains("trailing garbage"));
    }
    void setRootPersistsAndPreservesViaValue() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/settings.json";
        SettingsStore s(path);
        QJsonObject root = s.root();
        root.insert("webdav", QJsonObject{{"url", "https://x"}});
        s.setRoot(root);
        SettingsStore s2(path);
        QCOMPARE(s2.value("webdav/url").toString(), QString("https://x"));
        QCOMPARE(s2.value("theme/mode").toString(), QString("auto")); // 默认分区仍在
    }
```

- [ ] **步骤 2：运行测试验证失败**

运行：`cmake --build build --parallel && ctest --test-dir build -R tst_settings --output-on-failure`
预期：编译失败（reloadFromDisk/root/setRoot 未声明）。

- [ ] **步骤 3：实现**

`SettingsStore.h` 追加 public 方法：

```cpp
    // 从磁盘重读并替换内存根对象（同步合并后调用），随后补默认分区
    void reloadFromDisk();
    QJsonObject root() const { return m_root; }
    // 整体替换根对象并原子落盘（同步合并写盘的唯一入口）
    void setRoot(const QJsonObject &root);
```

`SettingsStore.cpp`：

1. 构造函数中默认值预置段（theme/typography/tts/reading/webdav/background 及旧键迁移）整体抽为私有方法 `void applyDefaults()`，构造函数改为：读盘（含损坏备份逻辑）→ `applyDefaults()` → `save()`。
2. 读盘段改为：

```cpp
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
```

（需 `#include <QDateTime>`、`<QJsonParseError>`。）

3. `save()` 改原子写：

```cpp
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
```

4. 新增：

```cpp
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
```

- [ ] **步骤 4：运行测试验证通过**

运行：`ctest --test-dir build -R tst_settings --output-on-failure`
预期：PASS（含既有用例）。

- [ ] **步骤 5：Commit**

```bash
git add src/core/SettingsStore.h src/core/SettingsStore.cpp tests/tst_settings.cpp
git commit -m "fix: SettingsStore 原子写、reloadFromDisk 与损坏备份（P0#4）"
```

---

### 任务 L2：同步设置合并经单例

**文件：**
- 修改：`src/sync/SyncManager.h/.cpp`、`src/sync/SyncController.h/.cpp`、`src/main.cpp`
- 测试：`tests/tst_syncmanager.cpp`、`tests/tst_synccontroller.cpp`

- [ ] **步骤 1：编写失败测试**

`tests/tst_syncmanager.cpp` 追加（该文件已有 SyncManager 直连 :memory: 的夹具模式，沿用其构造方式；新增 SettingsStore 注入）：

```cpp
    void applySettingsGoesThroughStore() {
        // 夹具：临时目录 settings.json + 单例 SettingsStore
        QTemporaryDir dir;
        auto *store = new SettingsStore(dir.path() + "/settings.json");
        store->setValue("theme/mode", "light");
        SyncManager mgr(dir.path() + "/Readdict.db", dir.path(), "readdict_sync_t1");
        mgr.setSettingsStore(store);
        const QByteArray remote = QByteArrayLiteral(
            "{\"theme\":{\"mode\":\"dark\"},\"typography\":{\"fontSize\":22}}");
        QVERIFY(mgr.applySettingsJson(remote));
        // 单例内存即时可见（不再被旧快照覆盖）
        QCOMPARE(store->value("theme/mode").toString(), QString("dark"));
        QCOMPARE(store->value("typography/fontSize").toInt(), 22);
        // 未提及分区保留
        QCOMPARE(store->value("webdav/syncProgress").toBool(), true);
        // 单例后续 setValue 不冲掉同步结果
        store->setValue("tts/rate", 1.5);
        QCOMPARE(store->value("theme/mode").toString(), QString("dark"));
    }
```

- [ ] **步骤 2：运行验证失败**（setSettingsStore 未声明，编译失败）

- [ ] **步骤 3：实现**

`SyncManager.h`：前向声明 `class SettingsStore;`，追加：

```cpp
    void setSettingsStore(SettingsStore *s) { m_settings = s; }
    // ... 成员区追加：
    SettingsStore *m_settings = nullptr;
```

`SyncManager.cpp` `applySettingsJson` 尾段（现 244-252 行直写文件）替换为：

```cpp
    if (local == before)
        return true;
    if (m_settings) {
        // 唯一写者路径：合并结果经单例原子落盘并刷新内存，杜绝旧快照覆盖
        m_settings->setRoot(local);
        return true;
    }
    // 无单例注入（纯单元测试夹具）：原子直写兜底
    const QString tmp = settingsPath() + QStringLiteral(".tmp");
    QFile w(tmp);
    if (!w.open(QIODevice::WriteOnly))
        return false;
    const QByteArray out = QJsonDocument(local).toJson(QJsonDocument::Indented);
    if (w.write(out) != out.size()) return false;
    w.close();
    QFile::remove(settingsPath());
    return QFile::rename(tmp, settingsPath());
```

（`before`/`local` 的构建逻辑保持不变；`#include "../core/SettingsStore.h"`。）

`SyncController.h/.cpp`：追加 `void setSettingsStore(SettingsStore *s)`，内部 `m_mgr.setSettingsStore(s)` 并保存指针 `m_store`；`doSync` 与定时器 lambda 中 `SettingsStore st(settingsPath())` 临时构造改为：

```cpp
    SettingsStore *st = m_store;
    SettingsStore fallback(settingsPath());   // 仅未注入时（测试旧夹具）
    if (!st) st = &fallback;
```

读取 opts 用 `st->value(...)`（P2#30：注入路径不再触发临时实例的构造 save）。

`main.cpp`：`syncController` 创建后追加 `syncController->setSettingsStore(settings);`。

- [ ] **步骤 4：适配既有用例**——`tst_syncmanager.cpp` 中直接断言 settings.json 文件内容的旧用例改为注入 SettingsStore 后断言单例值（模式同步骤 1）。`tests/CMakeLists.txt` 的 tst_syncmanager 源列表追加 `../src/core/SettingsStore.cpp`（注入需要）。

- [ ] **步骤 5：运行 + Commit**

```bash
ctest --test-dir build -R "tst_syncmanager|tst_synccontroller" --output-on-failure
git add -A src/sync src/main.cpp tests/tst_syncmanager.cpp tests/tst_synccontroller.cpp
git commit -m "fix: 同步设置合并经 SettingsStore 单例，杜绝内存快照覆盖（P0#2）"
```

---

### 任务 L3：书体同步哈希命名 + 导入注册

**文件：**
- 修改：`src/core/BookImporter.h/.cpp`、`src/sync/SyncManager.h/.cpp`、`src/main.cpp`
- 测试：`tests/tst_syncmanager.cpp`、`tests/tst_bookimporter.cpp`
- 注：SyncManager 不直接依赖 BookImporter 类型——adopt 经 `std::function<QString(const QString &path)>` 钩子注入（`setAdoptHandler`），main.cpp 接线 `importer->adoptFile`，tst_syncmanager 无需链接 BookImporter。

- [ ] **步骤 1：编写失败测试**

`tests/tst_bookimporter.cpp` 追加：

```cpp
    void adoptFileRegistersWithoutCopy() {
        // 已在书库目录内的文件（模拟同步下载落盘）→ adoptFile 直接注册不复制
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/books");
        const QString src = QStringLiteral(EPUB_FIXTURES_DIR) + "/sample.epub";
        const QString dest = dir.path() + "/books/sample.epub";
        QVERIFY(QFile::copy(src, dest));
        BookImporter imp(dir.path(), dir.path() + "/Readdict.db");
        const QString err = imp.adoptFile(dest);
        QVERIFY2(err.isEmpty(), qPrintable(err));
        bool found = false;
        for (const Book &b : imp.books())
            if (b.path == dest) found = true;
        QVERIFY(found); // 注册且 path 指向原文件（无二次复制）
    }
```

`tests/tst_syncmanager.cpp` 追加：

```cpp
    void bookBodyNamesUseContentHash() {
        QTemporaryDir dir;
        QDir().mkpath(dir.path() + "/books");
        const QString dbPath = dir.path() + "/Readdict.db";
        QSqlDatabase db = seedDb(dbPath);
        // 书库内真实文件（写任意字节，哈希对其内容计算）
        const QString dest = dir.path() + "/books/sample.epub";
        QFile f(dest);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QByteArray(300000, 'x'));
        f.close();
        seedBook(db, 1, "样书", 0.0, "2026-01-01T00:00:00");
        QSqlQuery upd(db);
        upd.exec(QStringLiteral("UPDATE books SET path='%1' WHERE id=1").arg(dest));
        SyncManager mgr(dbPath, dir.path(), "readdict_sync_h1");
        QStringList adopted;
        mgr.setAdoptHandler([&adopted](const QString &p) { adopted.append(p); return QString(); });
        MockWebDavClient client;
        SyncManager::Options opts;
        opts.books = true;
        mgr.sync(client, opts);
        // 上传名 = h<16hex>_<basename>
        QCOMPARE(client.putNames.size(), 1);
        QVERIFY2(QRegularExpression("^h[0-9a-f]{16}_sample\\.epub$")
                     .match(client.putNames.first()).hasMatch(),
                 qPrintable(client.putNames.first()));
        // 下载端：清空本地文件表重开 → 同 mock 远端再 sync，adopt 钩子收到落盘路径
        QStringList downloaded;
        mgr.setAdoptHandler([&downloaded](const QString &p) { downloaded.append(p); return QString(); });
        QFile::remove(dest);
        SyncManager mgr2(dbPath, dir.path(), "readdict_sync_h2");
        mgr2.setAdoptHandler([&downloaded](const QString &p) { downloaded.append(p); return QString(); });
        mgr2.sync(client, opts);
        QCOMPARE(downloaded.size(), 1);
        QVERIFY(downloaded.first().endsWith("sample.epub"));
        QVERIFY(QFile::exists(downloaded.first())); // 落盘成功
    }

- [ ] **步骤 2：运行验证失败**（adoptFile 未声明）

- [ ] **步骤 3：实现 BookImporter::adoptFile**

`BookImporter.h` 追加：

```cpp
    // 同步下载落盘后的注册入口：文件已在书库目录内，跳过复制直接走
    // 解析→addBook→封面→索引；成功返回空串。去重：(title,author,format)
    // 或 path 命中已有书 → 仅返回空串不重复注册。
    QString adoptFile(const QString &pathInLibrary);
```

`BookImporter.cpp`：把 `importFile` 中「复制文件入库」之后的「detectFormat→parse→addBook→封面→indexBook」段抽为私有 `QString registerBook(const QString &destPath, const QString &format, qint64 *importedId)`；`importFile` = 复制 + registerBook；`adoptFile` = 去重检查 + registerBook（不复制）。

- [ ] **步骤 4：实现 SyncManager 哈希命名**

`SyncManager.cpp` `syncBookBodies` 重写命名与下载注册：

```cpp
#include <QCryptographicHash>
// 上传段：
            QFile f(path);
            if (!f.open(QIODevice::ReadOnly)) continue;
            const QByteArray head = f.read(262144);           // 前 256KB
            const QString hash = QString::fromLatin1(
                QCryptographicHash::hash(head, QCryptographicHash::Sha1).toHex().left(16));
            const QString name = QStringLiteral("h%1_%2").arg(hash, QFileInfo(path).fileName());
            // ...present 检查同旧逻辑（同时兼容旧 b<id>_ 前缀视为已存在，避免重复上传）
            f.seek(0);
            if (client.put(name, f.readAll())) ...
// 下载段：正则改 ^(?:h[0-9a-f]{16}|b\d+)_([^/]+)$ ；落盘后：
        if (m_adopt) {
            const QString regErr = m_adopt(dest);
            log(regErr.isEmpty() ? QStringLiteral("下载并注册书籍 %1").arg(e.name)
                                 : QStringLiteral("注册失败 %1: %2").arg(e.name, regErr));
        } else {
            log(QStringLiteral("下载书籍 %1").arg(e.name));
        }
```

`SyncManager.h` 追加 `void setAdoptHandler(std::function<QString(const QString &)> h) { m_adopt = std::move(h); }` 与成员 `std::function<QString(const QString &)> m_adopt;`。`main.cpp`：`syncController->setAdoptHandler([importer](const QString &p) { return importer->adoptFile(p); });`（经 SyncController 新增同名转发方法）。

- [ ] **步骤 5：运行 + Commit**

```bash
ctest --test-dir build -R "tst_syncmanager|tst_bookimporter" --output-on-failure
git commit -m "fix: 书体同步内容哈希命名并经导入管线注册（P0#3）"
```

---

### 任务 L4：解析错误上抛 + backfill 失败标记

**文件：**
- 修改：`src/parsers/ParserFactory.h/.cpp`、`EpubParser.h/.cpp`、`Fb2Parser.h/.cpp`、`TextParser.h/.cpp`、`src/core/BookManager.cpp`、`src/core/BookImporter.cpp`、`src/ui/qml/ReaderPage.qml`
- 测试：`tests/tst_parserfactory.cpp`、`tests/tst_bookmanager.cpp`

- [ ] **步骤 1：编写失败测试**

`tests/tst_parserfactory.cpp` 追加：

```cpp
    void errorOutParamReportsDrmAndMissing() {
        QString err;
        ParserFactory::parse(QStringLiteral("/nonexistent/x.mobi"), "MOBI", &err);
        QVERIFY(!err.isEmpty()); // 文件不存在错误上抛
        // DRM fixture（若 fixtures 含 drm.mobi 则断言含 "DRM"，否则跳过该断言）
    }
    void successLeavesErrorEmpty() {
        QString err;
        ParserFactory::parse(QStringLiteral(PARSER_FIXTURES_DIR) + "/sample.epub", "EPUB", &err);
        QVERIFY(err.isEmpty());
    }
```

- [ ] **步骤 2：运行验证失败**（parse 无第三参，编译失败）

- [ ] **步骤 3：实现解析器 lastError**

- `ParserFactory.h/.cpp`：`static DocumentModel parse(const QString &filePath, const QString &format, QString *error = nullptr);` 各分支调用具体解析器后 `if (error) *error = parser.lastError();`。
- `MobiParser` 已有 `lastError()`；`EpubParser/Fb2Parser/TextParser` 各加 `QString m_error` + `lastError()`，在既有失败分支（文件不存在/zip 打开失败/XML 失败等）赋值，成功路径 `m_error.clear()`。
- `BookManager::documentFor`：解析后若 `doc.empty()` 记录 `m_docError[bookId] = err`（`QHash<qint64,QString>` 成员）；`loadChapter` 开头：

```cpp
    const DocumentModel doc = documentFor(bookId);
    if (doc.empty() && m_docError.value(bookId).isEmpty() == false) {
        QVariantMap out;
        out.insert("error", m_docError.value(bookId));
        return out;
    }
```

（空文档且无错误（如零章 TXT）维持旧行为返回空 map。）

- [ ] **步骤 4：backfill 失败标记（P2#31）**

`BookImporter.cpp` `backfillNext`：索引前检查标记文件 `m_libraryDir + "/.readdict_index_fail.json"`（`QJsonObject{id: 次数}`）；`indexBook` 内解析失败（documentFor 空）时次数 +1 写回；次数 ≥2 的书 backfill 跳过。

- [ ] **步骤 5：ReaderPage 最小错误占位**

`ReaderPage.qml` 加载章节回调中：若 `chapter.error` 存在，置 `property string loadError`，内容区显示居中 Label（`text: loadError`，`color: UITheme.danger`）+ 重试 Button（重调 loadChapter）；否则清空。样式 U 阶段再对齐。

- [ ] **步骤 6：运行 + Commit**

```bash
ctest --test-dir build -R "tst_parserfactory|tst_bookmanager" --output-on-failure
git commit -m "fix: 解析错误上抛 QML 错误页与 backfill 失败标记（P0#5/P2#31）"
```

---

### 任务 L5：highlights chapter_index 列与跨章排序

**文件：**
- 修改：`src/core/DatabaseManager.cpp`、`src/core/HighlightManager.h/.cpp`、`src/sync/SyncManager.cpp`、`src/ui/qml/ReaderContent.qml`、`src/ui/qml/ReaderPage.qml`
- 测试：`tests/tst_highlights.cpp`、`tests/tst_syncmanager.cpp`

- [ ] **步骤 1：编写失败测试**

`tests/tst_highlights.cpp` 追加：

```cpp
    void crossChapterOrderFollowsChapterIndex() {
        // 第 2 章句 0 先插入、第 1 章句 5 后插入 → 列表仍第 1 章在前
        HighlightManager h(dbPath, "readdict_h_t1");
        h.addHighlight(1, "第2章", 0, "t2", "#FF0", {}, 2);
        h.addHighlight(1, "第1章", 5, "t1", "#FF0", {}, 1);
        const QVariantList list = h.highlightsForBook(1);
        QCOMPARE(list.size(), 2);
        QCOMPARE(list.first().toMap().value("chapter").toString(), QString("第1章"));
        QCOMPARE(list.first().toMap().value("chapterIndex").toInt(), 1);
    }
    void backfillChapterIndexesMapsTitles() {
        HighlightManager h(dbPath, "readdict_h_t2");
        h.addHighlight(1, "第2章", 0, "t2", "#FF0", {}, 0); // 旧行 chapter_index=0
        h.backfillChapterIndexes(1, QVariantList{QStringLiteral("第1章"), QStringLiteral("第2章")});
        const QVariantList list = h.highlightsForBook(1);
        QCOMPARE(list.first().toMap().value("chapterIndex").toInt(), 2);
    }
```

（addHighlight 新签名末参 chapterIndex；既有调用点补默认值 0 编译适配。）

- [ ] **步骤 2：运行验证失败**

- [ ] **步骤 3：迁移 v2**

`DatabaseManager.cpp` `migrate()` 开头 `if (schemaVersion() >= 1) return;` 改为增量：

```cpp
    const int v = schemaVersion();
    if (v < 1) { /* 既有 v0→v1 建表 steps，保持原事务结构 */ }
    if (v < 2) {
        // v1→v2：highlights 增 chapter_index（旧行默认 0，经 backfillChapterIndexes 回填）
        QSqlQuery q2(m_db);
        if (!q2.exec("BEGIN") || !q2.exec("ALTER TABLE highlights ADD COLUMN chapter_index INTEGER DEFAULT 0")
            || !q2.exec("PRAGMA user_version = 2") || !q2.exec("COMMIT"))
            qFatal("数据库迁移 v2 失败: %s", qPrintable(q2.lastError().text()));
    }
```

- [ ] **步骤 4：HighlightManager 改签名与排序**

- `addHighlight(..., const QString &note = {}, int chapterIndex = 0)`：INSERT 列加 chapter_index。
- `highlightsForBook`：SELECT 加 chapter_index，`ORDER BY chapter_index, sentence_index, id`；输出 map 加 `chapterIndex`。
- 新增 `Q_INVOKABLE void backfillChapterIndexes(qint64 bookId, const QVariantList &titles)`：对每个 title（索引 i 从 1 起）`UPDATE highlights SET chapter_index=? WHERE book_id=? AND chapter=? AND (chapter_index IS 0 OR chapter_index IS NULL)`。

- [ ] **步骤 5：同步载荷携带 chapterIndex**

`SyncManager.cpp`：`buildHighlightsJson` 每行加 `"chapterIndex"`；`applyHighlightsJson` INSERT/去重读取 `o["chapterIndex"].toInt()` 写入列（缺失默认 0）。

- [ ] **步骤 6：QML 调用点接线**

`ReaderContent.qml` 479/493 两处 `Highlights.addHighlight(...)` 追加末参 `flick.chapterIndex`（该属性已存在于 flickable 上下文，见 chapter 加载逻辑；若无则用 ReaderPage 的 currentChapter 传入）。`ReaderPage.qml` 打开书/章节标题加载后调用 `Highlights.backfillChapterIndexes(book.id, titles)`。

- [ ] **步骤 7：运行 + Commit**

```bash
ctest --test-dir build -R "tst_highlights|tst_syncmanager" --output-on-failure
git commit -m "fix: 划线增 chapter_index 列，笔记按阅读顺序排序（P0#6）"
```

---

### 任务 L6：BookManager 进度语义与查询契约

**文件：**
- 修改：`src/core/BookManager.h/.cpp`、`src/ui/qml/ShelfPage.qml`、`src/ui/qml/ReaderPage.qml`
- 测试：`tests/tst_bookmanager.cpp`

- [ ] **步骤 1：编写失败测试**

```cpp
    void progressNeverRegresses() {
        // 读到 50% 后跳回第 1 章 → progress 保持 0.5
        BookManager m(dbPath, "readdict_bm_t1");
        const qint64 id = addSampleBook(m);
        m.reportProgress(id, 5, 10);   // 0.6
        m.reportProgress(id, 0, 10);   // 0.1 → 不 regress
        QCOMPARE(m.bookById(id).progress, 0.6);
    }
    void bookByIdModelIgnoresFilter() {
        BookManager m(dbPath, "readdict_bm_t2");
        const qint64 a = addSampleBook(m, "分类A");
        const qint64 b = addSampleBook(m, "分类B");
        m.setFilter("分类A");
        QCOMPARE(m.bookByIdModel(b).value("id").toLongLong(), b); // 过滤外仍可查
    }
    void chapterCountCached() {
        BookManager m(dbPath, "readdict_bm_t3");
        const qint64 id = addSampleBookFromEpub(m);
        m.chapterTitles(id);
        QCOMPARE(m.chapterCount(id), /* sample.epub 章节数 */ 3);
    }
```

（辅助函数 addSampleBook 沿用文件既有夹具；章节数按 fixtures/sample.epub 实际值填写。）

- [ ] **步骤 2：运行验证失败**

- [ ] **步骤 3：实现**

`BookManager.h`：

```cpp
    Q_INVOKABLE QVariantMap bookByIdModel(qint64 id) const;  // 全库查，不受 filter/search 影响
    Q_INVOKABLE void reportProgress(qint64 id, int chapterOneBased, int totalChapters);
    Q_INVOKABLE int chapterCount(qint64 bookId);             // 缓存值（chapterTitles/loadChapter 时刷新）
```

`BookManager.cpp`：

- `bookByIdModel`：`selectBooks("id=" + id, "")` 或直接 `bookById` 转 QVariantMap（复用 booksModel 的单行构造，抽私有 `static QVariantMap bookToMap(const Book&)`，booksModel 改用它）。
- `reportProgress`：

```cpp
void BookManager::reportProgress(qint64 id, int ch1, int total) {
    if (total <= 0) return;
    const double p = double(ch1) / total;
    QSqlQuery q(m_db);
    q.prepare("SELECT progress FROM books WHERE id=?");
    q.addBindValue(id);
    double old = 0;
    if (q.exec() && q.next()) old = q.value(0).toDouble();
    QSqlQuery up(m_db);
    if (p > old) {
        up.prepare("UPDATE books SET progress=?, last_read_at=? WHERE id=?");
        up.addBindValue(p);
    } else {
        up.prepare("UPDATE books SET last_read_at=? WHERE id=?"); // 位置变化不 regress 进度
        up.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
        up.addBindValue(id);
        if (!up.exec()) return;
        return; // 进度未变：不 emit（避免书架模型重建，P1#13）
    }
    up.addBindValue(QDateTime::currentDateTime().toString(Qt::ISODate));
    up.addBindValue(id);
    if (up.exec()) emit booksChanged();
}
```

- `loadChapter`：删除 `setProgress(...)` 调用（417 行）；解析后缓存 `m_chapterCounts[bookId] = doc.chapters.size()`；错误路径沿用 L4。
- `chapterTitles`：同样刷新 `m_chapterCounts`。
- `chapterCount`：返回缓存（无缓存时按需 documentFor 计算）。
- `savePosition`：变化写——记忆上次 (chapter, scrollY)，相同则直接 return（P1#16）。

- [ ] **步骤 4：QML 接线**

- `ShelfPage.qml` `bookById` 函数改 `return Books.bookByIdModel(id)`（对象无 id 时返回 null：`const m = Books.bookByIdModel(id); return m && m.id !== undefined ? m : null`）（P0#7）。
- `ReaderPage.qml`：章节加载成功后调 `Books.reportProgress(page.book.id, chapterIndex + 1, Books.chapterCount(page.book.id))`。
- `ReaderPage.qml` chapterProgress 绑定改读 `Books.chapterCount(page.book.id)`（P1#14）。

- [ ] **步骤 5：运行 + Commit**

```bash
ctest --test-dir build -R "tst_bookmanager" --output-on-failure
git commit -m "fix: 进度取 max 不 regress、bookByIdModel 全库查、chapterCount 缓存（P0#7/P1#13/P1#14/P1#16）"
```

---

### 任务 L7：TTS 键拆分、语速统一、reconfigure 停旧引擎、删死接口

**文件：**
- 修改：`src/tts/TtsController.h/.cpp`、`src/main.cpp`、`src/ui/qml/TtsBar.qml`、`src/ui/qml/SettingsTtsPage.qml`
- 测试：`tests/tst_ttscontroller.cpp`

- [ ] **步骤 1：编写失败测试**

`tests/tst_ttscontroller.cpp` 追加：

```cpp
    void reconfigureStopsOldEngine() {
        // 桩引擎记录 stop 调用：reconfigure 切换时旧引擎必须先 stop
        TtsController c;
        auto *first = new SpyEngine;   // 文件既有桩引擎模式；若无 SpyEngine 则新建记录 stop 的桩
        c.setEngine(first);
        c.play();
        c.reconfigure("system", "", "", "", "", 1.0);
        QVERIFY(first->stopped);
    }
```

- [ ] **步骤 2：运行验证失败**

- [ ] **步骤 3：实现**

- `TtsController.cpp` `reconfigure`：销毁旧引擎前 `if (m_engine) { m_engine->stop(); }`（P2#37）。
- `TtsController.h`：删除 `currentSentence()`、`atEnd()`、`seekTo(int)` 声明与实现；`tst_ttscontroller.cpp` 中对三者的用例删除或改为经 play/next 断言（P2#23）。
- 键拆分：`main.cpp` 启动迁移：

```cpp
    // P1#15：旧 tts/voice 单键 → 按当前引擎拆分
    const QString legacyVoice = settings->value("tts/voice").toString();
    if (!legacyVoice.isEmpty() && settings->value("tts/systemVoice").toString().isEmpty()
        && settings->value("tts/openaiVoice").toString().isEmpty()) {
        const QString eng = settings->value("tts/engine").toString("system");
        settings->setValue(eng == "openai" ? "tts/openaiVoice" : "tts/systemVoice", legacyVoice);
        // 旧键保留不删（回滚安全），读取路径全部改新键
    }
    const QString voice = settings->value(
        settings->value("tts/engine").toString("system") == "openai"
            ? "tts/openaiVoice" : "tts/systemVoice").toString();
```

reconfigure/setVoice 用 `voice`；`SettingsTtsPage.qml` 系统音色列表写 `tts/systemVoice`、OpenAI 音色文本写 `tts/openaiVoice`；`TtsBar.qml` 语速滑块 `from: 0.25; to: 4.0`（P1#9）。

- [ ] **步骤 4：运行 + Commit**

```bash
ctest --test-dir build -R "tst_ttscontroller" --output-on-failure
git commit -m "fix: TTS 音色键按引擎拆分、语速统一 0.25-4.0、reconfigure 停旧引擎（P1#9/P1#15/P2#23/P2#37）"
```

---

### 任务 L8：同步结构化结果 + 勾选即写 + 信号 + 事务 + 孤儿跳过

**文件：**
- 修改：`src/sync/SyncManager.h/.cpp`、`src/sync/SyncController.h/.cpp`、`src/ui/qml/SyncPage.qml`、`src/main.cpp`
- 测试：`tests/tst_syncmanager.cpp`、`tests/tst_synccontroller.cpp`

- [ ] **步骤 1：编写失败测试**

```cpp
    void applyHighlightsSkipsUnknownBooks() {
        // 载荷含本地不存在的 bookId → 不产生孤儿行
        SyncManager mgr(...);
        mgr.applyHighlightsJson(payloadWithBookId(999));
        QSqlQuery q(mgr 连接);
        q.exec("SELECT COUNT(*) FROM highlights WHERE book_id=999");
        q.next(); QCOMPARE(q.value(0).toInt(), 0);
    }
    void syncReturnsStructuredResult() {
        // mock 客户端使 settings PUT 失败 → Result.ok=false 且 failures 非空
        SyncManager::Result r = mgr.sync(client, opts);
        QVERIFY(!r.ok);
        QVERIFY(!r.failures.isEmpty());
    }
```

- [ ] **步骤 2：运行验证失败**

- [ ] **步骤 3：实现**

- `SyncManager.h`：`struct Result { bool ok = true; QStringList failures; };` `Result sync(WebDavClient&, const Options&);`（旧 `void sync` 移除，调用点改）；类改 `class SyncManager : public QObject` 并加 `Q_OBJECT` + `signals: void syncApplied();`（同步成功 apply 后 emit）。
- `syncOne` 失败路径收集：`result.failures.append(...)` 替代仅 log；`sync()` 返回 Result。
- `applyProgressJson`/`applyHighlightsJson` 循环外套 `m_db.transaction()`/`commit()`（P2#40）；`applyHighlightsJson` INSERT 前 `SELECT 1 FROM books WHERE id=?`，无则 `continue`（P1#18）。
- `SyncController.cpp` `doSync`：`const SyncManager::Result r = m_mgr.sync(client, opts);` 判败改 `r.ok`/`r.failures`（删字符串匹配，P1#12）；`finished(r.ok, r.failures.join('\n'))`。
- `main.cpp`：`QObject::connect(syncController 的 mgr syncApplied 经 SyncController 转发信号 dataApplied)` → `emit books->booksChanged();`（阅读页划线刷新由 ReaderPage 既有 Connections 补 `Sync.onDataApplied → reloadHighlights`）。
- `SyncPage.qml`：各 CheckBox `onCheckedChanged → Settings.setValue("webdav/syncXxx", checked)` 即写（P1#11）；「保存并立即同步」按钮改「立即同步」（只 `Sync.run(...)`，参数读当前勾选）。

- [ ] **步骤 4：运行 + Commit**

```bash
ctest --test-dir build -R "tst_sync" --output-on-failure
git commit -m "fix: 同步结构化结果、勾选即写、批处理事务与孤儿划线跳过（P1#11/P1#12/P1#18/P2#40）"
```

---

### 任务 L9：死代码清理 + 级联删除 + 迁移致命化 + 杂项

**文件：**
- 修改：`src/core/BookManager.h/.cpp`、`src/core/BookImporter.h/.cpp`、`src/core/SearchEngine.h/.cpp`、`src/core/DatabaseManager.cpp`、`src/parsers/TextParser.cpp`、`src/ui/qml/PdfReaderPage.qml`、`src/ui/qml/ReaderPage.qml`、`src/ui/qml/SettingsBackgroundPage.qml`、`src/ui/qml/ShelfPage.qml`
- 测试：`tests/tst_bookmanager.cpp`、`tests/tst_bookimporter.cpp`、`tests/tst_search.cpp`、`tests/tst_database.cpp`

- [ ] **步骤 1：removeBook 级联清理（P2#27）**

`BookManager.cpp` `removeBook`：DELETE books 后追加 `DELETE FROM highlights WHERE book_id=?`；若 `m_settings`：移除 `progress/<id>` 与 `progress/scroll_<id>` 键（SettingsStore 需 `Q_INVOKABLE void removeValue(const QString &dottedKey)`，实现 = 沿链取父对象 remove 后 save；tests/tst_settings 补用例）。测试：删书后 highlights 表无残留、settings 无残留键。

- [ ] **步骤 2：删死 API**

- `BookManager.h/.cpp`：删 `addCategory`/`removeCategory`/`categories()`（保留 `categoriesModel`）；grep 全仓调用点（仅测试）适配。
- `SearchEngine.h/.cpp`：删 `indexBook` 游标路径（保留 `rebuildBook`）；tst_search 适配。
- `BookImporter.h/.cpp`：`importFile(const QString &srcPath, qint64 *importedId = nullptr)`（删 move 参数，内部恒复制）；`doImport` 调用适配；tst_bookimporter 适配（P2#24）。
- `TextParser.cpp`：删 `inPre` 标志及其分支（P2#25）。
- `TtsController` 死接口已在 L7 删。

- [ ] **步骤 3：迁移失败致命化（P2#32）**

`DatabaseManager.cpp`：v0→v1 迁移的失败分支 `qWarning + return` 改 `qFatal("数据库迁移失败: %s", ...)`（与 open 失败同等）；tst_database 无失败迁移用例则不新增（qFatal 不可测）。

- [ ] **步骤 4：背景归一化抽公共（P2#33）**

新建 `src/ui/qml/BackgroundNorm.qml`（`pragma Singleton`，`QtObject { function norm(mode) { return ["light","dark","paper","image"].includes(mode) ? mode : "light" } }`），注册方式同 UITheme（main.cpp 与 tst_qmlmain.cpp 各 `qmlRegisterSingletonType(QUrl(...))`，CMake QML_FILES 与 tst_qml 资源列表追加）；`ReaderPage.qml` 700-703 与 `SettingsBackgroundPage.qml` 261-264 的白名单归一化改调 `BackgroundNorm.norm(...)`。

- [ ] **步骤 5：PDF 翻页节流（P2#34）**

`PdfReaderPage.qml`：翻页写进度改 2s 合并 Timer（`dirty` 置位，Timer 触发才写 Settings/DB），onDestruction 兜底 flush。

- [ ] **步骤 6：catFilter 按值维护（P1#17）**

`ShelfPage.qml`：`property string currentCategory: ""`；`onActivated` 写值 + `Books.setFilter(值)`；`Connections target: Books function onBooksChanged` 中按 `currentCategory` 重算 `catFilter.currentIndex`（model.indexOf(currentCategory)+1，找不到回 0 且 `currentCategory=""`）。

- [ ] **步骤 7：运行全量 + Commit**

```bash
ctest --test-dir build --output-on-failure
git commit -m "refactor: 级联删除、死 API 清理、迁移致命化与杂项收敛（P2#21-27/32-34）"
```

---

### 任务 L10：设置页逻辑（深色三态 + 主题预设持久化）

**文件：**
- 修改：`src/ui/qml/SettingsPage.qml`、`src/ui/qml/ThemeSheet.qml`
- 新建：`src/ui/qml/ThemeManagePage.qml`（简单列表：自定义预设 + 删除按钮）
- 测试：`tests/qml/` 既有设置冒烟适配

- [ ] **步骤 1：深色三态（P1#8）**

`SettingsPage.qml` 深色模式项改三选一 radio（跟随系统/浅色/深色，写 `theme/mode` = auto/light/dark）；用 KdRadioGrid 或三行 KdListItem+radio 圆点；subtext 显示当前值。

- [ ] **步骤 2：主题预设持久化（P1#10）**

- settings 键 `themes/custom`：数组，元素 `{name, bg, text, fontFamily, fontSize, lineHeight, ...}`。
- `ThemeSheet.qml`「保存当前设置」：弹命名输入 → 追加 `themes/custom` → 预设网格重算（内置 4 预设 + 自定义）；选中自定义即应用其值到 typography/background 键。
- 「管理主题」push `ThemeManagePage.qml`：自定义预设列表 + 删除（删除后若当前选中该预设回退内置默认）。
- CMake QML_FILES 与 tst_qml 资源列表追加 ThemeManagePage.qml。

- [ ] **步骤 3：运行 tst_qml + Commit**

```bash
ctest --test-dir build -R tst_qml --output-on-failure
git commit -m "fix: 深色三态恢复与主题预设持久化（P1#8/P1#10）"
```

---

### 任务 L11：L 阶段全量回归

- [ ] **步骤 1：全量构建零警告**

```bash
cmake --build build --parallel 2>&1 | grep -i warning | grep -v third_party || true
```

- [ ] **步骤 2：ctest 全绿**

```bash
ctest --test-dir build --output-on-failure
```
预期：全部 PASS（基线 20 个 + 新增用例）。

- [ ] **步骤 3：启动冒烟**

```bash
./build/Readdict.app/Contents/MacOS/Readdict &
```
观察 5 秒无 QML 错误/崩溃后退出。

- [ ] **步骤 4：Commit**

```bash
git commit --allow-empty -m "test: L 阶段全量回归通过"
```

---

**验收标准：** §5 清单 L 阶段条目全部落地；settings.json 唯一写者为 SettingsStore 单例；ctest 全绿；构建零警告；UI 样式未变（仅逻辑接线）。
