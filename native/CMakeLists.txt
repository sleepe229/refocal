# Refocal native core: libenh (C ABI in include/enh.h).
# Consumers: packages/refocal_ffi (Android via AGP externalNativeBuild; iOS via xcframework),
# tools/refocal-cli and native tests (desktop).
cmake_minimum_required(VERSION 3.24)
# The app's pubspec.yaml is the single source of the version: x.y.z for project(), the full
# version without build metadata (e.g. 0.0.3-alpha.1) for enh_version() and xmp:CreatorTool.
cmake_path(SET ENH_PUBSPEC NORMALIZE ${CMAKE_CURRENT_SOURCE_DIR}/../app/pubspec.yaml)
file(STRINGS ${ENH_PUBSPEC} ENH_PUBSPEC_VERSION REGEX "^version:")
if(NOT ENH_PUBSPEC_VERSION MATCHES "^version: *(([0-9]+\\.[0-9]+\\.[0-9]+)[^+ ]*)")
  message(FATAL_ERROR "no 'version: x.y.z[-pre][+build]' line in ${ENH_PUBSPEC}")
endif()
set(ENH_VERSION ${CMAKE_MATCH_1})
project(refocal_native VERSION ${CMAKE_MATCH_2} LANGUAGES C CXX)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${ENH_PUBSPEC})
find_package(Threads REQUIRED)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(ENH_VULKAN "ncnn Vulkan backend" ${ANDROID})
option(ENH_BUILD_TESTS "native tests (desktop)" OFF)
# x86 builds of ncnn compile every layer for SSE/AVX/FMA/AVX2/AVX512 and pick at runtime. Tests
# do not need that; CI turns it off (3-4x faster ncnn build). Keep ON for refocal-cli perf runs.
option(ENH_NCNN_RUNTIME_CPU "ncnn runtime CPU dispatch (x86)" ON)
set(ENH_SANITIZE "" CACHE STRING "address (ASan+UBSan) | thread | empty")
# libFuzzer targets (tests/fuzz, 11 §1); clang with ENH_SANITIZE=address. Coverage
# instrumentation goes into everything, the decoders of the vendored libraries included.
option(ENH_BUILD_FUZZ "libFuzzer targets (clang, ENH_SANITIZE=address)" OFF)
if(ENH_BUILD_FUZZ)
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR NOT ENH_SANITIZE STREQUAL "address")
    message(FATAL_ERROR "ENH_BUILD_FUZZ needs clang and ENH_SANITIZE=address")
  endif()
  add_compile_options(-fsanitize=fuzzer-no-link)
endif()

if(ENH_SANITIZE STREQUAL "address")
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=address,undefined)
elseif(ENH_SANITIZE STREQUAL "thread")
  add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
  add_link_options(-fsanitize=thread)
endif()

# Hidden by default; the C ABI is exported by the visibility pragma in include/enh.h.
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

# Reproducible builds (S8): no absolute source/build paths in objects or debug info.
add_compile_options(
  "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=."
  "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build")

# Options of the vendored projects below are set as normal variables, so changing an ENH_*
# option reconfigures them. ncnn's cmake_minimum_required(...3.10) leaves CMP0077 unset, and
# option() would ignore normal variables without it. A -D on the command line still wins.
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
function(enh_set_default var value)
  if(NOT DEFINED CACHE{${var}})
    set(${var} ${value} PARENT_SCOPE)
  endif()
endfunction()

