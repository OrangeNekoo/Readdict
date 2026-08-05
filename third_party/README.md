# third_party 第三方库

本项目以源码快照形式（vendoring）在仓库内保存以下第三方库，构建时通过顶层
`CMakeLists.txt` 的 `add_subdirectory` 直接编译，不依赖系统安装的库。

## libmobi

| 项 | 值 |
| --- | --- |
| 来源 | https://github.com/bfabiszewski/libmobi |
| 版本 | v0.12（git tag） |
| 许可证 | LGPL-3.0-or-later（见 `libmobi/COPYING`；项目 README 亦标注 LGPL-3.0-or-later） |
| 用途 | MOBI / AZW3 解析（`src/mobi.h`），供后续电子书解析模块使用 |
| CMake 目标 | `mobi`（静态库；顶层已设 `BUILD_SHARED_LIBS=OFF`） |

集成说明：`add_subdirectory(third_party/libmobi)`。其 CMake 默认 `USE_LIBXML2=ON`
（依赖系统 libxml2），本项目设为 `OFF`，使用库内置 xmlwriter 实现 OPF 元数据解析；
`USE_ZLIB=ON` 链接项目内 vendored zlib（通过预建的 `ZLIB::ZLIB` 别名指向
`zlibstatic`）。构建同时会生成 `mobitool`/`mobimeta`/`mobidrm` 命令行工具（上游
CMake 无开关可关，仅存在于构建目录，不影响应用）。

## zlib

| 项 | 值 |
| --- | --- |
| 来源 | https://github.com/madler/zlib |
| 版本 | v1.3.2（git tag） |
| 许可证 | zlib 许可（见 `zlib/LICENSE`） |
| 用途 | 压缩基础库；为 minizip 提供 inflate/deflate 实现 |
| CMake 目标 | `zlibstatic`（静态库） |

集成说明：`add_subdirectory(third_party/zlib)`，并设
`ZLIB_BUILD_SHARED=OFF` / `ZLIB_BUILD_STATIC=ON` / `ZLIB_BUILD_TESTING=OFF` /
`ZLIB_INSTALL=OFF`。库生成的头文件 `zconf.h` 输出到构建目录，目标的
`BUILD_INTERFACE` 已包含源目录与构建目录。

## minizip（zlib 子目录）

| 项 | 值 |
| --- | --- |
| 来源 | 随 zlib v1.3.2 附带（`zlib/contrib/minizip`） |
| 版本 | v1.0.0（minizip 自身版本号，随 zlib v1.3.2 快照） |
| 许可证 | Info-ZIP 许可（见 `zlib/contrib/minizip/LICENSE.Info-Zip`） |
| 用途 | EPUB 容器 zip 解包（`unzip.h`：`unzOpen64` / `unzReadCurrentFile` 等） |
| CMake 目标 | `libminizipstatic`（静态库，别名 `MINIZIP::minizipstatic`） |

集成说明：通过 `ZLIB_BUILD_MINIZIP=ON` 由 zlib 的 `contrib` 子目录自动带入（上游
支持的接入方式，minizip 会直接链接 zlib 的 `ZLIB::ZLIBSTATIC` 目标）。minizip 的
CMake 若独立加入会走 `find_package(ZLIB ... CONFIG)` 而找不到项目内 zlib，故不显式
`add_subdirectory` 它。

## 维护说明

- 各子目录的 LICENSE/COPYING 文件随源码快照保留。
- 快照通过 `git clone --depth 1 --branch <tag>` 获取后移除了 `.git` 元数据，
  以普通源码目录提交；升级时删除旧目录并重新克隆对应 tag 即可。
- 仓库根 `.gitignore` 的既有规则（`Makefile*`、`*.a`、`*.vcxproj` 等）会跳过
  部分上游自带文件（autotools/Windows IDE 构建残留），不影响 CMake 构建路径。
