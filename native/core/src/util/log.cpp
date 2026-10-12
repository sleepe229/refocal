// SPDX-License-Identifier: Apache-2.0
#include "util/log.hpp"

#include <atomic>
#include <cstdarg>
#include <cstdio>

#if defined(__ANDROID__)
#include <android/log.h>
#endif

namespace enh {
namespace {
std::atomic<int> g_min{static_cast<int>(LogLevel::info)};
}

void set_log_level(LogLevel min) { g_min = static_cast<int>(min); }

void log(LogLevel level, const char* fmt, ...) {
  if (static_cast<int>(level) < g_min.load(std::memory_order_relaxed)) return;
  char buf[1024];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
#if defined(__ANDROID__)
  static const int prio[] = {ANDROID_LOG_DEBUG, ANDROID_LOG_INFO, ANDROID_LOG_WARN,
                             ANDROID_LOG_ERROR};
  __android_log_write(prio[static_cast<int>(level)], "enh", buf);
#else
  static const char* tag[] = {"D", "I", "W", "E"};
  std::fprintf(stderr, "[enh %s] %s\n", tag[static_cast<int>(level)], buf);
#endif
}

}  // namespace enh
