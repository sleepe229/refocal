// File integrity (ADR-0011, ADR-0021, SEC-SUP-*): SHA-256 of downloaded model files and
// minisign (Ed25519) signatures of the model manifest. Monocypher provides Ed25519 and BLAKE2b.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace enh {

// Throws Error: ENH_E_INVALID (bad hex), ENH_E_IO (unreadable), ENH_E_SIGNATURE (mismatch).
void verify_file_sha256(const std::string& path, const std::string& sha256_hex);

// A minisign public key: the second line of a .pub file, base64 of "Ed" + key id + key.
struct MinisignKey {
  uint8_t id[8];
  uint8_t key[32];
};
// Throws Error(ENH_E_INVALID) for anything else.
MinisignKey parse_minisign_key(const std::string& base64);

// Verifies the minisign signature file [sig] (as `minisign -S` writes it: "Ed" pure or "ED"
// BLAKE2b-512 prehashed, plus the global signature over the trusted comment) of [msg_path]
// with the key of matching id among [keys]. Returns the trusted comment. Throws
// Error(ENH_E_SIGNATURE) when no key matches or a signature is wrong, ENH_E_INVALID for a
// malformed signature file, ENH_E_IO when a file cannot be read. A pure ("Ed") signature reads
// the whole message, so it is accepted only up to kMaxPureSignedBytes.
std::string verify_minisign(const std::string& msg_path, const std::string& sig,
                            const std::vector<MinisignKey>& keys);

inline constexpr int64_t kMaxPureSignedBytes = int64_t(16) << 20;

std::vector<uint8_t> base64_decode(const std::string& s);  // throws Error(ENH_E_INVALID)

}  // namespace enh
