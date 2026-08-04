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
