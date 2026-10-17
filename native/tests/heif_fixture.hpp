// A HEIF container as Android's HeifWriter lays it out (ftyp, meta, mdat; a grid primary item
// with hvc1 tiles), for test_heif and the HEIC export in test_job.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

namespace heif_fixture {

using Bytes = std::vector<uint8_t>;

struct W {
  Bytes b;
  void u(uint64_t v, int n) {
    for (int i = n - 1; i >= 0; --i) b.push_back(uint8_t(v >> (8 * i)));
  }
  void s(const std::string& x, bool nul = false) {
    b.insert(b.end(), x.begin(), x.end());
    if (nul) b.push_back(0);
  }
  void raw(const Bytes& x) { b.insert(b.end(), x.begin(), x.end()); }
};

inline Bytes box(const std::string& type, const Bytes& body) {
  W w;
  w.u(8 + body.size(), 4);
  w.s(type);
  w.raw(body);
  return w.b;
}
inline Bytes full(const std::string& type, int version, uint32_t flags, const Bytes& body) {
  W w;
  w.u(version, 1);
  w.u(flags, 3);
  w.raw(body);
  return box(type, w.b);
}
inline Bytes cat(std::initializer_list<Bytes> parts) {
  Bytes out;
  for (const auto& p : parts) out.insert(out.end(), p.begin(), p.end());
  return out;
}
inline Bytes infe(uint32_t id, const std::string& type, const std::string& mime = "") {
  W w;
  w.u(id, 2);
  w.u(0, 2);
  w.s(type);
  w.s("", true);
  if (!mime.empty()) w.s(mime, true);
  return full("infe", 2, 0, w.b);
}

// A HeifWriter-like file: grid item 1 with tiles 2 and 3 (hvc1), tile data in mdat after meta,
// an nclx colr and, if [with_moov], a trailing moov box. [extra_infe]/[extra_loc] add an item.
inline Bytes make_heif(const Bytes& tile2, const Bytes& tile3, bool with_moov = false) {
  auto build = [&](uint32_t mdat_at) {
    W iloc;  // version 0: offset 4, length 4, base 0
    iloc.u(0x44, 1);
    iloc.u(0x00, 1);
    iloc.u(2, 2);
    for (uint32_t id : {2u, 3u}) {
      const Bytes& t = id == 2 ? tile2 : tile3;
      iloc.u(id, 2);
      iloc.u(0, 2);  // data_reference_index
      iloc.u(1, 2);  // extents
      iloc.u(mdat_at + 8 + (id == 3 ? tile2.size() : 0), 4);
      iloc.u(t.size(), 4);
    }
    W iinf;
    iinf.u(3, 2);
    const Bytes iinf_box =
        full("iinf", 0, 0, cat({iinf.b, infe(1, "grid"), infe(2, "hvc1"), infe(3, "hvc1")}));
    W dimg;
    dimg.u(1, 2);
    dimg.u(2, 2);
    dimg.u(2, 2);
    dimg.u(3, 2);
    const Bytes iref = full("iref", 0, 0, box("dimg", dimg.b));
    W nclx;
    nclx.s("nclx");
    nclx.u(1, 2);
    nclx.u(13, 2);
    nclx.u(6, 2);
    nclx.u(0x80, 1);
    W ispe;
    ispe.u(0, 4);
    ispe.u(512, 4);
    ispe.u(256, 4);
    const Bytes ipco = box(
        "ipco", cat({box("hvcC", Bytes(23, 1)), full("ispe", 0, 0, ispe.b), box("colr", nclx.b)}));
    W ipma;
    ipma.u(3, 4);
    for (uint32_t id : {1u, 2u, 3u}) {
      ipma.u(id, 2);
      if (id == 1) {
        ipma.u(2, 1);
        ipma.u(2, 1);  // ispe
        ipma.u(3, 1);  // colr nclx
      } else {
        ipma.u(1, 1);
        ipma.u(0x81, 1);  // hvcC, essential
      }
    }
    W hdlr;
    hdlr.u(0, 4);
    hdlr.s("pict");
    hdlr.raw(Bytes(12, 0));
    hdlr.s("", true);
    W pitm;
    pitm.u(1, 2);
    const Bytes meta = full(
        "meta", 0, 0,
        cat({full("hdlr", 0, 0, hdlr.b), full("pitm", 0, 0, pitm.b), full("iloc", 0, 0, iloc.b),
             iinf_box, iref, box("iprp", cat({ipco, full("ipma", 0, 0, ipma.b)}))}));
    W ftyp;
    ftyp.s("heic");
    ftyp.u(0, 4);
    ftyp.s("mif1heic");
    const Bytes head = cat({box("ftyp", ftyp.b), meta});
    Bytes file = cat({head, box("mdat", cat({tile2, tile3}))});
    if (with_moov) file = cat({file, box("moov", Bytes(8, 0))});
    return std::make_pair(head.size(), file);
  };
  auto [mdat_at, ignored] = build(0);
  return build(uint32_t(mdat_at)).second;
}

}  // namespace heif_fixture
