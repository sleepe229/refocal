// Minimal JSON string writer. Every string leaving the core must be valid UTF-8 (enh.h, S6):
// invalid sequences are replaced with U+FFFD instead of being passed through.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

namespace enh {

// Length of the valid UTF-8 sequence at s[i], or 0 if invalid.
inline size_t utf8_seq_len(std::string_view s, size_t i) {
  auto b = [&](size_t k) { return static_cast<uint8_t>(s[k]); };
  auto cont = [&](size_t k) { return k < s.size() && (b(k) & 0xC0) == 0x80; };
  uint8_t c = b(i);
  if (c < 0x80) return 1;
  if (c >= 0xC2 && c <= 0xDF) return cont(i + 1) ? 2 : 0;
  if (c >= 0xE0 && c <= 0xEF) {
    if (!cont(i + 1) || !cont(i + 2)) return 0;
    uint8_t c1 = b(i + 1);
    if (c == 0xE0 && c1 < 0xA0) return 0;   // overlong
    if (c == 0xED && c1 >= 0xA0) return 0;  // surrogates
    return 3;
  }
  if (c >= 0xF0 && c <= 0xF4) {
    if (!cont(i + 1) || !cont(i + 2) || !cont(i + 3)) return 0;
    uint8_t c1 = b(i + 1);
    if (c == 0xF0 && c1 < 0x90) return 0;   // overlong
    if (c == 0xF4 && c1 >= 0x90) return 0;  // > U+10FFFF
    return 4;
  }
  return 0;
}

// Appends s as a quoted JSON string.
inline void json_str(std::string& out, std::string_view s) {
  out += '"';
  for (size_t i = 0; i < s.size();) {
    size_t n = utf8_seq_len(s, i);
    if (n == 0) {
      out += "\xEF\xBF\xBD";  // U+FFFD
      ++i;
      continue;
    }
    if (n == 1) {
      char c = s[i];
      switch (c) {
        case '"':
          out += "\\\"";
          break;
        case '\\':
          out += "\\\\";
          break;
        case '\n':
          out += "\\n";
          break;
        case '\r':
          out += "\\r";
          break;
        case '\t':
          out += "\\t";
          break;
        default:
          if (static_cast<uint8_t>(c) < 0x20) {
            static constexpr char kHex[] = "0123456789abcdef";
            const auto u = static_cast<uint8_t>(c);
            out += "\\u00";
            out += kHex[u >> 4];
            out += kHex[u & 0xF];
          } else {
            out += c;
          }
      }
    } else {
      out.append(s.data() + i, n);
    }
    i += n;
  }
  out += '"';
}

// Heap copy for out_json results; released by the caller with enh_free().
inline char* heap_copy(const std::string& s) {
  char* p = static_cast<char*>(std::malloc(s.size() + 1));
  if (p) std::memcpy(p, s.c_str(), s.size() + 1);
  return p;
}

}  // namespace enh
