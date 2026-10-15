// SPDX-License-Identifier: Apache-2.0
#include "util/integrity.hpp"

#include <cctype>
#include <cstdio>
#include <cstring>
#include <memory>

#include "monocypher-ed25519.h"
#include "monocypher.h"
#include "util/error.hpp"
#include "util/sha256.hpp"

namespace enh {
namespace {

using File = std::unique_ptr<FILE, int (*)(FILE*)>;

File open(const std::string& path) {
  File f(std::fopen(path.c_str(), "rb"), &std::fclose);
  if (!f) fail(ENH_E_IO, "cannot open file");
  return f;
}

// Streams [path] into [sink] in 64 KiB blocks.
template <class Sink>
int64_t stream(const std::string& path, Sink&& sink) {
  File f = open(path);
  std::vector<uint8_t> buf(size_t(1) << 16);
  int64_t total = 0;
  for (;;) {
    const size_t n = std::fread(buf.data(), 1, buf.size(), f.get());
    if (n > 0) sink(buf.data(), n);
    total += int64_t(n);
    if (n < buf.size()) {
      if (std::ferror(f.get())) fail(ENH_E_IO, "read error");
      return total;
    }
  }
}

std::vector<std::string> lines(const std::string& s) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < s.size()) {
    size_t j = s.find('\n', i);
    if (j == std::string::npos) j = s.size();
    std::string l = s.substr(i, j - i);
    if (!l.empty() && l.back() == '\r') l.pop_back();
    out.push_back(std::move(l));
    i = j + 1;
  }
  return out;
}

int b64(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

}  // namespace

std::vector<uint8_t> base64_decode(const std::string& s) {
  if (s.size() % 4 != 0) fail(ENH_E_INVALID, "bad base64 length");
  std::vector<uint8_t> out;
  out.reserve(s.size() / 4 * 3);
  for (size_t i = 0; i < s.size(); i += 4) {
    int v[4];
    int pad = 0;
    for (int k = 0; k < 4; ++k) {
      const char c = s[i + k];
      if (c == '=' && i + 4 == s.size() && k >= 2) {
        v[k] = 0;
        ++pad;
      } else if (pad > 0 || (v[k] = b64(c)) < 0) {
        fail(ENH_E_INVALID, "bad base64");
      }
    }
    const uint32_t x = uint32_t(v[0]) << 18 | uint32_t(v[1]) << 12 | uint32_t(v[2]) << 6 | v[3];
    out.push_back(uint8_t(x >> 16));
    if (pad < 2) out.push_back(uint8_t(x >> 8));
    if (pad < 1) out.push_back(uint8_t(x));
  }
  return out;
}

void verify_file_sha256(const std::string& path, const std::string& sha256_hex) {
  if (sha256_hex.size() != 64) fail(ENH_E_INVALID, "sha256 must be 64 hex digits");
  std::string want;
  for (const char c : sha256_hex) {
    if (!std::isxdigit(static_cast<unsigned char>(c))) fail(ENH_E_INVALID, "bad hex");
    want += char(std::tolower(static_cast<unsigned char>(c)));
  }
  Sha256 h;
  stream(path, [&](const uint8_t* p, size_t n) { h.update(p, n); });
  if (h.hex() != want) fail(ENH_E_SIGNATURE, "sha256 mismatch");
}

MinisignKey parse_minisign_key(const std::string& base64) {
  const auto raw = base64_decode(base64);
  if (raw.size() != 42 || raw[0] != 'E' || raw[1] != 'd') fail(ENH_E_INVALID, "not a minisign key");
  MinisignKey k;
  std::memcpy(k.id, raw.data() + 2, 8);
  std::memcpy(k.key, raw.data() + 10, 32);
  return k;
}

std::string verify_minisign(const std::string& msg_path, const std::string& sig,
                            const std::vector<MinisignKey>& keys) {
  // untrusted comment / signature / trusted comment / global signature
  const auto l = lines(sig);
  if (l.size() < 4 || l[0].rfind("untrusted comment:", 0) != 0 ||
      l[2].rfind("trusted comment: ", 0) != 0) {
    fail(ENH_E_INVALID, "not a minisign signature");
  }
  const auto s = base64_decode(l[1]);
  const auto global = base64_decode(l[3]);
  if (s.size() != 74 || global.size() != 64 || s[0] != 'E') fail(ENH_E_INVALID, "bad signature");
  const bool prehashed = s[1] == 'D';
  if (!prehashed && s[1] != 'd') fail(ENH_E_INVALID, "unknown signature algorithm");
  const MinisignKey* key = nullptr;
  for (const auto& k : keys) {
    if (std::memcmp(k.id, s.data() + 2, 8) == 0) key = &k;
  }
  if (!key) fail(ENH_E_SIGNATURE, "signed with an unknown key");
  const uint8_t* signature = s.data() + 10;

  bool ok;
  if (prehashed) {
    crypto_blake2b_ctx ctx;
    crypto_blake2b_init(&ctx, 64);
    stream(msg_path, [&](const uint8_t* p, size_t n) { crypto_blake2b_update(&ctx, p, n); });
    uint8_t digest[64];
    crypto_blake2b_final(&ctx, digest);
    ok = crypto_ed25519_check(signature, key->key, digest, sizeof digest) == 0;
  } else {
    std::vector<uint8_t> msg;
    stream(msg_path, [&](const uint8_t* p, size_t k) {
      if (int64_t(msg.size() + k) > kMaxPureSignedBytes) fail(ENH_E_LIMIT, "message too large");
      msg.insert(msg.end(), p, p + k);
    });
    ok = crypto_ed25519_check(signature, key->key, msg.data(), msg.size()) == 0;
  }
  if (!ok) fail(ENH_E_SIGNATURE, "signature does not match");

  // The global signature covers the signature and the trusted comment (no rollback of the
  // comment, which carries e.g. the manifest serial).
  const std::string trusted = l[2].substr(std::strlen("trusted comment: "));
  std::vector<uint8_t> covered(signature, signature + 64);
  covered.insert(covered.end(), trusted.begin(), trusted.end());
  if (crypto_ed25519_check(global.data(), key->key, covered.data(), covered.size()) != 0) {
    fail(ENH_E_SIGNATURE, "trusted comment signature does not match");
  }
  return trusted;
}

}  // namespace enh
