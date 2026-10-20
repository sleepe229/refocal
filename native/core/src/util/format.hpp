// printf-style formatting into a std::string of the size it needs: no fixed buffer, nothing cut
// off, and the format checked against the arguments at compile time.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdarg>
#include <string>

namespace enh {

[[gnu::format(printf, 1, 2)]] std::string strf(const char* fmt, ...);
[[gnu::format(printf, 1, 0)]] std::string vstrf(const char* fmt, va_list ap);

}  // namespace enh
