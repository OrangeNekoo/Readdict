# 便携数据目录 — 审查修复报告（权限顺序 / helper 路径约束 / 迁移重试安全）

日期：2026-08-11
基础提交：`ef94ff4`
规格：docs/superpowers/specs/2026-08-11-portable-data-design.md「权限处理」「旧数据迁移」
实现人：impl-flash（FixPortableReview）

## 一、审查发现与修复对照

| # | 审查发现 | 修复 |
|---|---------|------|
| 1 | main 先 migrate 后提权：迁移在普通权限下失败时直接 `return 1`，永远进不了 UAC helper | 新增 `ensurePortableData`：迁移+准备合并为一次 elevated operation；普通权限整体尝试，任一失败疑似权限不足且非提权进程才 `runas`；helper 内自行 migrate+prepare；提权后父进程复检两者均成立才 success |
| 2 | helper 接受任意绝对路径，可诱导管理员在任意位置创建目录/写入 | `runElevationHelper` 新增安全边界：目标必须等于 `cleanPath(applicationDirPath/data)`（Windows 便携目录唯一形态），其余一律退出码 3 |
| 3 | 合并中途失败残留目标（如 settings.json 已拷入），下次 `portableHasData` 判定已有数据而跳过迁移 | 合并循环记录已合并项，任一项失败即回滚本次已合并项（`removeEntry`），dataDir 回到“无有效数据”状态：无残留、无完成标记、可重试 |
| 4 | 空子目录（目录准备遗留的 books/covers/backgrounds）被 `portableHasData` 视为有效数据，阻止迁移 | `portableHasData` 只认 settings.json / Readdict.db / 非空子目录；空子目录不再阻止迁移 |
| 5 | ShellExecute 等待未检查 API 返回：`WaitForSingleObject`/`GetExitCodeProcess` 失败仍继续；UAC 取消/失败虽已处理但等待路径不严谨 | `elevateViaUac`：启动成功但无进程句柄 → 可读错误；`WaitForSingleObject(INFINITE)` 非 `WAIT_OBJECT_0` → `windowsErrorText` 可读错误并关闭句柄；`GetExitCodeProcess` 失败 → 可读错误；非 0 退出码（1/2/3）→ 可读错误；UAC 取消（ERROR_CANCELLED）→ 可读错误，均不进入等待 |

## 二、实现要点

### ensurePortableData（main 启动唯一入口）

```
1. migrateFromLegacy(legacy, dataDir) → 空则 prepareDataDir(dataDir)
2. 全部成功            → success（不提权）
3. 失败且非权限错误    → 原错误返回（提权无意义）
4. 失败且权限不足      → alreadyElevated ? 放弃二次提权 :（Windows）elevateViaUac
5. 提权后复检          → migrateFromLegacy + prepareDataDir 均空才 success
   （helper 已完成时复检为幂等空操作：迁移见标记/有效数据即跳过，准备见目录已存在）
```

macOS/Linux：legacy 传空（新旧路径相同），普通尝试失败返回“不支持自动提权”错误并停止，行为与既有一致（不调 sudo/root）。

### helper 路径边界

`runElevationHelper` 依次校验：参数形态（code 2）→ cleanPath 后绝对路径且无穿越（code 3）→
`== cleanPath(applicationDirPath + "/data")`（code 3）。提权进程只处理本程序目录 data/，
任意其他路径（含兄弟目录、`data-extra`、任意绝对路径）一律拒绝，无法诱导管理员写入。

### 迁移合并回滚

合并循环以 `merged` 列表跟踪本次已拷贝条目；失败时对已合并项逐个 `removeEntry`
（目录树 `removeRecursively` / 文件 `remove`）。由于进入合并前 `portableHasData == false`，
dataDir 中这些名称只可能是空目录或本次拷贝内容，回滚安全。暂存目录与完成标记语义不变
（标记仅在全部合并成功后写入）。

## 三、测试（tests/tst_portabledata.cpp，41 用例全部通过；本任务新增/改造 8）

