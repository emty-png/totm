cmake_minimum_required(VERSION 3.21)
project(totm VERSION 0.7.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick Svg Multimedia ShaderTools Network)

qt_standard_project_setup()

add_subdirectory(src)

install(TARGETS totm
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

# Windows installer (NSIS via CPack). Qt DLLs are staged by
# packaging/nsis-deploy.cmake via install(SCRIPT) so it runs after bin/totm.exe.
if(WIN32)
    set(CPACK_PACKAGE_NAME "totm")
    set(CPACK_PACKAGE_VENDOR "tot")
    set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "That one tool for motion")
    set(CPACK_NSIS_DISPLAY_NAME "totm motion graphics editor")
    set(CPACK_NSIS_PACKAGE_NAME "totm ${PROJECT_VERSION}")
    set(CPACK_NSIS_MUI_ICON "${PROJECT_SOURCE_DIR}/packaging/icons/totm.ico")
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
    # .totm association (exe handles argv + single-instance forwarding).
    # Uninstall only clears keys still pointing at totm.
    set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "
        WriteRegStr HKCR '.totm' '' 'totm.design'
        WriteRegStr HKCR 'totm.design' '' 'totm design'
        WriteRegStr HKCR 'totm.design\\\\DefaultIcon' '' '$INSTDIR\\\\bin\\\\totm.exe,0'
        WriteRegStr HKCR 'totm.design\\\\shell\\\\open\\\\command' '' '\\\"$INSTDIR\\\\bin\\\\totm.exe\\\" \\\"%1\\\"'
        System::Call 'Shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
    ")
    set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS "
        DeleteRegKey HKCR 'totm.design'
        ReadRegStr $0 HKCR '.totm' ''
        StrCmp $0 'totm.design' 0 +2
            DeleteRegValue HKCR '.totm' ''
        System::Call 'Shell32::SHChangeNotify(i 0x08000000, i 0, i 0, i 0)'
    ")
    configure_file(
        "${PROJECT_SOURCE_DIR}/packaging/nsis-deploy.cmake.in"
        "${PROJECT_BINARY_DIR}/nsis-deploy.cmake"
        @ONLY
    )
    install(SCRIPT "${PROJECT_BINARY_DIR}/nsis-deploy.cmake")
    include(CPack)
endif()
