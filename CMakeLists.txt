cmake_minimum_required(VERSION 3.21)
project(Readdict VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Sql Network Pdf TextToSpeech Multimedia Test QuickTest LinguistTools)

qt_standard_project_setup()

# D7：显式设置 QML 模块 QTP0004 策略（Qt 6.8+ 未设置会告警；OLD 亦被标记弃用）。
# 本项目 QML 文件集中在 src/ui/qml 单目录，NEW 行为仅额外为子目录生成 qmldir，
# 对本模块无实际影响，采用 NEW 消除告警并保持向前兼容。
qt_policy(SET QTP0004 NEW)

# ---- 第三方库（vendored） ----
# zlib：静态库 zlibstatic；minizip 由 zlib 的 contrib 子目录经 ZLIB_BUILD_MINIZIP 带入
# （显式 add_subdirectory(minizip) 会与 contrib 重复添加同名目标，故不重复引入）
set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)     # 仅构建静态库
set(ZLIB_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)    # 不构建 zlib 自测示例
set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
set(ZLIB_BUILD_MINIZIP ON CACHE BOOL "" FORCE)     # 构建 libminizipstatic（EPUB zip 解包）
add_subdirectory(third_party/zlib)
# libmobi 通过 find_package(ZLIB REQUIRED) 查找 zlib：预置其输入变量并预建 ZLIB::ZLIB 别名，
# 使 FindZLIB 命中 vendored 头文件且 libmobi 直接链接 zlibstatic，而非系统 zlib
set(ZLIB_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/third_party/zlib" CACHE PATH "" FORCE)
set(ZLIB_LIBRARY zlibstatic CACHE STRING "" FORCE)
add_library(ZLIB::ZLIB ALIAS zlibstatic)
# libmobi：静态库 mobi，使用内置 xmlwriter（USE_LIBXML2=OFF，避免依赖系统 libxml2）
set(USE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(USE_ZLIB ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/libmobi)

qt_add_executable(Readdict
    src/main.cpp
    src/core/DatabaseManager.cpp
    src/core/BookManager.cpp
    src/core/SettingsStore.cpp
    # 便携数据目录边界：路径解析/目录准备/Windows 旧数据迁移（main.cpp 唯一数据目录来源）
    src/core/PortableData.cpp
    src/core/BookImporter.cpp
    src/core/HighlightManager.cpp
    src/core/SearchEngine.cpp
    src/parsers/SentenceSplitter.cpp
    src/parsers/TextParser.cpp
    src/parsers/EpubParser.cpp
    src/parsers/Fb2Parser.cpp
    src/parsers/MobiParser.cpp
    src/parsers/ParserFactory.cpp
    src/tts/SystemTTSEngine.cpp
    src/tts/SystemTTSEngine.h
    src/tts/OpenAITTSEngine.cpp
    src/tts/OpenAITTSEngine.h
    src/tts/TtsController.cpp
    src/tts/TtsController.h
    src/tts/TTSEngine.h
    src/ui/ReaderTextHelper.cpp
    src/ui/ReaderTextHelper.h
    src/ui/LanguageController.cpp
    src/ui/LanguageController.h
    src/sync/SyncController.cpp
    src/sync/SyncController.h
    src/sync/SyncManager.cpp
    src/sync/SyncManager.h
    src/sync/WebDavClient.cpp
    src/sync/WebDavClient.h
)
qt_add_qml_module(Readdict
    URI Readdict
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    OUTPUT_DIRECTORY ReaddictQml
    QML_FILES
        src/ui/qml/Main.qml
        src/ui/qml/HomePage.qml
        src/ui/qml/KdTabBar.qml
        src/ui/qml/KdIcons.qml
        src/ui/qml/KdListItem.qml
        src/ui/qml/KdRadioGrid.qml
        src/ui/qml/KdSegmentedSlider.qml
        src/ui/qml/KdIconCard.qml
        src/ui/qml/KdToggle.qml
        src/ui/qml/KdBottomSheet.qml
        src/ui/qml/ThemeManagePage.qml
        src/ui/qml/ThemeSheet.qml
        src/ui/qml/FontSheet.qml
        src/ui/qml/LayoutSheet.qml
        src/ui/qml/MoreSheet.qml
        src/ui/qml/KdFilterSheet.qml
        src/ui/qml/ShelfPage.qml
        src/ui/qml/BookCard.qml
        src/ui/qml/SettingsPage.qml
        src/ui/qml/SettingsLanguagePage.qml
        src/ui/qml/SettingsTtsPage.qml
        src/ui/qml/SettingsBackgroundPage.qml
        src/ui/qml/SyncPage.qml
        src/ui/qml/StatsPage.qml
        src/ui/qml/ReaderPage.qml
        src/ui/qml/ReaderContent.qml
        src/ui/qml/ReaderBackground.qml
        src/ui/qml/KdTopToolbar.qml
        src/ui/qml/Theme.qml
        src/ui/qml/BackgroundNorm.qml
        src/ui/qml/TtsBar.qml
        src/ui/qml/PdfReaderPage.qml
        src/ui/qml/KdTopSearchBar.qml
        src/ui/qml/KdDropdownMenu.qml
        src/ui/qml/KdBottomTabs.qml
)

qt_add_resources(Readdict "app_resources"
    PREFIX "/"
    FILES resources.qrc
)

# D6：三语国际化。构建时 lupdate 扫描 QML/C++ 的 qsTr/tr 更新 .ts，
# lrelease 编译 .qm 并默认以 /i18n 前缀编入 Readdict 资源（main.cpp 的
# LanguageController 从 :/i18n 加载 readdict_<code>.qm）。
qt_add_translations(Readdict
    TS_FILES
        src/ui/i18n/readdict_zh_CN.ts
        src/ui/i18n/readdict_zh_TW.ts
        src/ui/i18n/readdict_en.ts
)

target_include_directories(Readdict PRIVATE src third_party/libmobi/src)
target_link_libraries(Readdict PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Network Qt6::Pdf Qt6::TextToSpeech Qt6::Multimedia
    MINIZIP::minizipstatic mobi zlibstatic
)
# Windows UAC 提权 helper（PortableData.cpp 的 ShellExecuteExW）需要 shell32
if(WIN32)
    target_link_libraries(Readdict PRIVATE shell32)
endif()
# TextParser 的 GB18030 解码走系统 iconv；macOS 的 iconv 在 libiconv.dylib 中需显式链接
if(APPLE)
    target_link_libraries(Readdict PRIVATE iconv)
endif()

# ---- D7：字体资源（fronts/ → bundle/安装目录）----
# 实际字体文件（glob 核实）：fronts/02_SourceHanSans-VF/.../Variable/SourceHanSans{-VF,HW-VF}.otf.ttc、
# fronts/02_SourceHanSerif-VF/.../Variable/SourceHanSerif-VF.otf.ttc、fronts/smiley-sans-v2.0.1/SmileySans-Oblique.otf。
# 打包布局：bundle 用扁平 Resources/fonts/（main.cpp 的 ../Resources/fonts 扁平相对路径），
# 开发期仍走仓库根 fronts/ 嵌套布局（CWD 回退）。
set(READDICT_FONT_FILES
    "${CMAKE_SOURCE_DIR}/fronts/02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSans-VF.otf.ttc"
    "${CMAKE_SOURCE_DIR}/fronts/02_SourceHanSans-VF/02_SourceHanSans-VF/Variable/SourceHanSansHW-VF.otf.ttc"
    "${CMAKE_SOURCE_DIR}/fronts/02_SourceHanSerif-VF/02_SourceHanSerif-VF/Variable/SourceHanSerif-VF.otf.ttc"
    "${CMAKE_SOURCE_DIR}/fronts/smiley-sans-v2.0.1/SmileySans-Oblique.otf"
)

# ---- D7：发布打包（macOS）----
# A1 起裸可执行；此处补 MACOSX_BUNDLE 生成 .app；deploy_script 目标一键产出
# 自包含 .app（Qt 库 + QML 插件含 QtQuick.Pdf + 私有 framework + 字体）。
# 字体拷贝：RESOURCE 属性在本机 CMake 4.4.2 下未生效（最小复现确认），改用
# POST_BUILD + TARGET_BUNDLE_CONTENT_DIR 确定性拷入 Contents/Resources/fonts。
if(APPLE)
    set_target_properties(Readdict PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.readdict.Readdict"
        MACOSX_BUNDLE_BUNDLE_NAME "Readdict"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_COPYRIGHT "Readdict"
    )
    add_custom_command(TARGET Readdict POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_BUNDLE_CONTENT_DIR:Readdict>/Resources/fonts"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${READDICT_FONT_FILES}
            "$<TARGET_BUNDLE_CONTENT_DIR:Readdict>/Resources/fonts/"
        COMMENT "拷贝字体到 bundle Resources/fonts"
    )
    # 部署脚本：cmake --build build --target deploy_script 即生成自包含 .app。
    # 三步部署：
    #  1) macdeployqt 直接部署运行时依赖（Qt 库 + PlugIns 插件 + qt.conf）——注意不能走
    #     qt_generate_deploy_app_script 的默认参数：其固定带 -appstore-compliant，
    #     会跳过私有 framework（QtQuickControls2Impl 等），导致插件 dlopen 失败。
    #  2) qt6_deploy_qml_imports 部署 QML 模块（QtQuick.Controls/Pdf/Effects 等，
    #     读 finalizer 写入的 deploy_qml_imports/Readdict.cmake 数据；插件二进制进
    #     PlugIns、qmldir 侧建符号链接）。
    #  3) 修复 QML 插件引用的私有 framework——macdeployqt 不扫描 Resources/qml 下的
    #     插件依赖，步骤 2 的插件在步骤 1 之后才出现，其 @rpath framework 缺失；
    #     扫描全包 dylib 的 @rpath 引用，把缺失的 framework 从 Qt lib 目录补拷。
    set(_readdict_deploy_support "${CMAKE_CURRENT_BINARY_DIR}/.qt/QtDeploySupport.cmake")
    set(_readdict_qt_lib "${Qt6_DIR}/../..")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/deploy_full.cmake"
"cmake_minimum_required(VERSION 3.16)
# D7 部署脚本（cmake -P 执行，CWD = build 目录）
include(\"${_readdict_deploy_support}\")
execute_process(COMMAND \"\${__QT_DEPLOY_TOOL}\" \"Readdict.app\" -always-overwrite
                RESULT_VARIABLE _deploy_result)
if(NOT _deploy_result EQUAL 0)
    message(FATAL_ERROR \"macdeployqt 部署失败: \${_deploy_result}\")
endif()
include(\"${Qt6_DIR}/../Qt6Qml/Qt6QmlDeploySupport.cmake\")
qt6_deploy_qml_imports(TARGET Readdict)
# 补拷缺失的 @rpath framework（QML 插件私有依赖）
file(GLOB_RECURSE _binaries
     \"Readdict.app/Contents/PlugIns/*.dylib\"
     \"Readdict.app/Contents/Resources/qml/*.dylib\"
     \"Readdict.app/Contents/MacOS/Readdict\"
     \"Readdict.app/Contents/Frameworks/*/*\")
set(_missing \"\")
foreach(_bin IN LISTS _binaries)
    execute_process(COMMAND /usr/bin/otool -L \"\${_bin}\"
                    OUTPUT_VARIABLE _otool_out ERROR_QUIET)
    string(REGEX MATCHALL \"@rpath/[A-Za-z0-9_.]+\\.framework\" _refs \"\${_otool_out}\")
    foreach(_ref IN LISTS _refs)
        get_filename_component(_name \"\${_ref}\" NAME)
        if(NOT EXISTS \"Readdict.app/Contents/Frameworks/\${_name}\")
            list(APPEND _missing \"\${_name}\")
        endif()
    endforeach()
endforeach()
if(_missing)
    list(REMOVE_DUPLICATES _missing)
    foreach(_fw IN LISTS _missing)
        message(STATUS \"补拷缺失 framework: \${_fw}\")
        file(COPY \"${_readdict_qt_lib}/\${_fw}\" DESTINATION \"Readdict.app/Contents/Frameworks/\")
    endforeach()
endif()
")
    add_custom_target(deploy_script
        COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_BINARY_DIR}/deploy_full.cmake"
        DEPENDS Readdict
    )
else()
    # 其他平台（Linux/Windows）：本项目当前只产出 macOS .app 分发物，跨平台安装打包
    # 尚未实施（无 install(TARGETS Readdict) 配套，仅装字体文件无意义）。
    # 此处安装字体仅保证「安装目录 + main.cpp 的 ../share/readdict/fonts 兜底路径」
    # 契约在将来补 install(TARGETS) 时直接生效；当前为 dev-only，安装打包留后续任务。
    install(FILES ${READDICT_FONT_FILES} DESTINATION share/readdict/fonts)
endif()

enable_testing()
add_subdirectory(tests)
