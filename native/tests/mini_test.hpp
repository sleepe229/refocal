// Tiny dependency-free test runner.
#pragma once
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace mini {
struct Case {
  const char* name;
  std::function<void()> fn;
};
inline std::vector<Case>& cases() {
  static std::vector<Case> c;
  return c;
}
inline int& failures() {
  static int f = 0;
  return f;
}
inline int& checks() {
  static int n = 0;
  return n;
}
struct Reg {
  Reg(const char* n, std::function<void()> f) { cases().push_back({n, std::move(f)}); }
};
inline int run_all() {
  for (auto& c : cases()) {
    int before = failures();
    c.fn();
    std::printf("[%s] %s\n", failures() == before ? " OK " : "FAIL", c.name);
  }
  std::printf("%zu cases, %d checks, %d failures\n", cases().size(), checks(), failures());
  return failures() ? 1 : 0;
}
}  // namespace mini

#define MT_CAT2(a, b) a##b
#define MT_CAT(a, b) MT_CAT2(a, b)
#define TEST(name)                                                   \
  static void MT_CAT(t_, __LINE__)();                                \
  static mini::Reg MT_CAT(r_, __LINE__)(name, MT_CAT(t_, __LINE__)); \
  static void MT_CAT(t_, __LINE__)()
#define CHECK(cond)                                                         \
  do {                                                                      \
    ++mini::checks();                                                       \
    if (!(cond)) {                                                          \
      ++mini::failures();                                                   \
      std::printf("  %s:%d CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
    }                                                                       \
  } while (0)
#define CHECK_EQ(a, b)                                                                \
  do {                                                                                \
    ++mini::checks();                                                                 \
    auto _a = (a);                                                                    \
    auto _b = (b);                                                                    \
    if (!(_a == _b)) {                                                                \
      ++mini::failures();                                                             \
      std::printf("  %s:%d CHECK_EQ failed: %s vs %s\n", __FILE__, __LINE__, #a, #b); \
    }                                                                                 \
  } while (0)
