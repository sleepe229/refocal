// TEST-SEC-005 (SEC-INP-005, ADR-0011): .rfpack archives through enh_rfpack_extract. The zips
// are built here byte by byte, so every header can lie: path traversal, symlinks, directories,
// zip bombs (ratio, total, overlapping entries), sizes and CRCs that do not match the data,
// ZIP64, encryption, duplicates, truncation.
// SPDX-License-Identifier: Apache-2.0
#include <zlib.h>

#include <cstring>
#include <string>
#include <vector>

#include "enh.h"
#include "mini_test.hpp"
#include "util/fs.hpp"

using namespace enh;
using Bytes = std::vector<uint8_t>;

static std::string g_work;

namespace {

void put16(Bytes& b, uint32_t v) {
  b.push_back(uint8_t(v));
  b.push_back(uint8_t(v >> 8));
}
void put32(Bytes& b, uint32_t v) {
  put16(b, v & 0xFFFF);
  put16(b, v >> 16);
}

Bytes deflate_raw(const Bytes& in) {
  z_stream z{};
  deflateInit2(&z, 9, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
  Bytes out(deflateBound(&z, uLong(in.size())));
  z.next_in = const_cast<uint8_t*>(in.data());
  z.avail_in = uInt(in.size());
  z.next_out = out.data();
  z.avail_out = uInt(out.size());
  deflate(&z, Z_FINISH);
  out.resize(z.total_out);
  deflateEnd(&z);
  return out;
}

uint32_t crc_of(const Bytes& b) { return uint32_t(crc32(0, b.data(), uInt(b.size()))); }

// One entry as it will be written; every field the directory states can be overridden.
struct Ent {
  std::string name;
  Bytes data;  // what is stored after the local header
  uint16_t method = 0;
  uint32_t crc = 0, size = 0;
  uint16_t made_by = 0x0314;  // Unix
  uint32_t ext_attr = 0100644u << 16;
  uint16_t flags = 0;
  int64_t point_at = -1;  // the directory points at another entry's local header
  int64_t packed = -1;    // the directory's packed size, if not data.size()

  static Ent stored(std::string n, const Bytes& d) {
    Ent e;
    e.name = std::move(n);
    e.data = d;
    e.crc = crc_of(d);
    e.size = uint32_t(d.size());
    return e;
  }
  static Ent deflated(std::string n, const Bytes& d) {
    Ent e = stored(std::move(n), d);
    e.method = 8;
    e.data = deflate_raw(d);
    return e;
  }
};

Bytes local_header(const Ent& e) {
  Bytes b;
  put32(b, 0x04034b50);
  put16(b, 20);
  put16(b, e.flags);
  put16(b, e.method);
  put32(b, 0);
  put32(b, e.crc);
  put32(b, uint32_t(e.data.size()));
  put32(b, e.size);
  put16(b, uint16_t(e.name.size()));
  put16(b, 0);
  b.insert(b.end(), e.name.begin(), e.name.end());
  return b;
}

Bytes build(const std::vector<Ent>& ents, uint32_t eocd_count = 0xFFFFFFFF) {
  Bytes z;
  std::vector<uint32_t> offs;
  for (const Ent& e : ents) {
    offs.push_back(uint32_t(z.size()));
    const Bytes h = local_header(e);
    z.insert(z.end(), h.begin(), h.end());
    z.insert(z.end(), e.data.begin(), e.data.end());
  }
  const uint32_t cd_off = uint32_t(z.size());
  for (size_t i = 0; i < ents.size(); ++i) {
    const Ent& e = ents[i];
    put32(z, 0x02014b50);
    put16(z, e.made_by);
    put16(z, 20);
    put16(z, e.flags);
    put16(z, e.method);
    put32(z, 0);
    put32(z, e.crc);
    put32(z, e.packed >= 0 ? uint32_t(e.packed) : uint32_t(e.data.size()));
    put32(z, e.size);
    put16(z, uint16_t(e.name.size()));
    put16(z, 0);
    put16(z, 0);
    put16(z, 0);
    put16(z, 0);
    put32(z, e.ext_attr);
    put32(z, e.point_at >= 0 ? uint32_t(e.point_at) : offs[i]);
    z.insert(z.end(), e.name.begin(), e.name.end());
  }
  const uint32_t cd_size = uint32_t(z.size()) - cd_off;
  const uint16_t n = eocd_count == 0xFFFFFFFF ? uint16_t(ents.size()) : uint16_t(eocd_count);
  put32(z, 0x06054b50);
  put16(z, 0);
  put16(z, 0);
  put16(z, n);
  put16(z, n);
  put32(z, cd_size);
  put32(z, cd_off);
  put16(z, 0);
  return z;
}

Bytes text(const std::string& s) { return Bytes(s.begin(), s.end()); }

int g_n = 0;
std::string write(const Bytes& z) {
  const std::string p = fs::join(g_work, "t" + std::to_string(g_n++) + ".rfpack");
  fs::write_atomic(p, z.data(), z.size(), false);
  return p;
}

enh_status extract(const Bytes& z, const std::string& entry, int64_t max = 1 << 30) {
  const std::string dst = fs::join(g_work, "out.bin");
  std::remove(dst.c_str());
  const enh_status st = enh_rfpack_extract(write(z).c_str(), entry.c_str(), dst.c_str(), max);
  // Nothing is left behind on failure, not even the .part file.
  if (st != ENH_OK) CHECK(!fs::exists(dst) && !fs::exists(dst + ".part"));
  return st;
}

}  // namespace

TEST("a valid pack: stored and deflated entries unpack exactly") {
  Bytes big(300000);
  for (size_t i = 0; i < big.size(); ++i) big[i] = uint8_t((i * 2654435761u) >> 13);
  const Bytes z = build(
      {Ent::stored("manifest.json", text("{\"schema\":1}")), Ent::deflated("model.ncnn.bin", big)});
  CHECK_EQ(extract(z, "manifest.json"), ENH_OK);
  CHECK(fs::read_text(fs::join(g_work, "out.bin")) == "{\"schema\":1}");
  CHECK_EQ(extract(z, "model.ncnn.bin"), ENH_OK);
  CHECK(fs::read_all(fs::join(g_work, "out.bin")) == big);
  CHECK_EQ(extract(z, "missing.bin"), ENH_E_INVALID);
  CHECK_EQ(extract(z, "model.ncnn.bin", 1000), ENH_E_LIMIT);  // the caller's limit
  CHECK(enh_rfpack_extract(nullptr, "a", "b", 1) == ENH_E_INVALID);
}

TEST("path traversal, absolute paths and directories are refused") {
  for (const char* bad : {"../evil", "a/b", "/etc/passwd", "..", ".", "a\\b", ""}) {
    const Bytes z = build({Ent::stored("ok.txt", text("x")), Ent::stored(bad, text("y"))});
    CHECK_EQ(extract(z, "ok.txt"), ENH_E_INVALID);  // the whole archive, not just that entry
  }
  Ent dir = Ent::stored("folder", {});
  dir.ext_attr = (040755u << 16) | 0x10;
  CHECK_EQ(extract(build({Ent::stored("ok.txt", text("x")), dir}), "ok.txt"), ENH_E_INVALID);
}

TEST("symlinks are refused") {
  Ent link = Ent::stored("model.ncnn.bin", text("/data/data/other/secret"));
  link.ext_attr = 0120777u << 16;
  CHECK_EQ(extract(build({link}), "model.ncnn.bin"), ENH_E_INVALID);
}

TEST("zip bombs: ratio, total size, overlapping entries") {
  const Bytes zeros(20 << 20, 0);  // deflates about 1000:1
  CHECK_EQ(extract(build({Ent::deflated("a.bin", zeros)}), "a.bin"), ENH_E_LIMIT);

  // Declared sizes adding up to more than 2 GB, each within the ratio (never inflated: the
  // directory alone is refused).
  std::vector<Ent> many;
  for (int i = 0; i < 3; ++i) {
    Ent e = Ent::stored("p" + std::to_string(i), Bytes(8 << 20, uint8_t(i)));
    e.method = 8;
    e.size = 750u << 20;  // 750 MB from 8 MB: ratio 94
    many.push_back(e);
  }
  CHECK_EQ(extract(build(many), "p0"), ENH_E_LIMIT);

  // b.bin's directory record points inside a.bin's data, at a local header hidden there: the
  // same bytes would be unpacked twice.
  const Ent b = Ent::stored("b.bin", text("payload"));
  Bytes inner = local_header(b);
  inner.insert(inner.end(), b.data.begin(), b.data.end());
  Ent ptr = b;
  ptr.data.clear();
  ptr.point_at = 30 + 5;  // a.bin's data starts after its 30 + 5 byte local header
  ptr.packed = int64_t(b.data.size());
  CHECK_EQ(extract(build({Ent::stored("a.bin", inner), ptr}), "a.bin"), ENH_E_INVALID);
}

TEST("data that does not match the directory") {
  Ent crc = Ent::stored("a.bin", text("hello"));
  crc.crc ^= 1;
  CHECK_EQ(extract(build({crc}), "a.bin"), ENH_E_INVALID);

  // Inflates to more than declared: stops at the declared size.
  Bytes d(5000, 'x');
  for (size_t i = 0; i < d.size(); i += 7) d[i] = uint8_t(i);
  Ent longer = Ent::deflated("b.bin", d);
  longer.size = 1000;
  longer.crc = crc_of(Bytes(d.begin(), d.begin() + 1000));
  CHECK_EQ(extract(build({longer}), "b.bin"), ENH_E_INVALID);

  Ent shorter = Ent::deflated("c.bin", d);
  shorter.size = 6000;
  CHECK_EQ(extract(build({shorter}), "c.bin"), ENH_E_INVALID);

  Ent stored = Ent::stored("d.bin", text("hello"));
  stored.size = 4;  // stored: packed and unpacked sizes must agree
  CHECK_EQ(extract(build({stored}), "d.bin"), ENH_E_INVALID);
}

TEST("ZIP64, encryption, duplicates, truncation, unsupported compression") {
  Ent z64 = Ent::stored("a.bin", text("x"));
  z64.size = 0xFFFFFFFF;
  CHECK(extract(build({z64}), "a.bin") != ENH_OK);

  Ent enc = Ent::stored("a.bin", text("x"));
  enc.flags = 1;
  CHECK_EQ(extract(build({enc}), "a.bin"), ENH_E_INVALID);

  CHECK_EQ(
      extract(build({Ent::stored("a.bin", text("1")), Ent::stored("a.bin", text("2"))}), "a.bin"),
      ENH_E_INVALID);

  Ent bz = Ent::stored("a.bin", text("x"));
  bz.method = 12;  // bzip2
  CHECK_EQ(extract(build({bz}), "a.bin"), ENH_E_INVALID);

  const Bytes ok = build({Ent::deflated("a.bin", Bytes(1000, 'q'))});
  for (size_t cut : {size_t(0), size_t(10), ok.size() / 2, ok.size() - 1}) {
    CHECK_EQ(extract(Bytes(ok.begin(), ok.begin() + long(cut)), "a.bin"), ENH_E_INVALID);
  }
  CHECK_EQ(extract(build({Ent::stored("a.bin", text("x"))}, 0), "a.bin"), ENH_E_INVALID);
  CHECK_EQ(extract(text("not a zip at all, just text"), "a.bin"), ENH_E_INVALID);
}

int main(int argc, char** argv) {
  g_work = argc > 1 ? argv[1] : "test-work-rfpack";
  fs::mkdirs(g_work);
  return mini::run_all();
}
