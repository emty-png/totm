cmake_minimum_required(VERSION 3.21)
project(totm VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Svg Multimedia ShaderTools Network)

qt_standard_project_setup()

add_subdirectory(src)

install(TARGETS totm
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

# Windows installer (NSIS via CPack). Qt DLLs are deployed by
# packaging/nsis-deploy.cmake via install(SCRIPT), which runs after
# bin/totm.exe is staged (CPACK_INSTALL_SCRIPT would run before it exists).
if(WIN32)
    set(CPACK_PACKAGE_NAME "totm")
    set(CPACK_PACKAGE_VENDOR "tot")
    set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "That one tool for motion")
    set(CPACK_NSIS_DISPLAY_NAME "totm motion graphics editor")
    set(CPACK_NSIS_PACKAGE_NAME "totm ${PROJECT_VERSION}")
    set(CPACK_NSIS_MUI_ICON "${PROJECT_SOURCE_DIR}/packaging/icons/totm.ico")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    configure_file(
        "${PROJECT_SOURCE_DIR}/packaging/nsis-deploy.cmake.in"
        "${PROJECT_BINARY_DIR}/nsis-deploy.cmake"
        @ONLY
    )
    install(SCRIPT "${PROJECT_BINARY_DIR}/nsis-deploy.cmake")
    include(CPack)
endif()
