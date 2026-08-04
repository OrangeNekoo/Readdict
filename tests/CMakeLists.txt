qt_add_executable(tst_database tst_database.cpp ${CMAKE_CURRENT_SOURCE_DIR}/../src/core/DatabaseManager.cpp)
target_include_directories(tst_database PRIVATE ../src)
target_link_libraries(tst_database PRIVATE Qt6::Test Qt6::Sql)
add_test(NAME tst_database COMMAND tst_database)
