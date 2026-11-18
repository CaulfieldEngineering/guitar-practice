# Practice for Windows: the guitar practice app's desktop version (JUCE, C++20). desktop/README.md says why JUCE.
# Built on the mini PC (Visual Studio 2022 Build Tools + CMake), like Duet's engine:
#   cmake -S desktop -B desktop/build -G "Visual Studio 17 2022" -A x64
#   cmake --build desktop/build --config Release
# or all of it, tests and the installer: powershell -File desktop/scripts/build.ps1
cmake_minimum_required(VERSION 3.22)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" PRACTICE_VERSION LIMIT_COUNT 1)
string(STRIP "${PRACTICE_VERSION}" PRACTICE_VERSION)
project(PracticeDesktop VERSION ${PRACTICE_VERSION} LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# One static runtime: nothing to install beside the program on the laptop.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# A plain JUCE 7.0.12 clone beside the repo (GitHub\JUCE-7.0.12), as Duet uses.
set(PRACTICE_JUCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../JUCE-7.0.12" CACHE PATH "The JUCE source tree")
if(NOT EXISTS "${PRACTICE_JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "JUCE not found at PRACTICE_JUCE_DIR=${PRACTICE_JUCE_DIR}.")
endif()
add_subdirectory("${PRACTICE_JUCE_DIR}" "${CMAKE_BINARY_DIR}/juce")

# The Steinberg ASIO SDK, unpacked beside the repo (GitHub\_sdk\ASIOSDK). Without it the app still has WASAPI.
set(PRACTICE_ASIO_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../_sdk/ASIOSDK" CACHE PATH "The ASIO SDK (folder holding common/iasiodrv.h)")

set(PRACTICE_CORE
    src/core/Scoring.cpp
    src/core/Drill.cpp
    src/core/OnsetDetector.cpp
    src/core/Results.cpp
    src/engine/DeviceController.cpp
    src/engine/AudioEngine.cpp
    src/app/Store.cpp
    src/app/Sync.cpp)

set(PRACTICE_DEFS
    PRACTICE_VERSION="${PRACTICE_VERSION}"
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
    JUCE_USE_MP3AUDIOFORMAT=1
    JUCE_USE_FLAC=0
    JUCE_USE_OGGVORBIS=0
    JUCE_USE_WINDOWS_MEDIA_FORMAT=0
    JUCE_WASAPI=1
    JUCE_DIRECTSOUND=0
    JUCE_STRICT_REFCOUNTEDPOINTER=1)

function(practice_asio target)
    if(EXISTS "${PRACTICE_ASIO_SDK_DIR}/common/iasiodrv.h")
        target_compile_definitions(${target} PRIVATE JUCE_ASIO=1)
        target_include_directories(${target} PRIVATE "${PRACTICE_ASIO_SDK_DIR}/common")
    else()
        target_compile_definitions(${target} PRIVATE JUCE_ASIO=0)
    endif()
endfunction()

# ---- the app ----
option(PRACTICE_TESTS_ONLY "Build only the tests" OFF)
if(NOT PRACTICE_TESTS_ONLY)
juce_add_gui_app(Practice
    PRODUCT_NAME "Practice"
    VERSION ${PRACTICE_VERSION}
    COMPANY_NAME "Caulfield Engineering"
    ICON_BIG "${CMAKE_CURRENT_SOURCE_DIR}/assets/icon.png")
juce_generate_juce_header(Practice)
target_sources(Practice PRIVATE
    ${PRACTICE_CORE}
    src/app/Model.cpp
    src/app/Voice.cpp
    src/ui/Theme.cpp
    src/ui/Widgets.cpp
    src/ui/Screens.cpp
    src/ui/RunScreens.cpp
    src/ui/SettingsScreens.cpp
    src/ui/MainComponent.cpp
    src/Main.cpp)
target_compile_definitions(Practice PRIVATE ${PRACTICE_DEFS}
    JUCE_APPLICATION_NAME_STRING="$<TARGET_PROPERTY:Practice,JUCE_PRODUCT_NAME>"
    JUCE_APPLICATION_VERSION_STRING="$<TARGET_PROPERTY:Practice,JUCE_VERSION>")
practice_asio(Practice)
target_link_libraries(Practice
    PRIVATE juce::juce_gui_extra juce::juce_audio_utils juce::juce_audio_devices juce::juce_audio_formats
    PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_lto_flags juce::juce_recommended_warning_flags)
endif()

# ---- the tests: scoring parity with the shared vectors, the detector, device picks under stress, sync ----
juce_add_console_app(PracticeTests PRODUCT_NAME "PracticeTests")
juce_generate_juce_header(PracticeTests)
target_sources(PracticeTests PRIVATE ${PRACTICE_CORE} tests/Tests.cpp)
target_compile_definitions(PracticeTests PRIVATE ${PRACTICE_DEFS}
    PRACTICE_REPO="${CMAKE_CURRENT_SOURCE_DIR}/.."
    JUCE_APPLICATION_NAME_STRING="PracticeTests" JUCE_APPLICATION_VERSION_STRING="${PRACTICE_VERSION}")
practice_asio(PracticeTests)
target_link_libraries(PracticeTests
    PRIVATE juce::juce_audio_devices juce::juce_audio_formats juce::juce_events
    PUBLIC juce::juce_recommended_config_flags)
