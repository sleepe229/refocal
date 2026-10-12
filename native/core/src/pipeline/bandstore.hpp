// On-disk BandStore (ADR-0004): jobs/<id>/bands/NNNN.raw (RGB8, uncompressed) committed with
// tmp -> fsync -> rename -> fsync(dir), then checkpoint.json. Resume continues after the last
// committed band (S2: byte-identical output after kill -9).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace enh {

struct Checkpoint {
  int band_idx = -1;  // last committed band
  int bands_total = 0;
  std::string recipe_hash;
  int out_w = 0, out_h = 0;
};

class BandStore {
 public:
  explicit BandStore(std::string job_dir, bool durable = true);
  const std::string& job_dir() const { return job_dir_; }
  std::string band_path(int i) const;
  std::string checkpoint_path() const;

  // Fresh job: removes old bands and checkpoint.
  void reset();
  void commit(int idx, const uint8_t* rgb, size_t bytes, const Checkpoint& ck);
  void read_band(int idx, std::vector<uint8_t>& out, size_t bytes) const;
  bool load_checkpoint(Checkpoint& ck) const;
  // Removes leftovers of bands after `last_committed` (partial writes before a kill).
  void discard_after(int last_committed, int bands_total) const;

 private:
  std::string job_dir_, bands_dir_;
  bool durable_;
};

std::string checkpoint_to_json(const Checkpoint& ck);
bool checkpoint_from_json(const std::string& js, Checkpoint& ck);

}  // namespace enh
