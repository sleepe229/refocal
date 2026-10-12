// Internal error type: thrown inside the core, converted to enh_status at the ABI boundary.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <stdexcept>
#include <string>

#include "enh.h"

namespace enh {

class Error : public std::runtime_error {
 public:
  Error(enh_status status, const std::string& msg) : std::runtime_error(msg), status_(status) {}
  enh_status status() const { return status_; }

 private:
  enh_status status_;
};

[[noreturn]] inline void fail(enh_status st, const std::string& msg) { throw Error(st, msg); }

}  // namespace enh