- helperPreparesDir / helperMigratesLegacyData：补 `p.applicationDirPath`，锁定“只接受自身 data/”契约
- helperRejectsPathOutsideOwnDataDir：兄弟目录 `other`、`data-extra` 均拒绝（code 3）且不创建
- helperRejectsEmptyApplicationDir：无法推导本程序 data/ 时拒绝一切路径
- migrateEmptySubdirDoesNotBlockMigration：空 books/covers 不阻止迁移，旧数据并入且写标记
- migrateSkipsWhenPortableHasNonEmptyBooks：非空 books 视为有效数据，跳过且不覆盖
- migrateMergeFailureRollsBackAndRetrySucceeds：books 被文件占据 → 合并失败；断言 settings.json/
  Readdict.db 已回滚、无标记、暂存清理、源保留；移除阻塞后重试成功（无“已迁移”误判跳过）
- ensurePortableDataSucceedsNormalPath：迁移+准备一次成功、不提权
- elevateReachedWhenMigrateFailsPermission：迁移阶段权限失败仍进入提权流程（非 Windows
  返回“不支持自动提权”且含实际路径），证明 migrate 不再单独致命
- migrateFailureNonPermissionDoesNotElevate：源不可读（非权限错误）返回原始迁移错误、不提权

TDD 顺序：先加测试 → 构建失败（`ensurePortableData` 不存在，红）→ 实现 → 41/41 绿。

## 四、验证结果

- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_portabledata -j2`：通过
- `./build/Qt_6_11_1_for_macOS_Debug/tests/tst_portabledata`：41 passed, 0 failed
- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target Readdict -j2`：通过（字体拷贝正常）
- `ctest --test-dir build/Qt_6_11_1_for_macOS_Debug`：21/21 通过

### tst_qml 首次 1 例失败 = 既有环境 flake（复现与记录）

首次 ctest 运行 tst_qml 输出 `262 passed, 1 failed, 4 skipped`（当时未捕获失败用例名；
该次输出含 `tst_u4.qml`/`tst_u5.qml "window not active after requestActivate()"` QWARN，
与既有窗口激活竞态 flake 特征一致）。后续复现记录：

| 轮次 | 结果 |
|------|------|
| 立即重跑 tst_qml | 263 passed, 0 failed |
| 全量 ctest 复跑 | 21/21 通过 |
| 复现轮 1（独立运行） | 263 passed, 0 failed |
| 复现轮 2（独立运行） | 263 passed, 0 failed |
| 复现轮 3（独立运行） | 263 passed, 0 failed |

连续 5 轮（4 次独立 + 1 次全量）均未复现。tst_qml 目标不编译/不链接
PortableData.cpp（tests/CMakeLists.txt 仅 tst_portabledata 引用；tst_qml 源列表为
qml/tst_qmlmain.cpp + QML 资源 + 后端单例），本 diff 与 QML 测试无任何依赖路径，
判定为既有环境 flake，非本 diff 回归。

## 五、疑虑与说明

1. **Windows 运行时路径无法在本机执行**：`elevateViaUac`（ShellExecuteExW/runas）为 Windows
   运行时特性，macOS 无法运行；Windows 专属代码按 API 契约逐项核对（SEE_MASK_NOCLOSEPROCESS
   必有 hProcess、WaitForSingleObject/GetExitCodeProcess 返回码、ERROR_CANCELLED 语义）。
   跨平台逻辑分支（决策/命令构造/helper 校验/回滚/重试）全部在 macOS 测试覆盖。
2. **保留 INFINITE 等待**：按任务要求可保留 INFINITE，但等待/退出码读取的 API 返回已显式
   检查并给出可读错误，不存在“未知状态继续”路径；UAC 取消时 ShellExecuteExW 直接返回
   FALSE（ERROR_CANCELLED），不会进入等待。
3. **复检语义**：提权成功后父进程复检 prepareDataDir 依赖 `QDir::mkpath` 对已存在目录直接
   成功——helper 已创建目录树，因此复检验证的是“helper 成果已物化”，而非父进程可写性
   （ACL 拒绝场景下父进程本就不应可写）。
