cmake_minimum_required(VERSION 3.10)
project(ez_dbengine_test C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
include_directories("${ROOT_DIR}/source")

if(WIN32)
    add_compile_options("/utf-8" "/W4")
    link_directories(
        "${ROOT_DIR}/build_win/lib/$<CONFIG>"
        "${ROOT_DIR}/build_win/bin/$<CONFIG>"
    )
endif()

# 1. C Stress test target
add_executable(ez_stress_master ez_stress_master.c)
target_link_libraries(ez_stress_master PRIVATE ez_dbengine)

# 2. Vector quantization algorithm test target
add_executable(test_quant test_quant.c)
target_link_libraries(test_quant PRIVATE ez_dbengine)

set_target_properties(ez_stress_master test_quant PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/release"
)