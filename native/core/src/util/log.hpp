// Core log: logcat on Android, stderr elsewhere. No photo paths or GPS in messages (ADR-0020).
// SPDX-License-Identifier: Apache-2.0
#pragma once

namespace enh {

enum class LogLevel { debug, info, warn, error };

void log(LogLevel level, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void set_log_level(LogLevel min);

}  // namespace enh

#define ENH_LOGD(...) ::enh::log(::enh::LogLevel::debug, __VA_ARGS__)
#define ENH_LOGI(...) ::enh::log(::enh::LogLevel::info, __VA_ARGS__)
#define ENH_LOGW(...) ::enh::log(::enh::LogLevel::warn, __VA_ARGS__)
#define ENH_LOGE(...) ::enh::log(::enh::LogLevel::error, __VA_ARGS__)
