cmake_minimum_required(VERSION 3.21)
project(Readdict VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Sql Network Pdf TextToSpeech Multimedia Test QuickTest)

qt_standard_project_setup()

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