4. **迁移失败非权限错误不提权**：源数据不可读（ACL/损坏）时提权无意义，返回原始可读错误
   停止启动，与“最小权限、不静默回退”一致。

---

# 便携数据目录 — 安全/路径最终审查修复报告（第二轮）

日期：2026-08-11
基础提交：`da1820e`
实现人：impl-flash（HardenPortableSecurity）

## 一、审查发现与修复对照

| # | 审查发现 | 修复 |
|---|---------|------|
| 1 | `copyRecursively`/`removeEntry` 跟随符号链接，helper 可越界读写/删除目标树之外 | 新增 `isLinkLike`（Unix `isSymbolicLink`；Windows 另查 `isReparsePoint` 覆盖 junction/挂载点）；`copyRecursively` 对源与目标的每个递归入口（含子项）拒绝链接类条目；`removeEntry`/`removeTreeSafely` 拒绝跟随链接类条目；迁移暂存根目录本身为链接时直接拒绝，mkpath/复制绝不写入链接目标 |
| 2 | 迁移标记写失败未回滚，重试会被 `portableHasData` 误判“已迁移”而跳过 | 标记 `open` 失败时回滚本次已合并项（`removeEntry`），dataDir 回到“无有效数据”可重试状态；不产生完成标记、源保留 |
| 3 | `portableHasData` 漏 optional sync/index 文件，只含可选文件也被误判“无数据”而覆盖 | `portableHasData` 增加 `.readdict_sync.json`/`.readdict_index_fail.json` 检查，仅可选文件也算已有数据 |
| 4 | Linux 相对 `XDG_DATA_HOME` 被接受，产出相对 dataDir | `resolveDataDir` 对相对 `XDG_DATA_HOME` 一律拒绝并 `qWarning` 回退默认 `~/.local/share/Readdict`（XDG Base Directory 规格要求绝对路径），绝不产出相对路径 |
| 5 | `prepareDataDir` 仅 mkpath 无写探针，已有目录 ACL 不可写时误报成功 | 在 dataDir 内创建唯一 `QTemporaryFile` 探针并实际写入一字节，失败判权限错误（触发 Windows UAC 决策），成功即自动删除，不留残留 |

## 二、测试（tests/tst_portabledata.cpp，49 用例全部通过；本任务新增 8）

TDD：先加 7 个失败测试确认红 → 实现 → 49/49 绿。
- `linuxRelativeXdgFallsBackToDefault`：相对 xdg 回退默认绝对路径（红：原产出相对路径）
- `prepareProbeDetectsUnwritableExistingDir`：子目录已存在但 dataDir ACL 只读 → 写探针发现权限错误（红：原 mkpath 全静默成功误报成功）
- `prepareProbeLeavesNoTrace`：成功准备后目录仅含三个数据子目录，无探针残留
- `migrateRejectsSymlinkFileInSource` / `migrateRejectsSymlinkDirInSource`：源内文件/子目录符号链接均拒绝，外部目标未被读取/改写（红：原跟随复制）
- `migrateRejectsSymlinkMergeTarget`：合并目标为符号链接拒绝写入，外部目录未被写入（红：原跟随写入）
- `migrateMarkerFailureRollsBackAndRetrySucceeds`：标记写失败回滚已合并项，移除阻塞后可重试成功（红：原残留数据不可重试）
- `migrateSkipsWhenPortableHasOnlyOptionalFiles`：仅可选文件也阻断迁移、不覆盖（红：原误判无数据并覆盖）

## 三、验证结果

- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_portabledata -j2`：通过
- `./build/Qt_6_11_1_for_macOS_Debug/tests/tst_portabledata`：49 passed, 0 failed
- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target Readdict -j2`：通过（字体拷贝正常）
- `ctest --test-dir build/Qt_6_11_1_for_macOS_Debug`：21/21 通过（含 tst_qml）

## 四、疑虑与说明

