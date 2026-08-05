qt_add_executable(tst_database tst_database.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp)
target_include_directories(tst_database PRIVATE ../src)
target_link_libraries(tst_database PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_database COMMAND tst_database)

qt_add_executable(tst_bookmanager tst_bookmanager.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp)
target_include_directories(tst_bookmanager PRIVATE ../src)
target_link_libraries(tst_bookmanager PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_bookmanager COMMAND tst_bookmanager)

qt_add_executable(tst_settings tst_settings.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp)
target_include_directories(tst_settings PRIVATE ../src)
target_link_libraries(tst_settings PRIVATE Qt6::Test)
add_test(NAME tst_settings COMMAND tst_settings)

qt_add_executable(tst_bookimporter tst_bookimporter.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookImporter.cpp)
target_include_directories(tst_bookimporter PRIVATE ../src)
target_link_libraries(tst_bookimporter PRIVATE Qt6::Test Qt6::Sql Qt6::Gui)
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

# QML 冒烟/端到端测试：自定义 main（tst_qmlmain.cpp）注册 Readdict.Backend 单例，
# 因为单例只在生产 main.cpp 中注册；不依赖 Qt 内部的 QUICK_TEST_SOURCE_DIR 自动 main，
# 该宏由下方 target_compile_definitions 提供（tests/qml 绝对路径）。
qt_add_executable(tst_qml
    qml/tst_qmlmain.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/SettingsStore.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/BookImporter.cpp
)
target_include_directories(tst_qml PRIVATE ../src)
target_compile_definitions(tst_qml PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
target_link_libraries(tst_qml PRIVATE
    Qt6::Test Qt6::QuickTest Qt6::Quick Qt6::Qml Qt6::QuickControls2 Qt6::Sql Qt6::Gui
)
# 书架页冒烟测试按 qrc 路径加载真实 UI 组件，需把对应 QML 文件以相同前缀编入测试资源
qt_add_resources(tst_qml "qml_ui"
    PREFIX "/qt/qml/Readdict/ui/qml"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../src/ui/qml"
    FILES
        ../src/ui/qml/ShelfPage.qml
        ../src/ui/qml/BookCard.qml
)
add_test(NAME tst_qml COMMAND tst_qml)
