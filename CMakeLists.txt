cmake_minimum_required(VERSION 3.21)
project(Readdict VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Sql Network Pdf TextToSpeech Multimedia Test QuickTest)

qt_standard_project_setup()

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
    src/core/BookImporter.cpp
)
qt_add_qml_module(Readdict
    URI Readdict
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    OUTPUT_DIRECTORY ReaddictQml
    QML_FILES
        src/ui/qml/Main.qml
        src/ui/qml/ShelfPage.qml
        src/ui/qml/BookCard.qml
        src/ui/qml/SettingsPage.qml
)

qt_add_resources(Readdict "app_resources"
    PREFIX "/"
    FILES resources.qrc
)

target_include_directories(Readdict PRIVATE src)
target_link_libraries(Readdict PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Network
)

enable_testing()
add_subdirectory(tests)
