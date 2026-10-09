cmake_minimum_required(VERSION 3.20)
project(s2_streaming CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

set(DEPS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../_deps" CACHE PATH "Prebuilt spike dependencies")
set(ncnn_DIR "${DEPS_DIR}/ncnn-install/lib/cmake/ncnn" CACHE PATH "")
find_package(ncnn REQUIRED)
find_package(PNG REQUIRED)

add_library(jpeg_static STATIC IMPORTED)
set_target_properties(jpeg_static PROPERTIES
  IMPORTED_LOCATION "${DEPS_DIR}/jpeg-install/lib/libjpeg.a"
  INTERFACE_INCLUDE_DIRECTORIES "${DEPS_DIR}/jpeg-install/include")
add_library(lz4_static STATIC IMPORTED)
set_target_properties(lz4_static PROPERTIES
  IMPORTED_LOCATION "${DEPS_DIR}/lz4-install/lib/liblz4.a"
  INTERFACE_INCLUDE_DIRECTORIES "${DEPS_DIR}/lz4-install/include")

add_executable(s2_stream src/main.cpp)
target_compile_options(s2_stream PRIVATE -Wall -Wextra -O2)
target_compile_definitions(s2_stream PRIVATE
  S2_DEFAULT_MODEL="${CMAKE_CURRENT_SOURCE_DIR}/../_shared/models/sr_compact_dn050")
target_link_libraries(s2_stream PRIVATE ncnn jpeg_static lz4_static PNG::PNG)
