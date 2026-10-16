// Reader of .rfpack archives (ADR-0011, SEC-INP-005): a zip whose entries are flat file names,
// stored or deflated. The whole central directory is checked before any entry is read:
// names [A-Za-z0-9._-] only (no directories, no "..", no absolute paths), no symlinks, no
// encryption, no ZIP64, no duplicate names, no overlapping entry data, at most kZipMaxTotal
// bytes unpacked and kZipMaxRatio unpacked bytes per packed byte. Entries are inflated into a
// sink, never past the size the directory declares, and checked against their CRC-32.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace enh {

inline constexpr uint64_t kZipMaxTotal = uint64_t(2) << 30;  // 2 GB unpacked (SEC-INP-005)
inline constexpr uint64_t kZipMaxRatio = 100;
inline constexpr size_t kZipMaxEntries = 256;

// Bytes of an archive. read() throws Error(ENH_E_INVALID) past the end, ENH_E_IO on a failed
// read.
class ZipSource {
 public:
  virtual ~ZipSource() = default;
  virtual uint64_t size() const = 0;
  virtual void read(uint64_t offset, void* dst, size_t n) const = 0;
};

class FileZipSource : public ZipSource {
 public:
  explicit FileZipSource(const std::string& path);  // throws Error(ENH_E_IO)
  ~FileZipSource() override;
  FileZipSource(const FileZipSource&) = delete;
  FileZipSource& operator=(const FileZipSource&) = delete;
  uint64_t size() const override { return size_; }
  void read(uint64_t offset, void* dst, size_t n) const override;

 private:
  std::FILE* f_ = nullptr;
  uint64_t size_ = 0;
};

class MemoryZipSource : public ZipSource {
 public:
  MemoryZipSource(const uint8_t* data, size_t n) : data_(data), n_(n) {}
  uint64_t size() const override { return n_; }
  void read(uint64_t offset, void* dst, size_t n) const override;

 private:
  const uint8_t* data_;
  size_t n_;
};

struct ZipEntry {
  std::string name;
  uint16_t method = 0;  // 0 stored, 8 deflate
  uint32_t crc = 0;
  uint64_t packed = 0, size = 0, local_offset = 0;
};

// The checked central directory. Throws Error: ENH_E_INVALID (malformed or forbidden),
// ENH_E_LIMIT (unpacked size or ratio), ENH_E_IO.
std::vector<ZipEntry> zip_entries(const ZipSource& src);

// Unpacks [e] (from zip_entries of the same source) in chunks. Throws Error(ENH_E_INVALID)
// when the data does not match the directory (size, CRC, local header).
void zip_extract(const ZipSource& src, const ZipEntry& e,
                 const std::function<void(const uint8_t*, size_t)>& sink);

}  // namespace enh
