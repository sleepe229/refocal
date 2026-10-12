// SPDX-License-Identifier: Apache-2.0
#include "util/fs.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>

#include "util/error.hpp"

namespace enh::fs {
namespace {

[[noreturn]] void io_fail(const char* what, const std::string& path) {
  int e = errno;
  fail(e == ENOSPC || e == EDQUOT ? ENH_E_DISK_FULL : ENH_E_IO,
       std::string(what) + " failed: " + std::strerror(e) + " (" + path + ")");
}

}  // namespace

bool exists(const std::string& path) {
  struct stat st;
  return ::stat(path.c_str(), &st) == 0;
}

int64_t file_size(const std::string& path) {
  struct stat st;
  return ::stat(path.c_str(), &st) == 0 ? int64_t(st.st_size) : -1;
}

void mkdirs(const std::string& path) {
  std::string cur;
  for (size_t i = 0; i < path.size(); ++i) {
    cur.push_back(path[i]);
    if ((path[i] == '/' || i + 1 == path.size()) && cur != "/") {
      if (::mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) io_fail("mkdir", cur);
    }
  }
}

void remove_tree(const std::string& path) {
  if (DIR* d = ::opendir(path.c_str())) {
    while (dirent* e = ::readdir(d)) {
      if (!std::strcmp(e->d_name, ".") || !std::strcmp(e->d_name, "..")) continue;
      std::string p = join(path, e->d_name);
      struct stat st;
      if (::lstat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) remove_tree(p);
      else ::unlink(p.c_str());
    }
    ::closedir(d);
    ::rmdir(path.c_str());
  } else {
    ::unlink(path.c_str());
  }
}

void fsync_dir(const std::string& dir) {
  int fd = ::open(dir.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd >= 0) {
    ::fsync(fd);
    ::close(fd);
  }
}

void write_atomic(const std::string& path, const void* data, size_t n, bool durable) {
  std::string tmp = path + ".tmp";
  int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) io_fail("open", tmp);
  const auto* p = static_cast<const uint8_t*>(data);
  size_t left = n;
  while (left > 0) {
    ssize_t w = ::write(fd, p, left);
    if (w < 0) {
      if (errno == EINTR) continue;
      int e = errno;
      ::close(fd);
      ::unlink(tmp.c_str());
      errno = e;
      io_fail("write", tmp);
    }
    p += w;
    left -= size_t(w);
  }
  if (durable && ::fsync(fd) != 0) {
    int e = errno;
    ::close(fd);
    ::unlink(tmp.c_str());
    errno = e;
    io_fail("fsync", tmp);
  }
  ::close(fd);
  if (::rename(tmp.c_str(), path.c_str()) != 0) io_fail("rename", tmp);
  if (durable) {
    size_t slash = path.find_last_of('/');
    fsync_dir(slash == std::string::npos ? "." : path.substr(0, slash));
  }
}

void write_atomic(const std::string& path, const std::string& s, bool durable) {
  write_atomic(path, s.data(), s.size(), durable);
}

std::vector<uint8_t> read_all(const std::string& path) {
  int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) io_fail("open", path);
  std::vector<uint8_t> v;
  struct stat st;
  if (::fstat(fd, &st) == 0 && st.st_size > 0) v.reserve(size_t(st.st_size));
  uint8_t buf[1 << 16];
  for (;;) {
    ssize_t r = ::read(fd, buf, sizeof buf);
    if (r < 0) {
      if (errno == EINTR) continue;
      ::close(fd);
      io_fail("read", path);
    }
    if (r == 0) break;
    v.insert(v.end(), buf, buf + r);
  }
  ::close(fd);
  return v;
}

std::string read_text(const std::string& path) {
  auto v = read_all(path);
  return std::string(v.begin(), v.end());
}

void read_exact(const std::string& path, void* dst, size_t n) {
  int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) io_fail("open", path);
  auto* p = static_cast<uint8_t*>(dst);
  size_t left = n;
  while (left > 0) {
    ssize_t r = ::read(fd, p, left);
    if (r < 0 && errno == EINTR) continue;
    if (r <= 0) {
      ::close(fd);
      fail(ENH_E_IO, "short read (" + path + ")");
    }
    p += r;
    left -= size_t(r);
  }
  ::close(fd);
}

int64_t free_bytes(const std::string& dir) {
  struct statvfs vs;
  if (::statvfs(dir.c_str(), &vs) != 0) return -1;
  return int64_t(vs.f_bavail) * int64_t(vs.f_frsize);
}

std::string join(const std::string& a, const std::string& b) {
  if (a.empty()) return b;
  return a.back() == '/' ? a + b : a + "/" + b;
}

}  // namespace enh::fs
