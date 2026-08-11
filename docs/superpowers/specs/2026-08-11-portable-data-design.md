# Readdict 跨平台便携数据目录设计

## 目标

调整 Readdict 的持久化路径，使 Windows 版本默认将配置、数据库和书籍跟随安装目录保存到 `data/`，同时让 macOS/Linux 遵循各自的用户应用数据标准目录。现有用户数据必须可迁移，不能因路径切换丢失。

## 路径策略

### Windows

使用可执行文件所在目录的 `data/`：

```text
<程序目录>/data/
├── settings.json
├── Readdict.db
├── books/
├── covers/
└── backgrounds/
```

例如程序位于 `F:/Readdict/Readdict.exe` 时，数据目录为 `F:/Readdict/data/`。路径基于 `QCoreApplication::applicationDirPath()`，不依赖当前工作目录。

### macOS

使用当前用户的 Qt 标准应用数据目录：

```text
~/Library/Application Support/Readdict/
```

不写入 `.app` 包，也不使用根目录 `/Library/Application Support/Readdict/`，避免管理员权限、应用签名和更新覆盖问题。

### Linux

优先使用 `$XDG_DATA_HOME/Readdict/`；变量为空时使用 `~/.local/share/Readdict/`。不写入 `/usr`、`/opt` 等安装目录。

## 目录解析接口

新增单一的路径解析/准备边界，启动时一次计算并将同一个 `dataDir` 传给 `SettingsStore`、`BookManager`、`BookImporter`、`HighlightManager`、`SearchEngine`、`SyncController`。除该边界外，业务类不自行判断平台路径。

准备目录时创建 `dataDir`、`books`、`covers`、`backgrounds`。所有创建和写入错误必须保留错误信息，禁止静默改写到另一个目录。

## 旧数据迁移

### Windows

当便携目录不存在有效数据，而旧 Qt AppData 目录存在时，启动前复制以下内容到 `<程序目录>/data/`：

- `settings.json`
- `Readdict.db`
- `books/`
- `covers/`
- `backgrounds/`
- `.readdict_sync.json`、`.readdict_index_fail.json`（若存在）

复制采用临时目录 + 完成标记方式：先复制到 `data.migrating/`，所有必需文件复制成功后再以目录替换/合并到 `data/`，最后写入迁移标记。旧目录保留，不删除、不修改原文件。已有便携目录有数据时不覆盖。

### macOS/Linux

继续使用当前标准用户数据目录，不迁移到程序目录。这样符合平台应用管理规范，且旧路径与新路径相同。

## 权限处理

使用最小权限原则：

1. 先以普通用户尝试创建/写入目标目录。
2. 成功则正常启动。
3. Windows 目标目录不可写时，调用一个一次性、最小范围的目录准备/迁移 helper，并通过 UAC 提升；不以管理员权限重新启动整个阅读器。
4. macOS/Linux 不自动启动 root GUI；标准目录不可写时显示明确错误和实际路径，停止启动，避免产生权限混杂文件。
5. helper 失败必须返回可读错误，不能静默回退到系统目录或当前目录。

helper 只接受已解析的目标目录和迁移操作，不接受任意命令行；执行后由普通进程重新检查目录可写性。

## 配置兼容与安全

- 数据库、设置和书籍文件名保持不变，业务层无需迁移 schema。
- 迁移前后使用 `QFileInfo`/文件存在性校验；不删除源数据。
- 不把密码、API Key 或数据库内容写入日志。
- Windows 便携目录可能位于网络盘或只读介质；失败时显示路径和权限错误。
- macOS/Linux 不因 Windows 便携规则改变现有用户路径。

## 测试

- 路径解析测试覆盖 Windows 风格 applicationDirPath、macOS 标准 AppData、Linux `XDG_DATA_HOME`/默认路径。平台专属分支使用可注入平台参数，不修改宿主系统目录。
- 目录准备测试覆盖新目录创建、已有目录复用、不可写目录错误。
- 迁移测试覆盖旧数据完整复制、已有便携数据不覆盖、源数据保留、部分复制失败不产生完成标记。
- 启动集成测试验证所有后端单例使用同一 `dataDir`，数据库和 settings 不再分散。

## 明确不做

- 不将 macOS 数据写入 `.app` 包或根 `/Library`。
- 不将 Linux 数据写入程序安装目录。
- 不自动以管理员/root 权限运行完整 GUI。
- 不删除旧数据，不实现云端迁移，不改变数据库 schema。
