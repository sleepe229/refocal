// Log redaction (PRIV-LOG-001) and the rotating file sink (PRIV-LOG-002).
// SPDX-License-Identifier: Apache-2.0
#include <unistd.h>

#include <string>

#include "enh.h"
#include "mini_test.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"

using namespace enh;

TEST("redact: paths and URIs, nothing else") {
  CHECK(redact("cannot open /data/user/0/io.github.refocal.app/files/inbox/in-1.jpg") ==
        "cannot open <path>");
  CHECK(
      redact("FileSystemException: Cannot open file, path = '/storage/emulated/0/DCIM/a b.jpg'") ==
      "FileSystemException: Cannot open file, path = '<path>'");
  CHECK(redact("uri=content://media/external/images/media/42 ok") == "uri=<uri> ok");
  CHECK(redact("(file:///sdcard/x.png)") == "(<uri>)");
  CHECK(redact("fetch https://example.org/packs/a.json failed") ==
        "fetch https://example.org/packs/a.json failed");
  CHECK(redact("4/5 tiles, 1/2 scale, a/b") == "4/5 tiles, 1/2 scale, a/b");
  CHECK(redact("job job-1791987980200 done in 12 ms") == "job job-1791987980200 done in 12 ms");
  CHECK(redact("at main.dart:12 (package:refocal/main.dart:12:5)") ==
        "at main.dart:12 (package:refocal/main.dart:12:5)");
  CHECK(redact("/") == "/" && redact("a // b") == "a // b" && redact("") == "");
}

TEST("file sink: lines, levels, rotation") {
  char tmpl[] = "/tmp/enh-log-XXXXXX";
  const std::string dir = mkdtemp(tmpl);
  const std::string path = fs::join(dir, "core.log");
  CHECK(enh_log_open(path.c_str(), 100) == ENH_E_INVALID);
  CHECK(enh_log_open(path.c_str(), 4096) == ENH_OK);
  enh_log_write(ENH_LOG_INFO, "opened /data/x/y.jpg");
  enh_log_write(ENH_LOG_DEBUG, "dropped below the minimum level");
  enh_log_write(42, "dropped: bad level");
  const std::string text = fs::read_text(path);
  CHECK(text.find(" I opened <path>\n") != std::string::npos);
  CHECK(text.find("dropped") == std::string::npos);

  for (int i = 0; i < 200; ++i) enh_log_write(ENH_LOG_WARN, std::string(40, 'x').c_str());
  CHECK(fs::exists(path + ".1"));
  CHECK(fs::file_size(path) <= 4096 && fs::file_size(path + ".1") <= 4096);
  enh_log_set_level(ENH_LOG_DEBUG);
  enh_log_write(ENH_LOG_DEBUG, "debug now");
  CHECK(fs::read_text(path).find(" D debug now\n") != std::string::npos);
  enh_log_set_level(ENH_LOG_INFO);
  fs::remove_tree(dir);
}

int main() { return mini::run_all(); }
