cmake_minimum_required(VERSION 3.10)

# Specify compilers under Linux prior to project() to prevent CMake detection failures
if(NOT WIN32)
    if(NOT DEFINED CMAKE_CXX_COMPILER)
        find_program(SYSTEM_GXX g++)
        if(SYSTEM_GXX)
            set(CMAKE_CXX_COMPILER "${SYSTEM_GXX}" CACHE FILEPATH "C++ Compiler" FORCE)
        endif()
    endif()
    if(NOT DEFINED CMAKE_C_COMPILER)
        find_program(SYSTEM_GCC gcc)
        if(SYSTEM_GCC)
            set(CMAKE_C_COMPILER "${SYSTEM_GCC}" CACHE FILEPATH "C Compiler" FORCE)
        endif()
    endif()
endif()

project(ez_dbengine_ffi_cpp CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../..")

include_directories(
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${ROOT_DIR}/source"
)

# Specify platform-dependent output runtime directories
if(WIN32)
    set(PLATFORM_RUN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/run_win")
    add_compile_options("/utf-8" "/W4" "/std:c++17")
    link_directories(
        "${PLATFORM_RUN_DIR}"
        "${ROOT_DIR}/build_win/lib"
        "${ROOT_DIR}/build_win/bin"
    )
else()
    set(PLATFORM_RUN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/run_linux")
    add_compile_options(-Wall -Wextra -Wno-missing-field-initializers -O3)
    link_directories(
        "${PLATFORM_RUN_DIR}"
        "${ROOT_DIR}/build_linux/lib"
    )
endif()

# 1. Stress test executable
add_executable(ez_stress_master
    ez_stress_master.cpp 
    ez_dbengine.cpp
)
target_link_libraries(ez_stress_master PRIVATE ez_dbengine)
if(UNIX AND NOT APPLE)
    target_link_libraries(ez_stress_master PRIVATE pthread)
endif()

set_target_properties(ez_stress_master PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PLATFORM_RUN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${PLATFORM_RUN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${PLATFORM_RUN_DIR}"
)

# 2. Multi-table relation demo executable
add_executable(relation_demo
    relation_demo.cpp
    ez_dbengine.cpp
)
target_link_libraries(relation_demo PRIVATE ez_dbengine)
if(UNIX AND NOT APPLE)
    target_link_libraries(relation_demo PRIVATE pthread)
endif()

set_target_properties(relation_demo PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PLATFORM_RUN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${PLATFORM_RUN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${PLATFORM_RUN_DIR}"
)