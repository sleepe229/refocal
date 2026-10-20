// SPDX-License-Identifier: Apache-2.0
#include <cstdio>
#include <vector>

#include "image/encode.hpp"
#include "util/error.hpp"
#include "util/size.hpp"

namespace enh {

struct RgbaWriter::Impl {
  std::FILE* f = nullptr;
  int w = 0, h = 0, y = 0;
  std::vector<uint8_t> row;
};

RgbaWriter::RgbaWriter(const std::string& path, int w, int h) : impl_(std::make_unique<Impl>()) {
  impl_->w = w;
  impl_->h = h;
  impl_->row.resize(sz(w) * 4);
  impl_->f = std::fopen(path.c_str(), "wb");
  if (!impl_->f) fail(ENH_E_IO, "cannot create output");
}

RgbaWriter::~RgbaWriter() {
  if (impl_->f) std::fclose(impl_->f);
}

void RgbaWriter::write_rows(const uint8_t* rgb, int rows) {
  Impl& m = *impl_;
  if (m.y + rows > m.h) fail(ENH_E_INTERNAL, "too many rows");
  for (int r = 0; r < rows; ++r, ++m.y) {
    const uint8_t* s = rgb + sz(r) * sz(m.w) * 3;
    for (int x = 0; x < m.w; ++x) {
      m.row[sz(x) * 4] = s[x * 3];
      m.row[sz(x) * 4 + 1] = s[x * 3 + 1];
      m.row[sz(x) * 4 + 2] = s[x * 3 + 2];
      m.row[sz(x) * 4 + 3] = 255;
    }
    if (std::fwrite(m.row.data(), 1, m.row.size(), m.f) != m.row.size()) {
      fail(ENH_E_DISK_FULL, "cannot write output");
    }
  }
}

void RgbaWriter::finish() {
  Impl& m = *impl_;
  if (m.y != m.h) fail(ENH_E_INTERNAL, "missing rows");
  const bool ok = std::fclose(m.f) == 0;
  m.f = nullptr;
  if (!ok) fail(ENH_E_DISK_FULL, "cannot write output");
}

}  // namespace enh
