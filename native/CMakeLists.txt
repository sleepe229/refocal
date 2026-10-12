# Refocal native core: libenh (C ABI in include/enh.h).
# Consumers: packages/refocal_ffi (Android via AGP externalNativeBuild; iOS via xcframework),
# tools/refocal-cli and native tests (desktop).
cmake_minimum_required(VERSION 3.22)
project(refocal_native VERSION 0.0.1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(ENH_VULKAN "ncnn Vulkan backend" ${ANDROID})
option(ENH_BUILD_TESTS "native tests (desktop)" OFF)
set(ENH_SANITIZE "" CACHE STRING "address (ASan+UBSan) | thread | empty")

if(ENH_SANITIZE STREQUAL "address")
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=address,undefined)
elseif(ENH_SANITIZE STREQUAL "thread")
  add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
  add_link_options(-fsanitize=thread)
endif()

# Reproducible builds (S8): no absolute source/build paths in objects or debug info.
add_compile_options(
  "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=."
  "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build")

# ---- ncnn (git submodule, BSD-3-Clause) ----
set(NCNN_VULKAN ${ENH_VULKAN} CACHE BOOL "" FORCE)
set(NCNN_SHARED_LIB OFF CACHE BOOL "" FORCE)
set(NCNN_INSTALL_SDK OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(NCNN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(NCNN_PYTHON OFF CACHE BOOL "" FORCE)
set(NCNN_PIXEL_DRAWING OFF CACHE BOOL "" FORCE)
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn/CMakeLists.txt")
  message(FATAL_ERROR "ncnn submodule missing: git submodule update --init --recursive")
endif()
add_subdirectory(third_party/ncnn EXCLUDE_FROM_ALL)

# ---- libenh ----
add_library(enh SHARED core/src/enh.cpp core/src/probe.cpp)
target_include_directories(enh PUBLIC include PRIVATE core/src)
target_link_libraries(enh PRIVATE ncnn)
target_compile_options(enh PRIVATE -Wall -Wextra -fvisibility=hidden)
target_compile_definitions(enh PRIVATE ENH_BUILDING ENH_VERSION_STRING="${PROJECT_VERSION}")
if(ANDROID)
  # 16 KB page size (Android 15+ devices) and no shared libomp.so in the APK.
  target_link_options(enh PRIVATE "-Wl,-z,max-page-size=16384" -static-openmp)
  target_link_libraries(enh PRIVATE log)
endif()

if(ENH_BUILD_TESTS)
  enable_testing()
  add_executable(test_abi tests/test_abi.cpp)
  target_link_libraries(test_abi PRIVATE enh)
  add_test(NAME abi COMMAND test_abi)
endif()