# ---- ncnn (git submodule, BSD-3-Clause) ----
enh_set_default(NCNN_VULKAN ${ENH_VULKAN})
enh_set_default(NCNN_SHARED_LIB OFF)
enh_set_default(NCNN_INSTALL_SDK OFF)
enh_set_default(NCNN_BUILD_TOOLS OFF)
enh_set_default(NCNN_BUILD_EXAMPLES OFF)
enh_set_default(NCNN_BUILD_BENCHMARK OFF)
enh_set_default(NCNN_BUILD_TESTS OFF)
enh_set_default(NCNN_PYTHON OFF)
enh_set_default(NCNN_PIXEL_DRAWING OFF)
if(NOT ENH_NCNN_RUNTIME_CPU)
  enh_set_default(NCNN_RUNTIME_CPU OFF)
  enh_set_default(NCNN_AVX512 OFF)
  enh_set_default(NCNN_AVX512VNNI OFF)
  enh_set_default(NCNN_AVXVNNI OFF)
  enh_set_default(NCNN_AVX2 OFF)
  enh_set_default(NCNN_AVX OFF)
  enh_set_default(NCNN_FMA OFF)
  enh_set_default(NCNN_F16C OFF)
  enh_set_default(NCNN_XOP OFF)
endif()
# Size (APK budget 30 MB, 0.1): models run fp16/fp32 (S1/S3), no int8/bf16 kernels.
enh_set_default(NCNN_INT8 OFF)
enh_set_default(NCNN_BF16 OFF)
# ncnn defaults to -fno-exceptions/-fno-rtti on Android/iOS and exports them PUBLIC; the core
# uses exceptions internally (converted to enh_status at the ABI boundary).
enh_set_default(NCNN_DISABLE_EXCEPTION OFF)
enh_set_default(NCNN_DISABLE_RTTI OFF)
if(ENH_SANITIZE STREQUAL "thread" OR ENH_SANITIZE STREQUAL "address")
  # OpenMP runtimes are not TSan-instrumented, and libomp's thread pool is never freed at exit
  # (LeakSanitizer false positives). Sanitizer builds run ncnn single-threaded.
  enh_set_default(NCNN_OPENMP OFF)
  enh_set_default(NCNN_SIMPLEOMP OFF)
elseif(ANDROID)
  # Statically linked libomp added ~0.8 MB to stripped libenh.so. simpleomp implements
  # the LLVM OpenMP ABI ncnn's kernels emit (#pragma omp parallel for num_threads)
  # and keeps CPU inference multithreaded, without shipping libomp in the APK.
  enh_set_default(NCNN_SIMPLEOMP ON)
elseif(NOT ANDROID AND NOT IOS)
  find_package(OpenMP)
  if(NOT OpenMP_CXX_FOUND)
    message(WARNING "OpenMP not found: ncnn CPU inference will be single-threaded "
                    "(install libomp-dev for clang, or build with gcc)")
  endif()
endif()
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn/CMakeLists.txt")
  message(FATAL_ERROR "ncnn submodule missing: git submodule update --init --recursive")
endif()
if(ANDROID AND NCNN_SIMPLEOMP AND NOT TARGET pthread)
  # simpleomp makes ncnn link "pthread"; Bionic has pthreads in libc and the NDK ships no
  # libpthread. A target of that name takes precedence over -lpthread and adds nothing.
  add_library(pthread INTERFACE)
endif()
add_subdirectory(third_party/ncnn EXCLUDE_FROM_ALL)

# ---- libjpeg-turbo (git submodule, IJG/BSD-3/zlib) ----
# Built as an external project: it does not support add_subdirectory(). The toolchain is
# forwarded so the same code path works for the host, the NDK and Xcode.
include(ExternalProject)
set(JPEG_PREFIX ${CMAKE_BINARY_DIR}/libjpeg-turbo)
set(JPEG_LIB ${JPEG_PREFIX}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX})
set(JPEG_C_FLAGS "${CMAKE_C_FLAGS} -ffile-prefix-map=${CMAKE_SOURCE_DIR}=. -ffile-prefix-map=${CMAKE_BINARY_DIR}=build")
if(ENH_SANITIZE STREQUAL "address")
  string(APPEND JPEG_C_FLAGS " -fsanitize=address,undefined -fno-omit-frame-pointer")
endif()
if(ENH_BUILD_FUZZ)
  string(APPEND JPEG_C_FLAGS " -fsanitize=fuzzer-no-link")
