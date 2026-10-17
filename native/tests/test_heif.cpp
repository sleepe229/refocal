// heif_meta (FR-EXP-002, ADR-0003 amendment): ICC, EXIF and XMP attached to a HEIF container as
// HeifWriter lays it out (ftyp, meta, mdat; a grid primary item with hvc1 tiles), read back, and
// the image data still found at its moved offsets.
// SPDX-License-Identifier: Apache-2.0
#include <algorithm>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

#include "heif_fixture.hpp"
#include "image/heif_meta.hpp"
#include "mini_test.hpp"
#include "util/error.hpp"

using namespace enh;
using namespace heif_fixture;

namespace {

const Bytes kTile2(100, 0xA2), kTile3(57, 0xB3);

OutputMeta sample_meta() {
  OutputMeta m;
  m.icc = Bytes(300, 0x11);
  m.exif = {'I', 'I', 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  m.xmp = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">ai</x:xmpmeta>";
  return m;
}

bool throws_invalid(const Bytes& b) {
  try {
    (void)heif_attach_meta(b, sample_meta());
  } catch (const Error& e) {
    return e.status() == ENH_E_INVALID;
  }
  return false;
}

}  // namespace

TEST("synthetic input reads back as written") {
  const Bytes in = make_heif(kTile2, kTile3);
  const auto info = heif_read_meta(in.data(), in.size());
  CHECK_EQ(info.primary, 1u);
  CHECK_EQ(info.items, size_t(2));
  CHECK(info.icc.empty() && info.exif_tiff.empty() && info.xmp.empty());
  CHECK(heif_item_data(in.data(), in.size(), 2) == kTile2);
  CHECK(heif_item_data(in.data(), in.size(), 3) == kTile3);
}

TEST("ICC, EXIF and XMP attached; tiles still resolve") {
  const Bytes in = make_heif(kTile2, kTile3);
  const OutputMeta m = sample_meta();
  const Bytes out = heif_attach_meta(in, m);
  const auto info = heif_read_meta(out.data(), out.size());
  CHECK_EQ(info.primary, 1u);
  CHECK(info.icc == m.icc);
  CHECK(info.exif_tiff == m.exif);
  CHECK_EQ(info.xmp, m.xmp);
  CHECK_EQ(info.items, size_t(4));
  CHECK_EQ(info.icc_items, (std::vector<uint32_t>{1, 2, 3}));
  CHECK(heif_item_data(out.data(), out.size(), 2) == kTile2);
  CHECK(heif_item_data(out.data(), out.size(), 3) == kTile3);
  // ftyp and mdat are copied as they were.
  CHECK(std::equal(in.begin(), in.begin() + 24, out.begin()));
  CHECK(std::equal(in.end() - 165, in.end(), out.end() - 165));
}

TEST("attaching again replaces, not duplicates") {
  const Bytes once = heif_attach_meta(make_heif(kTile2, kTile3), sample_meta());
  OutputMeta m2 = sample_meta();
  m2.icc = Bytes(200, 0x22);
  m2.xmp = "<x:xmpmeta>second</x:xmpmeta>";
  const Bytes twice = heif_attach_meta(once, m2);
  const auto info = heif_read_meta(twice.data(), twice.size());
  CHECK(info.icc == m2.icc);
  CHECK_EQ(info.xmp, m2.xmp);
  CHECK_EQ(info.items, size_t(4));  // 2 tiles + new Exif + new XMP
  CHECK_EQ(info.icc_items, (std::vector<uint32_t>{1, 2, 3}));
  CHECK(heif_item_data(twice.data(), twice.size(), 3) == kTile3);
}

TEST("only what is given is written") {
  OutputMeta m;
  m.xmp = "<x/>";
  const Bytes out = heif_attach_meta(make_heif(kTile2, kTile3), m);
  const auto info = heif_read_meta(out.data(), out.size());
  CHECK(info.icc.empty() && info.icc_items.empty() && info.exif_tiff.empty());
  CHECK_EQ(info.xmp, std::string("<x/>"));
  CHECK(heif_item_data(out.data(), out.size(), 2) == kTile2);
}

TEST("moov, truncation and garbage are refused, never crash") {
  CHECK(throws_invalid(make_heif(kTile2, kTile3, true)));
  CHECK(throws_invalid(Bytes{}));
  CHECK(throws_invalid(Bytes(64, 0xFF)));
  const Bytes in = make_heif(kTile2, kTile3);
  // A property box of size 0 ("to the end of ipco") would swallow the appended colr (fuzzer).
  Bytes zero = in;
  const Bytes nclx = {'c', 'o', 'l', 'r', 'n', 'c', 'l', 'x'};
  const auto at = std::search(zero.begin(), zero.end(), nclx.begin(), nclx.end()) - zero.begin();
  zero[at - 1] = 0;
  zero[at - 2] = 0;
  zero[at - 3] = 0;
  zero[at - 4] = 0;
  CHECK(throws_invalid(zero));
  // Every prefix that cuts the meta box is malformed.
  for (size_t n = 0; n < 24 + 8; ++n) CHECK(throws_invalid(Bytes(in.begin(), in.begin() + n)));
  for (size_t n = 32; n < in.size() - 165; n += 7) {
    try {
      (void)heif_attach_meta(Bytes(in.begin(), in.begin() + n), sample_meta());
    } catch (const Error&) {
    }
  }
}

// [seed_dir]: also writes the synthetic file before and after attaching (fuzz seed corpus).
int main(int argc, char** argv) {
  if (argc > 1) {
    const Bytes in = make_heif(kTile2, kTile3);
    const Bytes out = heif_attach_meta(in, sample_meta());
    for (const auto& [name, b] : {std::pair{"grid.heic", in}, std::pair{"grid-meta.heic", out}}) {
      if (FILE* f = std::fopen((std::string(argv[1]) + "/" + name).c_str(), "wb")) {
        std::fwrite(b.data(), 1, b.size(), f);
        std::fclose(f);
      }
    }
  }
  return mini::run_all();
}
