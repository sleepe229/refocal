// Core log: logcat on Android, stderr elsewhere, and a rotating file for bug reports
// (FR-SET-007, PRIV-LOG-001/002). Paths and URIs are redacted before any sink sees a line.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>

namespace enh {

enum class LogLevel : uint8_t { debug, info, warn, error };

void log(LogLevel level, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void set_log_level(LogLevel min);
// File sink; rotates to path + ".1". Throws Error(ENH_E_IO) if the file cannot be opened.
void log_open(const std::string& path, int64_t max_bytes);
// Replaces absolute paths with "<path>" and scheme URIs (content://, file://, ...) with "<uri>".
std::string redact(const std::string& line);

}  // namespace enh

#define ENH_LOGD(...) ::enh::log(::enh::LogLevel::debug, __VA_ARGS__)
#define ENH_LOGI(...) ::enh::log(::enh::LogLevel::info, __VA_ARGS__)
#define ENH_LOGW(...) ::enh::log(::enh::LogLevel::warn, __VA_ARGS__)
#define ENH_LOGE(...) ::enh::log(::enh::LogLevel::error, __VA_ARGS__)
