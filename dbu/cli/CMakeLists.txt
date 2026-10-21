cmake_minimum_required(VERSION 3.15)
project(ez_db_cli_shell C)

set(CMAKE_C_STANDARD 11)

# Specify the output path independently according to the operating system.
if(WIN32)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_compile_options(/utf-8)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/build_windows/bin)
else()
    add_definitions(-D_GNU_SOURCE)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/build_linux/bin)
endif()

include_directories(
    .
    ../../source
)

# 1. Interactive Shell executable (ez_shell)
add_executable(ez_shell dbu_shell.c)

# 2. Automated test agent executable file (ez_test_agent)
add_executable(ez_test_agent ez_test_agent.c dbu_shell.c)
target_compile_definitions(ez_test_agent PRIVATE TEST_AGENT)

if(UNIX)
    target_link_libraries(ez_shell PRIVATE dl)
    target_link_libraries(ez_test_agent PRIVATE dl)
endif()