1. **Windows 重解析点仅编译期核对**：`QFileInfo::isReparsePoint()` 为 Qt 6.1+ API，本机 macOS 无法运行 Windows 分支；按 Qt 文档契约核对（isSymbolicLink 覆盖符号链接、isReparsePoint 覆盖 junction/挂载点）。Unix 符号链接拒绝路径在 macOS 全量覆盖。
2. **探针用 `QTemporaryFile`**：唯一名 + 自动删除，避免固定名残留；失败时（open 失败）不产生文件，无需清理。
3. **暂存根目录守卫**：`data.migrating` 为链接时直接返回错误，mkpath/复制绝不跟随链接目标写入；这是对“所有递归入口和目标路径”的补强。
4. **相对 XDG 选择“回退默认 + 记录”**：规格（XDG Base Directory）要求标准绝对路径，回退默认 `~/.local/share/Readdict` 比中止启动更符合“数据不丢”语义；`qWarning` 记录以便诊断，不产出相对 dataDir。

---

# 便携数据目录 — 便携最终审查阻塞修复报告（第三轮）

日期：2026-08-11
基础提交：`8946fb6`
审查发现来源：便携最终审查（五项阻塞中的三项）
实现人：impl-flash（FixPortableFinalSecurity）

## 一、审查发现与修复对照

| # | 审查发现 | 修复 |
|---|---------|------|
| 1 | `QFileInfo::isReparsePoint()` 非 Qt 6.11 公共 API（6.11.1 头文件仅 `isSymbolicLink`/`isJunction`），Windows 构建阻断 | `isLinkLike` 的 Windows 分支改为 Win32 guarded helper `isWindowsReparsePoint`：`GetFileAttributesW` 检查 `FILE_ATTRIBUTE_REPARSE_POINT`，覆盖符号链接/junction/挂载点等一切重解析条目；GetFileAttributesW 不跟随末级链接，悬空链接返回链接自身属性，与 QFileInfo 语义一致 |
| 2 | copy/remove 未检查 dataDir/legacy 根、marker 本身 symlink，可越界写 | `prepareDataDir` 入口先于 mkpath 拒绝 dataDir 根链接；循环内拒绝 books/covers/backgrounds 子目录链接（mkpath 对链接会静默“成功”并跟随写入目标）。`migrateFromLegacy` 入口拒绝 legacy 根链接（防越界读）与 dataDir 根链接（防越界写）；写标记前拒绝 marker 路径本身为链接（open(WriteOnly) 会沿链接覆盖/创建链接目标之外的文件），拒绝时回滚本次已合并项 |
| 3 | QTemporaryFile write/close 返回值未检查 | 写探针改为 `probe.write("p", 1) != 1 || !probe.flush()` 全检查（close 为 void 不报告落盘失败，故显式 flush），失败判权限错误返回；标记 open/write/flush 全检查，任一失败回滚已合并项，dataDir 回到“无有效数据”可重试状态 |

## 二、测试（tests/tst_portabledata.cpp，54 用例全部通过；本任务新增 5）

TDD：先加 5 个失败测试确认红（5/54 failed）→ 实现 → 54/54 绿。

- `prepareRejectsSymlinkDataDirRoot`：dataDir 是指向外部目录的符号链接 → 拒绝，外部目录未被 mkpath 写入任何子目录/探针（红：原 mkpath 跟随链接在外部建目录）
- `prepareRejectsSymlinkSubdir`：dataDir/books 指向外部目录 → 拒绝并停止，其余子目录不创建，外部未被改写
- `migrateRejectsSymlinkDataDirRoot`：迁移目标根为链接 → 拒绝，外部目录未被写入 settings.json/Readdict.db/books
- `migrateRejectsSymlinkLegacyRoot`：legacy 根为链接 → 拒绝，未从链接目标复制，未创建暂存目录
- `migrateRejectsSymlinkMarker`：标记路径为指向外部目录的悬空链接 → 拒绝且回滚已合并项，外部目录未创建任何文件（无越界写），源保留

## 三、验证结果

- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_portabledata -j2`：通过
- `./build/Qt_6_11_1_for_macOS_Debug/tests/tst_portabledata`：54 passed, 0 failed
- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target Readdict -j2`：通过（字体拷贝正常）
- `ctest --test-dir build/Qt_6_11_1_for_macOS_Debug`：首轮 tst_qml `262 passed, 1 failed`（`ArrowKeyPagingSmoke::test_realDragScrollDoesNotSummon` 拖动/窗口激活竞态，与既有 flake 签名一致，tst_qml 不编译/不链接 PortableData.cpp）；独立重跑 `263 passed, 0 failed`，全量 ctest 复跑 21/21 通过
- 提交：`2d4a312`（中文）

## 四、疑虑与说明

1. **Windows 分支仅编译期核对**：`isWindowsReparsePoint` 只用 Win32 公共 API（GetFileAttributesW / FILE_ATTRIBUTE_REPARSE_POINT / INVALID_FILE_ATTRIBUTES，windows.h 已有包含），本机 macOS 无法编译 Windows 分支；Unix 符号链接拒绝路径在 macOS 全量覆盖，Win32 语义按 MSDN 文档核对（不跟随末级链接、悬空链接返回 REPARSE_POINT）。
2. **探针 write/flush 失败未做确定性测试**：write/flush 失败在 macOS 上无法不经注入稳定触发（需磁盘满/配额），按简报允许的“可注入 helper 或至少检查代码路径”取代码路径检查；行为可观察路径（open 失败判权限错误、成功不留残留）由既有测试锁定。
3. **标记写入内容**：标记从空文件改为写入 `"1"`，使 write 长度检查有实际意义；仅存在性被消费（portableHasData/migrateFromLegacy），内容不对外读取。
4. **既有 `migrateMarkerFailureRollsBackAndRetrySucceeds` 语义微调**：悬空标记链接现在被链接守卫先行拒绝（消息仍含“迁移标记”，回滚/重试断言不变），原“open 失败”路径仍由错误消息覆盖，测试未放宽。

---

# 便携数据目录 — 便携最终复审剩余迁移安全问题修复报告（第四轮）

日期：2026-08-12
基础提交：`f99ce04`
审查发现来源：便携最终复审（RereviewPortableSecurity，两项剩余）
实现人：impl-flash（FixPortableFinalSecurity）

## 一、审查发现与修复对照

| # | 审查发现 | 修复 |
|---|---------|------|
| 1 | `portableHasData` 用 `QFile::exists`/`QDir` 枚举做存在性检查，会**跟随**已有 marker/子目录符号链接：marker 指向外部已有文件、settings/db/optional 文件为指向外部已有文件的链接、`books/covers/backgrounds` 为指向非空外部目录的链接时，被判“已有数据”，`migrateFromLegacy` 静默跳过迁移（fail-open，旧数据永不迁入且不可恢复） | `portableHasData` 改为 fail-closed 三态 `DataPresence { None, Present, LinkRejected }`：对 marker、settings/Readdict.db、两个 optional 文件、三个子目录逐一先做 `isLinkLike` 检查（符号链接/Windows 重解析点），任一为链接类条目即返回 `LinkRejected`；`migrateFromLegacy` 收到 `LinkRejected` 返回可读错误（“便携数据目录含符号链接/重解析点，拒绝迁移”），既不信赖（不误判跳过）也不跟随（不在链接目标上作业）。悬空链接同样拒绝（isSymbolicLink 不依赖目标存在性） |
| 2 | `copyRecursively` 目录条目内部复制一部分后失败（如 `books/` 内 a.epub 已复制、evil.epub 为源内符号链接被拒），当前条目已复制的 partial 未清理；该条目尚未加入 `merged`，回滚只删此前完整成功的条目，partial 残留在 dataDir，下次被 `portableHasData` 判为“已有数据”而跳过迁移 | `copyRecursively` 子项失败时对当前条目调用 `removeTreeSafely(dst)` 整体清理已复制部分（dst 由本函数创建、入口已拒绝链接类条目，删除不越界），再向上返回错误；文件 `QFile::copy` 失败时主动 `QFile::remove(dst)` 清除可能的部分文件。迁移合并回滚语义因此闭合：失败条目自身无残留，与 `merged` 回滚共同保证“无 partial、无 marker、可重试”。`removeTreeSafely` 定义上移到 `copyRecursively` 之前 |

