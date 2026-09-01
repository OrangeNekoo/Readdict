# Readdict · 现代、安静的开源电子书阅读器

**简体中文** | [English](README.en.md)

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Qt](https://img.shields.io/badge/Qt-6.11-41CD52.svg)](https://www.qt.io/)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#从源码构建)

Readdict 是一款基于 **Qt 6 / QML** 构建的桌面电子书阅读器，专注于干净纸感界面上不打扰的阅读体验。支持 EPUB、MOBI/AZW3、FB2、TXT 与 PDF，内置朗读（TTS）、高亮划线、WebDAV 同步与灵活的排版定制。

## 界面一览

| 图书馆 | 阅读页 |
| --- | --- |
| ![图书馆](docs/screenshots/library.jpeg) | ![阅读页](docs/screenshots/reader.jpeg) |

| 主页 | 阅读背景设置 |
| --- | --- |
| ![主页](docs/screenshots/home.jpeg) | ![阅读背景设置](docs/screenshots/background-settings.jpeg) |

## 功能特性

### 📚 多格式书库
- 支持 **EPUB / MOBI / AZW3 / FB2 / TXT / Markdown / PDF** 七种格式，导入即读
- 图书馆封面墙：书封、书名、作者与阅读进度一目了然，支持分类筛选与全局搜索
- 主页聚合「最近阅读」与阅读统计（累计时长、藏书量）

### 📖 沉浸阅读
- **主题背景**：浅色 / 深色 / 米白 / 自定义图片，可调模糊度与亮度
- **字体排印**：内置思源黑体、思源宋体（可变字体）与得意黑，亦可调字号与版面布局
- **翻页方式**：竖向连续滚动 / 横向分页自由切换
- 章节目录、书签、全文搜索
- 高亮划线：划选即高亮，工具条支持删除，划线集中管理

### 🔊 朗读（TTS）
- 系统语音引擎开箱即用，亦可配置 **OpenAI 兼容 TTS API** 获得更自然的音色
- 朗读时**逐句高亮**跟随，PDF 同样支持基于视觉坐标的逐句高亮
- 语速、音色可调

### ☁️ 同步与本地优先
- **WebDAV** 同步：坚果云等任何标准 WebDAV 服务均可
- 数据本地存储，Windows 支持便携数据目录（绿色便携）

### 🌏 国际化
- 简体中文 / 繁體中文 / English 三语界面，构建时由 Qt Linguist 工具链生成

## 从源码构建

### 依赖

| 依赖 | 版本要求 |
| --- | --- |
| Qt 6（开源版即可） | ≥ 6.11 |
| CMake | ≥ 3.21 |
| C++17 编译器 | Clang / GCC / MSVC |

Qt 安装需包含以下模块：`Core`、`Gui`、`Quick`、`QuickControls2`、`Sql`、`Network`、`Pdf`、`TextToSpeech`、`Multimedia`、`LinguistTools`。第三方库（zlib、minizip、libmobi）已以源码快照形式内置于 [`third_party/`](third_party/)，无需单独安装。

### 构建步骤（macOS）

```bash
# 让 CMake 找到 Qt（按你的 Qt 安装路径调整）
export CMAKE_PREFIX_PATH="$HOME/Qt/6.11.1/macos"

cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --target Readdict

# 运行
open build/Readdict.app
```

生成自包含 `.app`（内嵌 Qt 运行时与字体，可直接分发）：

```bash
cmake --build build --target deploy_script
# 产物：build/Readdict.app
```

### 运行测试

```bash
cmake --build build
ctest --test-dir build --output-on-failure
```

## 技术栈

- **Qt 6.11 / QML**：声明式 UI，Material 风格定制组件
- **C++17 + CMake**：解析器、同步、TTS 引擎与业务核心
- **Qt Test**：24 个测试用例覆盖解析、导入、同步、高亮、TTS 等核心模块
- 内置可变字体与三语翻译资源

## 致谢

Readdict 站在以下优秀开源项目的肩膀上，衷心感谢：

| 项目 | 用途 | 许可证 |
| --- | --- | --- |
| [Qt](https://www.qt.io/) | 应用框架（UI / PDF / TTS / 多媒体 / 网络） | LGPLv3 / GPLv3 |
| [libmobi](https://github.com/bfabiszewski/libmobi) | MOBI / AZW3 格式解析 | LGPL-3.0-or-later |
| [zlib](https://github.com/madler/zlib) | 压缩基础库 | zlib License |
| [minizip](https://github.com/madler/zlib/tree/develop/contrib/minizip)（zlib contrib） | EPUB 容器 zip 解包 | Info-ZIP License |
| [思源黑体 / 思源宋体](https://github.com/adobe-fonts) | 内置可变字体 | SIL OFL 1.1 |
| [得意黑 Smiley Sans](https://github.com/atelier-anchor/smiley-sans) | 内置字体 | SIL OFL 1.1 |
| [Project Gutenberg](https://www.gutenberg.org/) | 截图中的公版演示书目 | 公版 |

同时感谢 Qt / QML 社区与所有开源阅读器先行者提供的灵感。

## 许可证

本项目以 [**GNU General Public License v3.0**](LICENSE) 发布。

- 你可以自由地使用、学习、修改与再分发本项目，衍生作品须同样以 GPL-3.0 开源。
- 项目使用的 Qt 开源版本遵循 **LGPLv3 / GPLv3** 双许可，本应用以动态链接方式使用 Qt 并遵守相应义务；Qt PDF 模块内含 [PDFium](https://pdfium.googlesource.com/pdfium/)，其第三方许可声明随 Qt 文档提供。
- [`third_party/`](third_party/) 与 [`fronts/`](fronts/) 内的第三方源码及字体分别保留其原始许可证（见上表），随仓库一并提供。

---

*Readdict — addicted to reading, not to notifications.* 📖
