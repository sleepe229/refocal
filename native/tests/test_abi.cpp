// ABI smoke test: exported symbols, session lifecycle, device probe JSON, UTF-8 sanitizing.
// SPDX-License-Identifier: Apache-2.0
#include <cstdio>
#include <cstring>
#include <string>

#include "enh.h"
#include "json_util.hpp"

static int fails = 0;
#define CHECK(c)                                                        \
  do {                                                                  \
    if (!(c)) {                                                         \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c); \
      ++fails;                                                          \
    }                                                                   \
  } while (0)

int main() {
  CHECK(enh_abi_version() == ENH_ABI_VERSION);
  CHECK(std::strlen(enh_version()) > 0);

  enh_session_config cfg{};
  enh_session* s = nullptr;
  CHECK(enh_session_create(&cfg, &s) == ENH_E_INVALID);  // struct_size = 0
  cfg.struct_size = sizeof cfg;
  cfg.work_dir = "/tmp";
  CHECK(enh_session_create(&cfg, &s) == ENH_OK);
  CHECK(s != nullptr);

  char* json = nullptr;
  CHECK(enh_device_probe(s, &json) == ENH_OK);
  CHECK(json && std::strstr(json, "\"schema\":1") && std::strstr(json, "\"cpu\":{"));
  if (json) std::printf("%s\n", json);
  enh_free(json);
  enh_session_destroy(s);

  // Strings leaving the core are valid UTF-8 (S6, TEST-FAULT-010).
  std::string out;
  enh::json_str(out, std::string("a\xff"
                                 "b\xc3\xa9\"\n",
                                 7));
  CHECK(out ==
        "\"a\xEF\xBF\xBD"
        "b\xc3\xa9\\\"\\n\"");
  out.clear();
  enh::json_str(out, std::string("\xed\xa0\x80", 3));  // UTF-16 surrogate encoded in UTF-8
  CHECK(out == "\"\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\"");

  std::printf("test_abi: %d failures\n", fails);
  return fails ? 1 : 0;
}