## 二、TDD 证据

先加测试确认红（`tst_portabledata` 55 passed, **4 failed**，4 个失败均为“静默跳过→err 为空”）：

- `migrateRejectsExistingSymlinkMarker`：marker 为指向外部**已有**文件的符号链接（红：原 `QFile::exists` 跟随→Present→跳过）
- `migrateRejectsSymlinkSettingsFile`：settings.json 为指向外部已有文件的符号链接（红）
- `migrateRejectsSymlinkOptionalFile`：`.readdict_sync.json` 为指向外部已有文件的符号链接（红）
- `migrateRejectsSymlinkChildDirNonEmpty`：dataDir/books 为指向**非空**外部目录的符号链接（红：原 `QDir::exists`+`entryList` 跟随→非空→跳过）

实现后 **59/59 绿**。另新增契约锁定用例：

- `migrateCopyPartialCleansTargetAndRetrySucceeds`：legacy/books 含 [a.epub, evil(符号链接)]，复制 books 中途失败（a.epub 已复制后 evil 被拒）→ 断言 dataDir 无任何 partial（settings/db/books 均不存在）、无 `.readdict_migrated`、暂存已清、源保留；移除 evil 后重试成功（books/a.epub、settings.json、marker 齐全），证明无 partial 残留导致“已有数据”误判跳过。

适配（fail-closed 提前拒绝，行为语义变更）：

- `migrateRejectsSymlinkMarker`：断言由“迁移标记”改为“符号链接”（拒绝点从合并后写标记守卫提前到存在性探测），外部目录未被创建任何文件等断言不变
- `migrateMarkerFailureRollsBackAndRetrySucceeds`：标记路径为链接时现于存在性探测即拒绝（不再走到合并后写标记），断言改“符号链接”，移除链接后重试成功断言不变；原只读目录构造不再相关，已简化

## 三、验证结果

- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target tst_portabledata -j2`：通过
- `./build/Qt_6_11_1_for_macOS_Debug/tests/tst_portabledata`：59 passed, 0 failed（红阶段 55 passed, 4 failed）
- `cmake --build build/Qt_6_11_1_for_macOS_Debug --target Readdict -j2`：通过（字体拷贝正常）
- `ctest --test-dir build/Qt_6_11_1_for_macOS_Debug`：**21/21 通过**
- 提交：`f94e292`（中文）

## 四、疑虑与说明

1. **partial 清理用例的触发路径**：`migrateCopyPartialCleansTargetAndRetrySucceeds` 经暂存阶段触发（books 内 a.epub 复制成功后 evil 符号链接被拒）。合并阶段中 `portableHasData==None` 前提下（三个子目录为空/不存在）预置阻塞无法通过存在性探测，故确定性 partial 只出现在暂存阶段；实现仍按规格对合并阶段同样自清理（同一函数），TOCTOU/IO 错误路径（磁盘满等不可确定性触发）由该防御覆盖。
2. **fail-closed 提前拒绝的既有用例影响**：`migrateRejectsSymlinkMergeTarget`（dataDir/books 链接→空外部目录）现于存在性探测拒绝（消息仍含“符号链接”，外部未被写入、源保留断言不变）；`migrateSkipsWhenPortableHasData` 系列（真实文件/非空子目录）语义不变。
3. **Windows 分支仍为编译期核对**：`isLinkLike` 的 Windows 重解析点分支沿用上轮 `GetFileAttributesW` 方案，本机 macOS 无法运行；Unix 符号链接路径（含悬空链接）全量覆盖。
4. **`QFile::copy` 失败清理**为防御性处理（Qt 是否在失败时删除目标未在文档中保证），与“不残留 partial 被误判有效数据”契约一致。
