cmake_minimum_required(VERSION 3.21)
project(totm VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick)

qt_standard_project_setup()

add_subdirectory(src)

# Sampler conformance (samplerconf + cppdump + conform.py). Dev-only,
# never shipped; keeps the C++ video sampler bit-identical to QML.
option(TOTM_BUILD_TESTS "Build sampler conformance tests" ON)
if(TOTM_BUILD_TESTS)
    add_subdirectory(tests)
endif()

install(TARGETS totm
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