endif()
set(JPEG_CMAKE_ARGS
  -DCMAKE_INSTALL_PREFIX=${JPEG_PREFIX}
  -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
  "-DCMAKE_C_FLAGS=${JPEG_C_FLAGS}"
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF
  -DREQUIRE_SIMD=OFF
  -DBUILD=0)  # default is today's date, which breaks reproducible builds (S8)
if(CMAKE_TOOLCHAIN_FILE)
  list(APPEND JPEG_CMAKE_ARGS -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
endif()
set(JPEG_FORWARD ANDROID_ABI ANDROID_PLATFORM ANDROID_STL ANDROID_NDK CMAKE_OSX_ARCHITECTURES
    CMAKE_OSX_DEPLOYMENT_TARGET CMAKE_MAKE_PROGRAM CMAKE_C_COMPILER_LAUNCHER)
if(CMAKE_CROSSCOMPILING)
  list(APPEND JPEG_FORWARD CMAKE_SYSTEM_NAME CMAKE_SYSTEM_PROCESSOR)
endif()
foreach(v ${JPEG_FORWARD})
  if(DEFINED ${v})
    list(APPEND JPEG_CMAKE_ARGS -D${v}=${${v}})
  endif()
endforeach()
ExternalProject_Add(libjpeg_turbo_ext
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libjpeg-turbo
  BINARY_DIR ${CMAKE_BINARY_DIR}/libjpeg-turbo-build
  CMAKE_ARGS ${JPEG_CMAKE_ARGS}
  BUILD_BYPRODUCTS ${JPEG_LIB}
  UPDATE_COMMAND "" PATCH_COMMAND "")
file(MAKE_DIRECTORY ${JPEG_PREFIX}/include)
add_library(jpeg_static STATIC IMPORTED)
set_target_properties(jpeg_static PROPERTIES IMPORTED_LOCATION ${JPEG_LIB}
  INTERFACE_INCLUDE_DIRECTORIES ${JPEG_PREFIX}/include)
add_dependencies(jpeg_static libjpeg_turbo_ext)

# ---- libpng, libwebp (git submodules; libpng license, BSD-3) ----
# zlib is the platform's (NDK, iOS SDK, host): not bundled.
find_package(ZLIB REQUIRED)
enh_set_default(PNG_SHARED OFF)
enh_set_default(PNG_STATIC ON)
enh_set_default(PNG_TESTS OFF)
enh_set_default(PNG_TOOLS OFF)
enh_set_default(PNG_FRAMEWORK OFF)
enh_set_default(SKIP_INSTALL_ALL ON)
add_subdirectory(third_party/libpng EXCLUDE_FROM_ALL)
# Library only: encoder, demux (input metadata), mux (output metadata, FR-EXP-001).
foreach(o ANIM_UTILS CWEBP DWEBP GIF2WEBP IMG2WEBP VWEBP WEBPINFO WEBPMUX EXTRAS)
  enh_set_default(WEBP_BUILD_${o} OFF)
endforeach()
add_subdirectory(third_party/libwebp EXCLUDE_FROM_ALL)

# ---- libenh ----
set(ENH_SOURCES
  core/src/enh.cpp
  core/src/probe.cpp
  core/src/util/fs.cpp
  core/src/util/log.cpp
  core/src/image/decode.cpp
  core/src/image/jpeg.cpp
  core/src/image/png.cpp
  core/src/image/platform_decode.cpp
  core/src/image/webp.cpp
  core/src/image/metaio.cpp
  core/src/image/ops.cpp
  core/src/pipeline/bandstore.cpp
  core/src/pipeline/geometry.cpp
  core/src/backend/ncnn_backend.cpp
  core/src/job/events.cpp
  core/src/job/job.cpp
  core/src/job/export.cpp
  core/src/policy/blocklist.cpp
  core/src/policy/builtin_blocklist.cpp
  core/src/policy/gpu_gate.cpp
  core/src/policy/gpu_identity.cpp
  core/src/policy/sentinel.cpp
  core/src/policy/tier.cpp)
# Dart API DL (BSD-3-Clause, from the Dart SDK; copied to third_party/dart_api_dl) — event ports.
set(DART_DL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/dart_api_dl)
list(APPEND ENH_SOURCES ${DART_DL_DIR}/dart_api_dl.c)

add_library(enh_core STATIC ${ENH_SOURCES})
target_include_directories(enh_core PUBLIC include core/src
  PRIVATE ${DART_DL_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/third_party/json/single_include)
target_link_libraries(enh_core PUBLIC ncnn jpeg_static png_static webpdemux libwebpmux ZLIB::ZLIB
  Threads::Threads)
set_source_files_properties(${DART_DL_DIR}/dart_api_dl.c PROPERTIES COMPILE_OPTIONS "-w")
target_compile_options(enh_core PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra>)
target_compile_definitions(enh_core PRIVATE ENH_BUILDING ENH_VERSION_STRING="${ENH_VERSION}")
if(ANDROID)
  target_link_libraries(enh_core PUBLIC log)
endif()
if(ENH_BUILD_TESTS OR ENH_BUILD_CLI)
  target_compile_definitions(enh_core PRIVATE ENH_FAULT_INJECTION)  # never in app builds
endif()

add_library(enh SHARED core/src/enh_export_anchor.cpp)
target_link_libraries(enh PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,enh_core>")
target_include_directories(enh PUBLIC include)
if(ANDROID)
  # 16 KB page size (Android 15+). CPU threads come from ncnn simpleomp, not libomp.
  target_link_options(enh PRIVATE "-Wl,-z,max-page-size=16384"
                     -Wl,--gc-sections -Wl,--icf=all)
endif()

# ---- refocal-cli (desktop: golden tests, perf, bug repro) ----
option(ENH_BUILD_CLI "tools/refocal-cli" OFF)
if(ENH_BUILD_CLI AND NOT ANDROID AND NOT IOS)
  add_executable(refocal-cli ${CMAKE_CURRENT_SOURCE_DIR}/../tools/refocal-cli/main.cpp)
  target_link_libraries(refocal-cli PRIVATE enh_core)
  target_include_directories(refocal-cli PRIVATE third_party/json/single_include)
endif()

if(ENH_BUILD_TESTS)
  enable_testing()
  add_executable(test_abi tests/test_abi.cpp)
  target_link_libraries(test_abi PRIVATE enh)
  target_include_directories(test_abi PRIVATE core/src)
  add_test(NAME abi COMMAND test_abi)
  add_executable(test_pipeline tests/test_pipeline.cpp)
  target_link_libraries(test_pipeline PRIVATE enh_core)
  target_include_directories(test_pipeline PRIVATE third_party/json/single_include)
  add_test(NAME pipeline COMMAND test_pipeline ${CMAKE_CURRENT_BINARY_DIR}/test-work)
  add_executable(test_job tests/test_job.cpp)
  target_link_libraries(test_job PRIVATE enh_core)
  target_include_directories(test_job PRIVATE core/src third_party/json/single_include)
  add_test(NAME job COMMAND test_job ${CMAKE_CURRENT_BINARY_DIR}/test-work-job)
  add_executable(test_codecs tests/test_codecs.cpp)
  target_link_libraries(test_codecs PRIVATE enh_core)
  add_test(NAME codecs COMMAND test_codecs ${CMAKE_CURRENT_BINARY_DIR}/test-work-codecs)
  foreach(t blocklist sentinel log)
    add_executable(test_${t} tests/test_${t}.cpp)
    target_link_libraries(test_${t} PRIVATE enh_core)
    add_test(NAME ${t} COMMAND test_${t})
  endforeach()
endif()

if(ENH_BUILD_FUZZ)
  foreach(t metaio decode)
    add_executable(fuzz_${t} tests/fuzz/fuzz_${t}.cpp)
    target_link_libraries(fuzz_${t} PRIVATE enh_core)
    target_link_options(fuzz_${t} PRIVATE -fsanitize=fuzzer)
  endforeach()
endif()
