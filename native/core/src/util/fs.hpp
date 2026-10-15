// File helpers with the durability rules of the BandStore (ADR-0004): tmp -> fsync -> rename ->
// fsync(dir). All functions throw enh::Error (ENH_E_IO / ENH_E_DISK_FULL).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace enh::fs {

bool exists(const std::string& path);
int64_t file_size(const std::string& path);  // -1 if missing
void mkdirs(const std::string& path);
void remove_tree(const std::string& path);  // best effort
void fsync_dir(const std::string& dir);
// Atomic replace: data lands at `path` completely or not at all.
void write_atomic(const std::string& path, const void* data, size_t n, bool durable = true);
void write_atomic(const std::string& path, const std::string& s, bool durable = true);
std::vector<uint8_t> read_all(const std::string& path);
std::string read_text(const std::string& path);
// Reads exactly n bytes from the start of the file into dst.
void read_exact(const std::string& path, void* dst, size_t n);
int64_t free_bytes(const std::string& dir);  // -1 if unknown
std::string join(const std::string& a, const std::string& b);

}  // namespace enh::fs
