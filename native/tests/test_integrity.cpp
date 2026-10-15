// SHA-256 and minisign verification (ADR-0021) against reference vectors made by minisign 0.11
// (tests/data/minisign: keys test/other, signatures of msg.txt prehashed and legacy, and of a
// 300 KB file; the secret keys were deleted after signing).
// SPDX-License-Identifier: Apache-2.0
#include <string>

#include "enh.h"
#include "mini_test.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/integrity.hpp"

using namespace enh;

static std::string g_dir, g_work;
static std::string at(const std::string& f) { return fs::join(g_dir, f); }
static std::string pub(const std::string& name) {
  const std::string t = fs::read_text(at(name + ".pub"));
  const size_t a = t.find('\n') + 1, b = t.find('\n', a);
  return t.substr(a, b - a);  // the key line
}
static enh_status status_of(void (*f)()) {
  try {
    f();
    return ENH_OK;
  } catch (const Error& e) {
    return e.status();
  }
}

TEST("sha256 of files, streamed") {
  CHECK(enh_verify_file(at("big.dat").c_str(),
                        "58b9dec19ba921aac16ea351d2978ddfe870ad7358a9826c9dccc15943bf84ec") ==
        ENH_OK);
  CHECK(enh_verify_file(at("big.dat").c_str(),
                        "58B9DEC19BA921AAC16EA351D2978DDFE870AD7358A9826C9DCCC15943BF84EC") ==
        ENH_OK);
  std::string wrong = "58b9dec19ba921aac16ea351d2978ddfe870ad7358a9826c9dccc15943bf84ec";
  wrong[0] = wrong[0] == '0' ? '1' : '0';
  CHECK(enh_verify_file(at("big.dat").c_str(), wrong.c_str()) == ENH_E_SIGNATURE);
  CHECK(enh_verify_file(at("big.dat").c_str(), "abc") == ENH_E_INVALID);
  CHECK(enh_verify_file(at("missing").c_str(),
                        "58b9dec19ba921aac16ea351d2978ddfe870ad7358a9826c9dccc15943bf84ec") ==
        ENH_E_IO);
}

TEST("minisign: prehashed and legacy signatures, the trusted comment") {
  const std::vector<MinisignKey> keys{parse_minisign_key(pub("other")),
                                      parse_minisign_key(pub("test"))};
  CHECK(verify_minisign(at("msg.txt"), fs::read_text(at("msg.txt.minisig")), keys) == "serial:7");
  CHECK(verify_minisign(at("msg.txt"), fs::read_text(at("msg.txt.legacy.minisig")), keys) ==
        "legacy");
  CHECK(verify_minisign(at("big.dat"), fs::read_text(at("big.dat.minisig")), keys) == "big");
  const std::string csv = pub("other") + "," + pub("test");
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), at("msg.txt.minisig").c_str(), csv.c_str()) ==
        ENH_OK);
}

TEST("minisign: rejected") {
  const std::string csv = pub("test");
  // Signed by a key the app does not have.
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), at("msg.txt.minisig").c_str(),
                            pub("other").c_str()) == ENH_E_SIGNATURE);
  // Another message under the signature.
  CHECK(enh_verify_minisign(at("big.dat").c_str(), at("msg.txt.minisig").c_str(), csv.c_str()) ==
        ENH_E_SIGNATURE);
  // A changed trusted comment (e.g. a lower manifest serial) breaks the global signature.
  std::string sig = fs::read_text(at("msg.txt.minisig"));
  const size_t p = sig.find("serial:7");
  sig.replace(p, 8, "serial:6");
  const std::string forged = fs::join(g_work, "forged.minisig");
  fs::write_atomic(forged, sig);
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), forged.c_str(), csv.c_str()) == ENH_E_SIGNATURE);
  // Malformed input.
  fs::write_atomic(forged, "untrusted comment: x\nnot base64!\n");
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), forged.c_str(), csv.c_str()) == ENH_E_INVALID);
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), at("msg.txt.minisig").c_str(), "Zm9v") ==
        ENH_E_INVALID);
  CHECK(enh_verify_minisign(at("msg.txt").c_str(), at("msg.txt.minisig").c_str(), "") ==
        ENH_E_INVALID);
  CHECK(status_of([] { (void)base64_decode("YQ="); }) == ENH_E_INVALID);
  CHECK(base64_decode("YWJj") == std::vector<uint8_t>({'a', 'b', 'c'}));
  CHECK(base64_decode("YWI=") == std::vector<uint8_t>({'a', 'b'}));
}

int main(int argc, char** argv) {
  g_dir = argc > 1 ? argv[1] : "tests/data/minisign";
  g_work = argc > 2 ? argv[2] : "test-work-integrity";
  fs::mkdirs(g_work);
  return mini::run_all();
}
