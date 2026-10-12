// SPDX-License-Identifier: Apache-2.0
#include "pipeline/bandstore.hpp"

#include <unistd.h>

#include <cstdio>
#include <nlohmann/json.hpp>

#include "util/error.hpp"
#include "util/fs.hpp"

namespace enh {

BandStore::BandStore(std::string job_dir, bool durable)
    : job_dir_(std::move(job_dir)), bands_dir_(fs::join(job_dir_, "bands")), durable_(durable) {}

std::string BandStore::band_path(int i) const {
  char b[24];
  std::snprintf(b, sizeof b, "%04d.raw", i);
  return fs::join(bands_dir_, b);
}

std::string BandStore::checkpoint_path() const { return fs::join(job_dir_, "checkpoint.json"); }

void BandStore::reset() {
  fs::remove_tree(bands_dir_);
  ::unlink(checkpoint_path().c_str());
  fs::mkdirs(bands_dir_);
}

void BandStore::commit(int idx, const uint8_t* rgb, size_t bytes, const Checkpoint& ck) {
  fs::write_atomic(band_path(idx), rgb, bytes, durable_);
  Checkpoint c = ck;
  c.band_idx = idx;
  fs::write_atomic(checkpoint_path(), checkpoint_to_json(c), durable_);
}

void BandStore::read_band(int idx, std::vector<uint8_t>& out, size_t bytes) const {
  std::string p = band_path(idx);
  if (fs::file_size(p) != int64_t(bytes)) fail(ENH_E_IO, "band size mismatch");
  out.resize(bytes);
  fs::read_exact(p, out.data(), bytes);
}

bool BandStore::load_checkpoint(Checkpoint& ck) const {
  if (!fs::exists(checkpoint_path())) return false;
  return checkpoint_from_json(fs::read_text(checkpoint_path()), ck);
}

void BandStore::discard_after(int last, int total) const {
  for (int b = last + 1; b < total; ++b) {
    ::unlink(band_path(b).c_str());
    ::unlink((band_path(b) + ".tmp").c_str());
  }
}

std::string checkpoint_to_json(const Checkpoint& ck) {
  nlohmann::json j = {{"version", 1},           {"band_idx", ck.band_idx},
                      {"bands_total", ck.bands_total}, {"recipe_hash", ck.recipe_hash},
                      {"out_w", ck.out_w},      {"out_h", ck.out_h}};
  return j.dump(2) + "\n";
}

bool checkpoint_from_json(const std::string& js, Checkpoint& ck) {
  auto j = nlohmann::json::parse(js, nullptr, false);
  if (j.is_discarded() || j.value("version", 0) != 1) return false;
  ck.band_idx = j.value("band_idx", -1);
  ck.bands_total = j.value("bands_total", 0);
  ck.recipe_hash = j.value("recipe_hash", "");
  ck.out_w = j.value("out_w", 0);
  ck.out_h = j.value("out_h", 0);
  return true;
}

}  // namespace enh
