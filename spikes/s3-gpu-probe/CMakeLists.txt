cmake_minimum_required(VERSION 3.20)
project(refocal_s3_gpu_probe CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Header-only nlohmann/json (MIT), fetched by tools/fetch_deps.sh into third_party/ (gitignored).
set(NLOHMANN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party" CACHE PATH "dir containing nlohmann/json.hpp")
if(NOT EXISTS "${NLOHMANN_DIR}/nlohmann/json.hpp")
  message(FATAL_ERROR "nlohmann/json.hpp not found in ${NLOHMANN_DIR}; run tools/fetch_deps.sh")
endif()

# ncnn: desktop -> spikes/_deps/ncnn-install; Android -> prebuilt ncnn-<ver>-android-vulkan/arm64-v8a
if(NOT ncnn_DIR)
  if(ANDROID)
    message(FATAL_ERROR "set -Dncnn_DIR=<ncnn-android-vulkan>/${ANDROID_ABI}/lib/cmake/ncnn")
  endif()
  set(ncnn_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../_deps/ncnn-install/lib/cmake/ncnn")
endif()
if(ANDROID)
  add_link_options(-static-openmp)  # ncnn Android packages are built with OpenMP; avoid libomp.so
endif()
find_package(ncnn REQUIRED)

# Pure C++ part (no ncnn): blocklist, crash sentinel, tier rules. This is what moves to native core.
add_library(refocal_gpu_policy STATIC
  src/blocklist.cpp src/builtin_blocklist.cpp src/sentinel.cpp src/tier.cpp)
target_include_directories(refocal_gpu_policy PUBLIC ${NLOHMANN_DIR})
target_compile_options(refocal_gpu_policy PRIVATE -Wall -Wextra)

# ncnn-dependent part: device probe + correctness-checked microbenchmark
add_library(refocal_bench STATIC src/bench.cpp src/device_info.cpp)
target_include_directories(refocal_bench PUBLIC ${NLOHMANN_DIR})
target_link_libraries(refocal_bench PUBLIC ncnn)
target_compile_options(refocal_bench PRIVATE -Wall -Wextra)

add_executable(refocal-probe src/main.cpp)
target_link_libraries(refocal-probe PRIVATE refocal_gpu_policy refocal_bench)
get_filename_component(SPIKES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
if(NOT ANDROID)
  target_compile_definitions(refocal-probe PRIVATE REFOCAL_SPIKES_DIR="${SPIKES_DIR}")
endif()
if(ANDROID)
  # static libc++ so a single binary can be adb-pushed to /data/local/tmp
  target_link_options(refocal-probe PRIVATE -static-libstdc++)
endif()

enable_testing()
add_executable(test_blocklist tests/test_blocklist.cpp)
target_link_libraries(test_blocklist PRIVATE refocal_gpu_policy refocal_bench)
add_executable(test_sentinel tests/test_sentinel.cpp)
target_link_libraries(test_sentinel PRIVATE refocal_gpu_policy)
add_test(NAME blocklist COMMAND test_blocklist)
add_test(NAME sentinel COMMAND test_sentinel)
if(NOT ANDROID)
  add_test(NAME sentinel_crash_e2e
           COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/sentinel_crash_test.sh $<TARGET_FILE:refocal-probe>)
endif()
