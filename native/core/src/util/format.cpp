// SPDX-License-Identifier: Apache-2.0
#include "util/format.hpp"

#include <cstdio>

#include "util/error.hpp"

namespace enh {

std::string vstrf(const char* fmt, va_list ap) {
  va_list measure;
  va_copy(measure, ap);
  const int n = std::vsnprintf(nullptr, 0, fmt, measure);
  va_end(measure);
  if (n < 0) fail(ENH_E_INTERNAL, "bad format");
  std::string s(static_cast<size_t>(n) + 1, '\0');
  if (std::vsnprintf(s.data(), s.size(), fmt, ap) != n) fail(ENH_E_INTERNAL, "bad format");
  s.resize(static_cast<size_t>(n));
  return s;
}

std::string strf(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  std::string s;
  try {
    s = vstrf(fmt, ap);
  } catch (...) {
    va_end(ap);
    throw;
  }
  va_end(ap);
  return s;
}

}  // namespace enh
