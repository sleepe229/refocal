// SPDX-License-Identifier: Apache-2.0
#include "util/zip.hpp"

#include <zlib.h>

#include <algorithm>
#include <cstring>
#include <set>

#include "util/error.hpp"

namespace enh {
namespace {

constexpr uint32_t kEocdSig = 0x06054b50, kCdSig = 0x02014b50, kLocalSig = 0x04034b50;
constexpr size_t kEocdSize = 22, kCdSize = 46, kLocalSize = 30;
constexpr uint64_t kMaxCdBytes = 1 << 20;
constexpr size_t kMaxName = 128;
constexpr size_t kChunk = 1 << 16;

uint16_t u16(const uint8_t* p) { return uint16_t(p[0] | p[1] << 8); }
uint32_t u32(const uint8_t* p) {
  return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}

[[noreturn]] void bad(const std::string& what) { fail(ENH_E_INVALID, "rfpack: " + what); }

bool valid_name(const std::string& n) {
  if (n.empty() || n.size() > kMaxName || n == "." || n == "..") return false;
  return std::all_of(n.begin(), n.end(), [](char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' ||
           c == '_' || c == '-';
  });
}

}  // namespace

FileZipSource::FileZipSource(const std::string& path) {
  f_ = std::fopen(path.c_str(), "rb");
  if (!f_) fail(ENH_E_IO, "cannot open rfpack");
  if (fseeko(f_, 0, SEEK_END) != 0) {
    std::fclose(f_);
    fail(ENH_E_IO, "cannot read rfpack");
  }
  size_ = uint64_t(ftello(f_));
}

FileZipSource::~FileZipSource() { std::fclose(f_); }

void FileZipSource::read(uint64_t offset, void* dst, size_t n) const {
  if (offset > size_ || n > size_ - offset) bad("truncated");
  if (n == 0) return;  // dst may be null (an empty buffer)
  if (fseeko(f_, off_t(offset), SEEK_SET) != 0 || std::fread(dst, 1, n, f_) != n)
    fail(ENH_E_IO, "cannot read rfpack");
}

void MemoryZipSource::read(uint64_t offset, void* dst, size_t n) const {
  if (offset > n_ || n > n_ - offset) bad("truncated");
  if (n == 0) return;  // memcpy with a null pointer is undefined even for 0 bytes
  std::memcpy(dst, data_ + offset, n);
}

std::vector<ZipEntry> zip_entries(const ZipSource& src) {
  const uint64_t size = src.size();
  if (size < kEocdSize) bad("not a zip");
  // End of central directory: the last record, its comment running to the end of the file.
  const uint64_t tail_n = std::min<uint64_t>(size, kEocdSize + 0xFFFF);
  std::vector<uint8_t> tail(tail_n);
  src.read(size - tail_n, tail.data(), tail_n);
  const uint8_t* eocd = nullptr;
  for (size_t i = tail_n - kEocdSize + 1; i-- > 0;) {
    if (u32(&tail[i]) == kEocdSig && u16(&tail[i + 20]) == tail_n - i - kEocdSize) {
      eocd = &tail[i];
      break;
    }
  }
  if (!eocd) bad("no end of central directory");
  const uint64_t eocd_pos = size - tail_n + uint64_t(eocd - tail.data());
  const uint16_t disk = u16(eocd + 4), cd_disk = u16(eocd + 6);
  const uint16_t here = u16(eocd + 8), count = u16(eocd + 10);
  const uint32_t cd_size = u32(eocd + 12), cd_off = u32(eocd + 16);
  if (here == 0xFFFF || count == 0xFFFF || cd_size == 0xFFFFFFFF || cd_off == 0xFFFFFFFF)
    bad("ZIP64 is not supported");
  if (disk != 0 || cd_disk != 0 || here != count) bad("multi-disk archive");
  if (count == 0 || count > kZipMaxEntries) bad("entry count");
  if (cd_size > kMaxCdBytes || uint64_t(cd_off) + cd_size > eocd_pos) bad("central directory");

  std::vector<uint8_t> cd(cd_size);
  src.read(cd_off, cd.data(), cd_size);
  std::vector<ZipEntry> out;
  std::set<std::string> names;
  uint64_t total = 0;
  struct Range {
    uint64_t begin, end;
  };
  std::vector<Range> ranges;
  size_t p = 0;
  for (uint16_t i = 0; i < count; ++i) {
    if (cd_size - p < kCdSize || u32(&cd[p]) != kCdSig) bad("central directory entry");
    const uint8_t* h = &cd[p];
    const uint16_t made_by = u16(h + 4), flags = u16(h + 8), method = u16(h + 10);
    const uint16_t nlen = u16(h + 28), elen = u16(h + 30), clen = u16(h + 32);
    const uint32_t ext_attr = u32(h + 38);
    ZipEntry e;
    e.method = method;
    e.crc = u32(h + 16);
    e.packed = u32(h + 20);
    e.size = u32(h + 24);
    const uint32_t local = u32(h + 42);
    if (cd_size - p - kCdSize < size_t(nlen) + elen + clen) bad("central directory entry");
    e.name.assign(reinterpret_cast<const char*>(h + kCdSize), nlen);
    p += kCdSize + nlen + elen + clen;

    if (!valid_name(e.name)) bad("forbidden entry name");
    if (!names.insert(e.name).second) bad("duplicate entry " + e.name);
    if (flags & 0x2041) bad("encrypted entry " + e.name);
    if (method != 0 && method != 8) bad("unsupported compression in " + e.name);
    if (e.packed == 0xFFFFFFFF || e.size == 0xFFFFFFFF || local == 0xFFFFFFFF)
      bad("ZIP64 is not supported");
    if (u16(h + 34) != 0) bad("multi-disk archive");
    // Unix file type in the high half of the external attributes: regular files only.
    const uint32_t type = (ext_attr >> 16) & 0xF000;
    if ((made_by >> 8) == 3 && type != 0 && type != 0x8000) bad("not a regular file: " + e.name);
    if (ext_attr & 0x10) bad("directory entry " + e.name);  // MS-DOS directory attribute
    if (method == 0 && e.packed != e.size) bad("stored size mismatch in " + e.name);
    total += e.size;
    if (total > kZipMaxTotal) fail(ENH_E_LIMIT, "rfpack: unpacked size over the limit");
    if (e.size > kZipMaxRatio * e.packed)
      fail(ENH_E_LIMIT, "rfpack: compression ratio of " + e.name);

    uint8_t lh[kLocalSize];
    src.read(local, lh, kLocalSize);
    const uint16_t lnlen = u16(lh + 26), lelen = u16(lh + 28);
    if (u32(lh) != kLocalSig || u16(lh + 8) != method || (u16(lh + 6) & 0x2041) || lnlen != nlen)
      bad("local header of " + e.name);
    std::string lname(lnlen, '\0');
    src.read(uint64_t(local) + kLocalSize, lname.data(), lnlen);
    if (lname != e.name) bad("local header of " + e.name);
    e.local_offset = uint64_t(local) + kLocalSize + lnlen + lelen;
    if (e.local_offset + e.packed > cd_off) bad("entry data past the central directory");
    ranges.push_back({local, e.local_offset + e.packed});
    out.push_back(std::move(e));
  }
  // Overlapping entries make a small archive unpack into much more (a "zip bomb").
  std::sort(ranges.begin(), ranges.end(),
            [](const Range& a, const Range& b) { return a.begin < b.begin; });
  for (size_t i = 1; i < ranges.size(); ++i)
    if (ranges[i].begin < ranges[i - 1].end) bad("overlapping entries");
  return out;
}

void zip_extract(const ZipSource& src, const ZipEntry& e,
                 const std::function<void(const uint8_t*, size_t)>& sink) {
  std::vector<uint8_t> in(kChunk), out(kChunk);
  uLong crc = crc32(0L, Z_NULL, 0);
  uint64_t read = 0, written = 0;
  if (e.method == 0) {
    while (read < e.packed) {
      const size_t n = size_t(std::min<uint64_t>(kChunk, e.packed - read));
      src.read(e.local_offset + read, in.data(), n);
      read += n;
      crc = crc32(crc, in.data(), uInt(n));
      sink(in.data(), n);
    }
    written = read;
  } else {
    z_stream z{};
    if (inflateInit2(&z, -MAX_WBITS) != Z_OK) fail(ENH_E_OOM, "inflate");
    struct Guard {
      z_stream& z;
      ~Guard() { inflateEnd(&z); }
    } guard{z};
    int st = Z_OK;
    while (st != Z_STREAM_END) {
      if (z.avail_in == 0) {
        if (read == e.packed) bad("truncated data in " + e.name);
        const size_t n = size_t(std::min<uint64_t>(kChunk, e.packed - read));
        src.read(e.local_offset + read, in.data(), n);
        read += n;
        z.next_in = in.data();
        z.avail_in = uInt(n);
      }
      z.next_out = out.data();
      z.avail_out = uInt(out.size());
      st = inflate(&z, Z_NO_FLUSH);
      // Z_BUF_ERROR with the input used up: only more input lets it go on.
      if (st != Z_OK && st != Z_STREAM_END && !(st == Z_BUF_ERROR && z.avail_in == 0))
        bad("corrupt data in " + e.name);
      const size_t n = out.size() - z.avail_out;
      written += n;
      if (written > e.size) bad("data longer than declared in " + e.name);
      crc = crc32(crc, out.data(), uInt(n));
      if (n) sink(out.data(), n);
    }
    if (z.avail_in != 0 || read != e.packed) bad("data after the end of " + e.name);
  }
  if (written != e.size) bad("data shorter than declared in " + e.name);
  if (uint32_t(crc) != e.crc) bad("CRC mismatch in " + e.name);
}

}  // namespace enh
