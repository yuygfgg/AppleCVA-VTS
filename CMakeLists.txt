cmake_minimum_required(VERSION 3.20)

if(APPLE AND NOT CMAKE_OSX_SYSROOT)
    execute_process(
        COMMAND xcrun --sdk macosx --show-sdk-path
        OUTPUT_VARIABLE APPLECVA_MACOS_SDK
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
    if(APPLECVA_MACOS_SDK)
        set(CMAKE_OSX_SYSROOT "${APPLECVA_MACOS_SDK}"
            CACHE PATH "macOS SDK used for AppleCVA builds" FORCE)
    endif()
endif()

project(AppleCVAVTSSource VERSION 0.1.0 LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_MACOSX_RPATH ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

set_source_files_properties(apps/vts_source/qml/Main.qml
    PROPERTIES
        QT_RESOURCE_ALIAS Main.qml)

set(APPLECVA_APP_NAME "AppleCVA VTS Source")
set(APPLECVA_BUNDLE_IDENTIFIER "local.applecva.vts-source")
set(APPLECVA_CODESIGN_IDENTITY "-"
    CACHE STRING "Code signing identity for the macOS app bundle; '-' uses ad-hoc signing")

set(APPLECVA_FRAMEWORKS
    Foundation
    Vision
    CoreFoundation
    CoreGraphics
    CoreVideo
    CoreMedia
    ImageIO)

set(VTS_SOURCE_FRAMEWORKS
    AVFoundation
    QuartzCore)

function(target_link_apple_frameworks target visibility)
    foreach(framework IN LISTS ARGN)
        target_link_libraries(${target} ${visibility}
                              "-framework ${framework}")
    endforeach()
endfunction()

add_library(applecva SHARED
    lib/applecva.m)

target_include_directories(applecva
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include)

target_compile_options(applecva
    PRIVATE
        -Wall
        -Wextra
        -fobjc-arc)

target_link_apple_frameworks(applecva PUBLIC ${APPLECVA_FRAMEWORKS})

set_target_properties(applecva
    PROPERTIES
        OUTPUT_NAME applecva
        INSTALL_NAME_DIR "@rpath")

qt_add_executable(vts_source
    MACOSX_BUNDLE
    common/capture.m
    common/tracking_utils.m
    common/tracking_pipeline.m
    apps/vts_source/qt/main.cpp
    apps/vts_source/qt/controller.h
    apps/vts_source/qt/controller.mm
    apps/vts_source/qt/preview_item.h
    apps/vts_source/qt/preview_item.cpp
    apps/vts_source/calibration.m
    apps/vts_source/client.m
    apps/vts_source/parameters.m)

qt_add_qml_module(vts_source
    URI AppleCVAVTSSource
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        apps/vts_source/qml/Main.qml)

target_include_directories(vts_source
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/common
        ${CMAKE_CURRENT_SOURCE_DIR}/apps/vts_source
        ${CMAKE_CURRENT_SOURCE_DIR}/apps/vts_source/qt)

target_compile_options(vts_source
    PRIVATE
        -Wall
        -Wextra
        $<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>)

target_link_libraries(vts_source PRIVATE
    applecva
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2)
target_link_apple_frameworks(vts_source
    PRIVATE
        ${APPLECVA_FRAMEWORKS}
        ${VTS_SOURCE_FRAMEWORKS})

set_target_properties(vts_source
    PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "${APPLECVA_APP_NAME}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${APPLECVA_BUNDLE_IDENTIFIER}"
        MACOSX_BUNDLE_INFO_PLIST
            "${CMAKE_CURRENT_SOURCE_DIR}/apps/vts_source/VTSSourceInfo.plist"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        OUTPUT_NAME "${APPLECVA_APP_NAME}"
        BUILD_RPATH "@executable_path/../Frameworks"
        INSTALL_RPATH "@executable_path/../Frameworks")

add_custom_command(TARGET vts_source POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_BUNDLE_DIR:vts_source>/Contents/Frameworks"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "$<TARGET_FILE:applecva>"
            "$<TARGET_BUNDLE_DIR:vts_source>/Contents/Frameworks/"
    COMMAND /usr/bin/codesign --force --deep --sign
            "${APPLECVA_CODESIGN_IDENTITY}"
            "$<TARGET_BUNDLE_DIR:vts_source>"
    COMMENT "Embedding applecva and signing the app bundle"
    VERBATIM)

add_custom_target(vts_source_codesign ALL
    COMMAND /usr/bin/codesign --force --deep --sign
            "${APPLECVA_CODESIGN_IDENTITY}"
            "$<TARGET_BUNDLE_DIR:vts_source>"
    DEPENDS vts_source
    COMMENT "Signing the app bundle"
    VERBATIM)

install(TARGETS vts_source
    BUNDLE DESTINATION ".")
install(CODE "
    execute_process(
        COMMAND /usr/bin/codesign --force --deep --sign
                \"${APPLECVA_CODESIGN_IDENTITY}\"
                \"\${CMAKE_INSTALL_PREFIX}/${APPLECVA_APP_NAME}.app\"
        COMMAND_ERROR_IS_FATAL ANY)
")

set(CPACK_GENERATOR "ZIP")
set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
set(CPACK_PACKAGE_CHECKSUM SHA256)
set(CPACK_PACKAGE_FILE_NAME
    "AppleCVA-VTS-Source-${PROJECT_VERSION}-macos"
    CACHE STRING "Base file name for generated packages")
set(CPACK_PACKAGE_NAME "AppleCVA-VTS-Source")
set(CPACK_PACKAGE_VENDOR "AppleCVA")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
include(CPack)
