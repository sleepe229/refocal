// SPDX-License-Identifier: Apache-2.0
#include "util/log.hpp"

#include <atomic>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <ctime>
#include <mutex>

#if defined(__ANDROID__)
#include <android/log.h>
#endif

#include "util/error.hpp"
#include "util/format.hpp"

namespace enh {
namespace {

std::atomic<int> g_min{static_cast<int>(LogLevel::info)};

// The longest message kept: a log line, not a dump.
constexpr size_t kMaxLine = 1023;

struct FileSink {
  std::mutex mu;
  std::string path;
  FILE* f = nullptr;
  int64_t size = 0, max = 0;

  void write(const std::string& line) {
    std::lock_guard lk(mu);
    if (!f) return;
    if (size + int64_t(line.size()) > max) rotate();
    if (!f) return;
    // A log line that cannot be written is lost: there is nowhere to report it.
    (void)std::fwrite(line.data(), 1, line.size(), f);
    (void)std::fflush(f);  // the lines before a native crash are the useful ones
    size += int64_t(line.size());
  }

  void rotate() {          // under mu
    (void)std::fclose(f);  // flushed after every line
    const std::string old = path + ".1";
    // Best effort: without the rename the log starts over in the same file.
    (void)std::rename(path.c_str(), old.c_str());
    f = std::fopen(path.c_str(), "w");
    size = 0;
  }
};

FileSink& sink() {
  static FileSink s;
  return s;
}

bool is_delim(char c) {
  return std::isspace(static_cast<unsigned char>(c)) || c == '"' || c == '\'' || c == '(' ||
         c == ')' || c == ',' || c == ';' || c == '[' || c == ']' || c == '<' || c == '>';
}

const char* kTag[] = {"D", "I", "W", "E"};

}  // namespace

std::string redact(const std::string& in) {
  std::string out;
  out.reserve(in.size());
  size_t i = 0;
  while (i < in.size()) {
    const bool token_start = i == 0 || is_delim(in[i - 1]) || in[i - 1] == '=' || in[i - 1] == ':';
    if (token_start && std::isalpha(static_cast<unsigned char>(in[i]))) {
      // scheme://... ; http(s) stays (model download URLs carry no personal data)
      size_t j = i;
      while (j < in.size() && (std::isalnum(static_cast<unsigned char>(in[j])) || in[j] == '+' ||
                               in[j] == '-' || in[j] == '.')) {
        ++j;
      }
      if (in.compare(j, 3, "://") == 0) {
        const std::string scheme = in.substr(i, j - i);
        size_t e = j + 3;
        while (e < in.size() && !is_delim(in[e])) ++e;
        if (scheme == "http" || scheme == "https") {
          out.append(in, i, e - i);
        } else {
          out += "<uri>";
        }
        i = e;
        continue;
      }
    }
    if (token_start && in[i] == '/' && i + 1 < in.size() && !is_delim(in[i + 1]) &&
        in[i + 1] != '/') {
      size_t e = i + 1;
      const char quote = i > 0 && (in[i - 1] == '"' || in[i - 1] == '\'') ? in[i - 1] : 0;
      if (quote) {  // a quoted path may contain spaces: up to the closing quote
        while (e < in.size() && in[e] != quote) ++e;
      } else {
        while (e < in.size() && !is_delim(in[e])) ++e;
      }
      out += "<path>";
      i = e;
      continue;
    }
    out += in[i++];
  }
  return out;
}

void set_log_level(LogLevel min) { g_min = static_cast<int>(min); }

void log_open(const std::string& path, int64_t max_bytes) {
  if (max_bytes < 4096) fail(ENH_E_INVALID, "log size too small");
  FileSink& s = sink();
  std::lock_guard lk(s.mu);
  if (s.f) (void)std::fclose(s.f);  // flushed after every line
  s.f = std::fopen(path.c_str(), "a");
  if (!s.f) fail(ENH_E_IO, "cannot open the log file");
  s.path = path;
  s.max = max_bytes;
  const long end = std::fseek(s.f, 0, SEEK_END) == 0 ? std::ftell(s.f) : -1;
  if (end < 0) {
    (void)std::fclose(s.f);
    s.f = nullptr;
    fail(ENH_E_IO, "cannot open the log file");
  }
  s.size = end;
}

static void emit(int level, const char* msg) {
  const std::string line = redact(msg);
#if defined(__ANDROID__)
  static const int prio[] = {ANDROID_LOG_DEBUG, ANDROID_LOG_INFO, ANDROID_LOG_WARN,
                             ANDROID_LOG_ERROR};
  __android_log_write(prio[level], "enh", line.c_str());
#else
  (void)std::fprintf(stderr, "[enh %s] %s\n", kTag[level], line.c_str());
#endif
  char ts[32];
  const std::time_t now = std::time(nullptr);
  std::tm tm{};
  gmtime_r(&now, &tm);
  if (std::strftime(ts, sizeof ts, "%Y-%m-%dT%H:%M:%SZ", &tm) == 0) ts[0] = '\0';
  sink().write(std::string(ts) + " " + kTag[level] + " " + line + "\n");
}

void log(LogLevel level, const char* fmt, ...) {
  if (static_cast<int>(level) < g_min.load(std::memory_order_relaxed)) return;
  va_list ap;
  va_start(ap, fmt);
  std::string msg;
  try {
    msg = vstrf(fmt, ap);
  } catch (const Error&) {
    msg = std::string("bad log format: ") + fmt;
  }
  va_end(ap);
  if (msg.size() > kMaxLine) msg.resize(kMaxLine);
  emit(static_cast<int>(level), msg.c_str());
}

}  // namespace enh

extern "C" enh_status enh_log_open(const char* path, int64_t max_bytes) {
  if (!path) return ENH_E_INVALID;
  try {
    enh::log_open(path, max_bytes);
    return ENH_OK;
  } catch (const enh::Error& e) {
    return e.status();
  }
}

extern "C" void enh_log_write(int32_t level, const char* message) {
  if (!message || level < ENH_LOG_DEBUG || level > ENH_LOG_ERROR) return;
  if (level < enh::g_min.load(std::memory_order_relaxed)) return;
  enh::emit(level, message);
}

extern "C" void enh_log_set_level(int32_t min_level) {
  if (min_level >= ENH_LOG_DEBUG && min_level <= ENH_LOG_ERROR) enh::g_min = min_level;
}
