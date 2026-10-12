cmake_minimum_required(VERSION 3.20)
project(refocal_s6_ffi CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

# SANITIZE=thread | address (ASan+LSan+UBSan) | empty
set(SANITIZE "" CACHE STRING "sanitizer build")
if(SANITIZE STREQUAL "thread")
  add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
  add_link_options(-fsanitize=thread)
elseif(SANITIZE STREQUAL "address")
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=address,undefined)
endif()

get_filename_component(SPEC_APPENDIX "${CMAKE_CURRENT_SOURCE_DIR}/../../../docs/spec/appendix" ABSOLUTE)

# Variant B (Dart native port) needs dart_api_dl.c from the Dart SDK (BSD-3-Clause).
set(DART_SDK_INCLUDE "$ENV{HOME}/sdk/dart-sdk/include" CACHE PATH "dart-sdk/include")
add_library(enh_mock SHARED src/core.cpp)
target_include_directories(enh_mock PUBLIC include ${SPEC_APPENDIX})
if(EXISTS "${DART_SDK_INCLUDE}/dart_api_dl.c")
  enable_language(C)
  target_sources(enh_mock PRIVATE "${DART_SDK_INCLUDE}/dart_api_dl.c")
  target_include_directories(enh_mock PRIVATE "${DART_SDK_INCLUDE}")
  target_compile_definitions(enh_mock PRIVATE ENH_WITH_DART_PORT)
else()
  message(WARNING "dart_api_dl.c not found in ${DART_SDK_INCLUDE}: variant B disabled")
endif()
set_source_files_properties(src/core.cpp PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra")

enable_testing()
add_executable(stress tests/stress.cpp)
target_link_libraries(stress PRIVATE enh_mock)
add_test(NAME stress COMMAND stress 400)
