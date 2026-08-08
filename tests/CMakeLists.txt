qt_add_executable(tst_database tst_database.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp)
target_include_directories(tst_database PRIVATE ../src)
target_link_libraries(tst_database PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_database COMMAND tst_database)

qt_add_executable(tst_bookmanager
    tst_bookmanager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
    # C8：removeBook 清理 fts_content 的集成用例
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SearchEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/TextParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/EpubParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/Fb2Parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/MobiParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/ParserFactory.cpp
)
target_include_directories(tst_bookmanager PRIVATE ../src ../src/parsers ../third_party/libmobi/src)
# B10：loadChapter 进度百分比用例需解析 sample.epub fixture（绝对路径注入，同 tst_epubparser 模式）
target_compile_definitions(tst_bookmanager PRIVATE EPUB_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
target_link_libraries(tst_bookmanager PRIVATE Qt6::Test Qt6::Sql Qt6::Gui MINIZIP::minizipstatic mobi zlibstatic)
if(APPLE)
    target_link_libraries(tst_bookmanager PRIVATE iconv)
endif()
add_test(NAME tst_bookmanager COMMAND tst_bookmanager)

qt_add_executable(tst_highlights
    tst_highlights.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/HighlightManager.cpp
)
target_include_directories(tst_highlights PRIVATE ../src)
target_link_libraries(tst_highlights PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_highlights COMMAND tst_highlights)

qt_add_executable(tst_settings tst_settings.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp)
target_include_directories(tst_settings PRIVATE ../src)
target_link_libraries(tst_settings PRIVATE Qt6::Test)
add_test(NAME tst_settings COMMAND tst_settings)

# C8：FTS5 全文搜索（SearchEngine）
qt_add_executable(tst_search tst_search.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SearchEngine.cpp)
target_include_directories(tst_search PRIVATE ../src)
target_link_libraries(tst_search PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_search COMMAND tst_search)

qt_add_executable(tst_bookimporter
    tst_bookimporter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookImporter.cpp
    # C8：导入后全文索引（BookImporter::indexBook → SearchEngine）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SearchEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/TextParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/EpubParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/Fb2Parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/MobiParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/ParserFactory.cpp
)
target_include_directories(tst_bookimporter PRIVATE ../src ../src/parsers ../third_party/libmobi/src)
target_link_libraries(tst_bookimporter PRIVATE Qt6::Test Qt6::Sql Qt6::Gui Qt6::Pdf MINIZIP::minizipstatic mobi zlibstatic)
if(APPLE)
    target_link_libraries(tst_bookimporter PRIVATE iconv)
endif()
add_test(NAME tst_bookimporter COMMAND tst_bookimporter)

qt_add_executable(tst_sentencesplitter tst_sentencesplitter.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp)
target_include_directories(tst_sentencesplitter PRIVATE ../src ../src/parsers)
target_link_libraries(tst_sentencesplitter PRIVATE Qt6::Test)
add_test(NAME tst_sentencesplitter COMMAND tst_sentencesplitter)

qt_add_executable(tst_textparser tst_textparser.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/TextParser.cpp)
target_include_directories(tst_textparser PRIVATE ../src ../src/parsers)
target_link_libraries(tst_textparser PRIVATE Qt6::Test)
# TextParser 的 GB18030 解码走系统 iconv；macOS 的 iconv 在 libiconv.dylib 中需显式链接
if(APPLE)
    target_link_libraries(tst_textparser PRIVATE iconv)
endif()
add_test(NAME tst_textparser COMMAND tst_textparser)

qt_add_executable(tst_epubparser
    tst_epubparser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/EpubParser.cpp
)
target_include_directories(tst_epubparser PRIVATE ../src ../src/parsers)
# fixture 目录绝对路径注入（见 tst_epubparser.cpp 顶部说明）
target_compile_definitions(tst_epubparser PRIVATE EPUB_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
# minizip：unzip.h 的 include 路径由 MINIZIP::minizipstatic 的 PUBLIC include 传递
target_link_libraries(tst_epubparser PRIVATE Qt6::Test MINIZIP::minizipstatic zlibstatic)
add_test(NAME tst_epubparser COMMAND tst_epubparser)

qt_add_executable(tst_fb2parser
    tst_fb2parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/Fb2Parser.cpp
)
target_include_directories(tst_fb2parser PRIVATE ../src ../src/parsers)
# fixture 目录绝对路径注入（见 tst_fb2parser.cpp 顶部说明）
target_compile_definitions(tst_fb2parser PRIVATE FB2_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
target_link_libraries(tst_fb2parser PRIVATE Qt6::Test)
add_test(NAME tst_fb2parser COMMAND tst_fb2parser)

qt_add_executable(tst_mobiparser
    tst_mobiparser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/MobiParser.cpp
)
target_include_directories(tst_mobiparser PRIVATE ../src ../src/parsers ../third_party/libmobi/src)
# libmobi：静态库 mobi（PUBLIC 传递 zlib），include 路径由 src/CMakeLists 传递
target_link_libraries(tst_mobiparser PRIVATE Qt6::Test mobi zlibstatic)
add_test(NAME tst_mobiparser COMMAND tst_mobiparser)

qt_add_executable(tst_ttsurl
    tst_ttsurl.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TTSEngine.h
)
target_include_directories(tst_ttsurl PRIVATE ../src ../src/tts)
# OpenAITTSEngine 声明含 QNetworkAccessManager/QMediaPlayer 成员，需 Network/Multimedia 模块
target_link_libraries(tst_ttsurl PRIVATE Qt6::Test Qt6::Network Qt6::Multimedia)
add_test(NAME tst_ttsurl COMMAND tst_ttsurl)

qt_add_executable(tst_ttsengine
    tst_ttsengine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TTSEngine.h
)
target_include_directories(tst_ttsengine PRIVATE ../src ../src/tts)
target_link_libraries(tst_ttsengine PRIVATE Qt6::Test Qt6::Network Qt6::Multimedia)
add_test(NAME tst_ttsengine COMMAND tst_ttsengine)

qt_add_executable(tst_ttscontroller
    tst_ttscontroller.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TtsController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TtsController.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/SystemTTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/SystemTTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TTSEngine.h
)
target_include_directories(tst_ttscontroller PRIVATE ../src ../src/tts)
# TtsController::reconfigure 会实例化两个具体引擎，需 Network/Multimedia/TextToSpeech
target_link_libraries(tst_ttscontroller PRIVATE Qt6::Test Qt6::Network Qt6::Multimedia Qt6::TextToSpeech)
add_test(NAME tst_ttscontroller COMMAND tst_ttscontroller)

qt_add_executable(tst_parserfactory
    tst_parserfactory.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/TextParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/EpubParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/Fb2Parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/MobiParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/ParserFactory.cpp
)
target_include_directories(tst_parserfactory PRIVATE ../src ../src/parsers ../third_party/libmobi/src)
# fixture 目录绝对路径注入（见 tst_parserfactory.cpp 顶部说明）
target_compile_definitions(tst_parserfactory PRIVATE PARSER_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
target_link_libraries(tst_parserfactory PRIVATE Qt6::Test MINIZIP::minizipstatic mobi zlibstatic)
if(APPLE)
    target_link_libraries(tst_parserfactory PRIVATE iconv)
endif()
add_test(NAME tst_parserfactory COMMAND tst_parserfactory)

# QML 冒烟/端到端测试：自定义 main（tst_qmlmain.cpp）注册 Readdict.Backend 单例，
# 因为单例只在生产 main.cpp 中注册；不依赖 Qt 内部的 QUICK_TEST_SOURCE_DIR 自动 main，
# 该宏由下方 target_compile_definitions 提供（tests/qml 绝对路径）。
qt_add_executable(tst_qml
    qml/tst_qmlmain.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookImporter.cpp
    # C7：Highlights 单例（划线数据流冒烟）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/HighlightManager.cpp
    # C8：Search 单例（全文搜索冒烟）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SearchEngine.cpp
    # C7：TextEdit 行距助手（段落渲染用 TextEdit）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/ReaderTextHelper.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/ReaderTextHelper.h
    # D6：语言控制器（Lang 单例，QML 冒烟驱动三语切换）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/LanguageController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/LanguageController.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/SentenceSplitter.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/TextParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/EpubParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/Fb2Parser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/MobiParser.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/parsers/ParserFactory.cpp
    # C5：Tts 单例（无引擎桩）供 TtsBar/高亮冒烟
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TtsController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TtsController.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/SystemTTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/SystemTTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/OpenAITTSEngine.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/tts/TTSEngine.h
    # D3：Sync 单例（SyncPage 冒烟 + 错误配置 finished(false) 验证）
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncController.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncManager.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.h
)
target_include_directories(tst_qml PRIVATE ../src ../src/parsers ../third_party/libmobi/src)
target_compile_definitions(tst_qml PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
# B10：QML 冒烟需要导入多章节 EPUB fixture（sample.epub）与长文本书（滚动恢复用例），
# 绝对路径注入经 TestEnv 暴露为 file:// URL（与 tst_epubparser 的 fixtures 注入同模式）
target_compile_definitions(tst_qml PRIVATE TEST_FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
target_link_libraries(tst_qml PRIVATE
    Qt6::Test Qt6::QuickTest Qt6::Quick Qt6::Qml Qt6::QuickControls2 Qt6::Sql Qt6::Gui Qt6::Pdf
    Qt6::Network Qt6::Multimedia Qt6::TextToSpeech
    MINIZIP::minizipstatic mobi zlibstatic
)
if(APPLE)
    target_link_libraries(tst_qml PRIVATE iconv)
endif()
# 书架页冒烟测试按 qrc 路径加载真实 UI 组件，需把对应 QML 文件以相同前缀编入测试资源
qt_add_resources(tst_qml "qml_ui"
    PREFIX "/qt/qml/Readdict/ui/qml"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/qml"
    FILES
        ../src/ui/qml/Main.qml
        ../src/ui/qml/KdTabBar.qml
        ../src/ui/qml/KdBottomNav.qml
        ../src/ui/qml/KdIcons.qml
        ../src/ui/qml/KdListItem.qml
        ../src/ui/qml/KdRadioGrid.qml
        ../src/ui/qml/KdSegmentedSlider.qml
        ../src/ui/qml/KdToggle.qml
        ../src/ui/qml/KdBottomSheet.qml
        ../src/ui/qml/ThemeSheet.qml
        ../src/ui/qml/FontSheet.qml
        ../src/ui/qml/LayoutSheet.qml
        ../src/ui/qml/MoreSheet.qml
        ../src/ui/qml/ShelfPage.qml
        ../src/ui/qml/BookCard.qml
        ../src/ui/qml/SettingsPage.qml
        ../src/ui/qml/SettingsLanguagePage.qml
        ../src/ui/qml/SettingsTtsPage.qml
        ../src/ui/qml/SettingsBackgroundPage.qml
        ../src/ui/qml/SyncPage.qml
        ../src/ui/qml/StatsPage.qml
        ../src/ui/qml/ReaderPage.qml
        ../src/ui/qml/ReaderContent.qml
        ../src/ui/qml/ReaderControls.qml
        ../src/ui/qml/ReaderBackground.qml
        ../src/ui/qml/Theme.qml
        ../src/ui/qml/TtsBar.qml
        ../src/ui/qml/PdfReaderPage.qml
)
add_test(NAME tst_qml COMMAND tst_qml)

# D6：三语 .qm 编入 QML 测试资源（:/i18n/readdict_<code>.qm），使 Lang 单例在
# 测试进程中真实加载翻译；lrelease 目标先于测试产出 qm（qt_add_translations
# 生成 Readdict_lrelease 自定义目标，见顶层 CMakeLists）。
add_dependencies(tst_qml Readdict_lrelease)
# 绝对路径文件入资源需 QT_RESOURCE_ALIAS（Qt 6.11 策略）；必须逐文件设置，
# 列表形式会把同一别名赋给全部文件（别名冲突导致 zh_CN 命中 en 内容）
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_zh_CN.qm PROPERTIES QT_RESOURCE_ALIAS readdict_zh_CN.qm)
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_zh_TW.qm PROPERTIES QT_RESOURCE_ALIAS readdict_zh_TW.qm)
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_en.qm PROPERTIES QT_RESOURCE_ALIAS readdict_en.qm)
qt_add_resources(tst_qml "i18n_qm"
    PREFIX "/i18n"
    FILES
        ${CMAKE_BINARY_DIR}/readdict_zh_CN.qm
        ${CMAKE_BINARY_DIR}/readdict_zh_TW.qm
        ${CMAKE_BINARY_DIR}/readdict_en.qm
)

# D6：语言控制器单元测试——真实 .qm（同 tst_qml 的资源嵌入方式）验证
# applyLanguage 切换后 QCoreApplication::translate 命中三语翻译
qt_add_executable(tst_language
    tst_language.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/LanguageController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/LanguageController.h
)
target_include_directories(tst_language PRIVATE ../src ../src/ui)
target_link_libraries(tst_language PRIVATE Qt6::Test Qt6::Gui)
add_dependencies(tst_language Readdict_lrelease)
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_zh_CN.qm PROPERTIES QT_RESOURCE_ALIAS readdict_zh_CN.qm)
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_zh_TW.qm PROPERTIES QT_RESOURCE_ALIAS readdict_zh_TW.qm)
set_source_files_properties(${CMAKE_BINARY_DIR}/readdict_en.qm PROPERTIES QT_RESOURCE_ALIAS readdict_en.qm)
qt_add_resources(tst_language "i18n_qm"
    PREFIX "/i18n"
    FILES
        ${CMAKE_BINARY_DIR}/readdict_zh_CN.qm
        ${CMAKE_BINARY_DIR}/readdict_zh_TW.qm
        ${CMAKE_BINARY_DIR}/readdict_en.qm
)
add_test(NAME tst_language COMMAND tst_language)

# D1：WebDAV 协议客户端（自实现 PROPFIND/MKCOL/PUT/GET/DELETE，本地 QTcpServer mock）
qt_add_executable(tst_webdav tst_webdav.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.cpp)
target_include_directories(tst_webdav PRIVATE ../src ../src/sync)
target_link_libraries(tst_webdav PRIVATE Qt6::Test Qt6::Network)
add_test(NAME tst_webdav COMMAND tst_webdav)

# D2：SyncManager（数据打包/合并/冲突解决；MockWebDavClient 走虚接口，见 tst_syncmanager.cpp 头注释）
qt_add_executable(tst_syncmanager
    tst_syncmanager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/HighlightManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
)
target_include_directories(tst_syncmanager PRIVATE ../src ../src/sync)
target_link_libraries(tst_syncmanager PRIVATE Qt6::Test Qt6::Sql Qt6::Network)
add_test(NAME tst_syncmanager COMMAND tst_syncmanager)

# D3：SyncController（真实 WebDavClient 走本地 QTcpServer mock：成功上传路径 +
# 不可达服务器失败路径 + 自动同步开关/空转 run 防重入）
qt_add_executable(tst_synccontroller
    tst_synccontroller.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncController.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncController.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/SyncManager.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/sync/WebDavClient.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
)
target_include_directories(tst_synccontroller PRIVATE ../src ../src/sync)
target_link_libraries(tst_synccontroller PRIVATE Qt6::Test Qt6::Sql Qt6::Network)
add_test(NAME tst_synccontroller COMMAND tst_synccontroller)
