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
