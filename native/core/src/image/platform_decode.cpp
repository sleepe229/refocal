// Platform decoders for formats the core does not carry (ADR-0003): HEIC/HEIF, AVIF, GIF, BMP.
// Android: AImageDecoder (API 30+), resolved with dlopen because minSdk is 29; on 29 the
// platform layer converts such files before they reach the core. The decoder applies the EXIF
// orientation and converts to sRGB (Display P3 HEICs would otherwise lose their color space:
// no ICC is carried for these formats). iOS (ImageIO) comes with the iOS build.
// SPDX-License-Identifier: Apache-2.0
#include <cstring>
#include <type_traits>

#include "image/decode.hpp"
#include "util/error.hpp"

#if defined(__ANDROID__)
#include <android/bitmap.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#endif

namespace enh {

#if defined(__ANDROID__)
namespace {

// <android/imagedecoder.h> declares these only for API >= 30; the subset we use, by value.
struct AImageDecoder;
struct AImageDecoderHeaderInfo;
constexpr int kDecoderSuccess = 0;
constexpr int32_t kDataSpaceSrgb = 142671872;  // ADATASPACE_SRGB, <android/data_space.h>

struct Api {
  int (*create_from_fd)(int, AImageDecoder**) = nullptr;
  void (*destroy)(AImageDecoder*) = nullptr;
  const AImageDecoderHeaderInfo* (*header)(const AImageDecoder*) = nullptr;
  int32_t (*width)(const AImageDecoderHeaderInfo*) = nullptr;
  int32_t (*height)(const AImageDecoderHeaderInfo*) = nullptr;
  const char* (*mime)(const AImageDecoderHeaderInfo*) = nullptr;
  int (*alpha_flags)(const AImageDecoderHeaderInfo*) = nullptr;
  int (*set_format)(AImageDecoder*, int32_t) = nullptr;
  int (*set_dataspace)(AImageDecoder*, int32_t) = nullptr;
  size_t (*min_stride)(AImageDecoder*) = nullptr;
  int (*decode)(AImageDecoder*, void*, size_t, size_t) = nullptr;
  bool ok = false;

  Api() {
    void* h = dlopen("libjnigraphics.so", RTLD_NOW | RTLD_LOCAL);
    if (!h) return;
    auto sym = [&](auto& fn, const char* name) {
      fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(dlsym(h, name));
      return fn != nullptr;
    };
    ok = sym(create_from_fd, "AImageDecoder_createFromFd") &&
         sym(destroy, "AImageDecoder_delete") && sym(header, "AImageDecoder_getHeaderInfo") &&
         sym(width, "AImageDecoderHeaderInfo_getWidth") &&
         sym(height, "AImageDecoderHeaderInfo_getHeight") &&
         sym(mime, "AImageDecoderHeaderInfo_getMimeType") &&
         sym(alpha_flags, "AImageDecoderHeaderInfo_getAlphaFlags") &&
         sym(set_format, "AImageDecoder_setAndroidBitmapFormat") &&
         sym(set_dataspace, "AImageDecoder_setDataSpace") &&
         sym(min_stride, "AImageDecoder_getMinimumStride") &&
         sym(decode, "AImageDecoder_decodeImage");
  }
};

const Api& api() {
  static const Api a;
  return a;
}

// The fd stays ours (AImageDecoder_createFromFd does not take it) and must outlive the decoder.
class Fd {
 public:
  explicit Fd(const std::string& path) : fd_(::open(path.c_str(), O_RDONLY | O_CLOEXEC)) {}
  ~Fd() {
    if (fd_ >= 0) ::close(fd_);
  }
  Fd(const Fd&) = delete;
  Fd& operator=(const Fd&) = delete;
  int get() const { return fd_; }

 private:
  int fd_;
};

class Decoder {
 public:
  // Members are complete objects before the body runs: a throw here still closes the fd.
  explicit Decoder(const std::string& path) : fd_(path) {
    if (fd_.get() < 0) fail(ENH_E_IO, "cannot open input");
    if (api().create_from_fd(fd_.get(), &d_) != kDecoderSuccess || !d_) {
      fail(ENH_E_INVALID, "unsupported or corrupt image");
    }
  }
  ~Decoder() {
    if (d_) api().destroy(d_);
  }
  Decoder(const Decoder&) = delete;
  Decoder& operator=(const Decoder&) = delete;
  AImageDecoder* get() const { return d_; }
  const AImageDecoderHeaderInfo* header() const { return api().header(d_); }

 private:
  Fd fd_;  // declared first: destroyed after the decoder
  AImageDecoder* d_ = nullptr;
};

}  // namespace

bool platform_decoder_available() { return api().ok; }

ImageInfo platform_probe(const std::string& path) {
  if (!api().ok) fail(ENH_E_INVALID, "this format needs Android 11 or later");
  Decoder d(path);
  ImageInfo i;
  i.w = api().width(d.header());
  i.h = api().height(d.header());
  i.alpha = api().alpha_flags(d.header()) != ANDROID_BITMAP_FLAGS_ALPHA_OPAQUE;
  return i;
}

Rgb8 platform_decode(const std::string& path, std::vector<uint8_t>* alpha) {
  if (!api().ok) fail(ENH_E_INVALID, "this format needs Android 11 or later");
  Decoder d(path);
  Rgb8 img;
  img.w = api().width(d.header());
  img.h = api().height(d.header());
  if (api().set_format(d.get(), ANDROID_BITMAP_FORMAT_RGBA_8888) != kDecoderSuccess) {
    fail(ENH_E_INVALID, "cannot decode to RGBA");
  }
  api().set_dataspace(d.get(), kDataSpaceSrgb);  // best effort: fails for images without one
  const size_t stride = api().min_stride(d.get());
  const size_t row = size_t(img.w) * 4;
  if (stride < row) fail(ENH_E_INTERNAL, "bad stride");
  std::vector<uint8_t> buf(stride * size_t(img.h));
  if (api().decode(d.get(), buf.data(), stride, buf.size()) != kDecoderSuccess) {
    fail(ENH_E_INVALID, "image decode failed");
  }
  if (stride != row) {  // compact rows in place
    for (int y = 1; y < img.h; ++y)
      std::memmove(buf.data() + y * row, buf.data() + y * stride, row);
  }
  const size_t n = size_t(img.w) * img.h;
  buf.resize(n * 4);
  // AImageDecoder outputs premultiplied alpha by default.
  const bool has_alpha = api().alpha_flags(d.header()) != ANDROID_BITMAP_FLAGS_ALPHA_OPAQUE;
  rgba_to_rgb_on_white(buf, n, true, has_alpha ? alpha : nullptr);
  img.px = std::move(buf);
  return img;
}

#else

bool platform_decoder_available() { return false; }
ImageInfo platform_probe(const std::string&) { fail(ENH_E_INVALID, "unsupported input format"); }
Rgb8 platform_decode(const std::string&, std::vector<uint8_t>*) {
  fail(ENH_E_INVALID, "unsupported input format");
}

#endif

}  // namespace enh
