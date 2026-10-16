// WebP on libwebp (ADR-0003). Input: still images via WebPDecode, animations via WebPAnimDecoder
// (first frame, FR-IMP-007), EXIF/ICCP chunks via WebPDemux. Output (FR-EXP-001): WebPEncode,
// metadata chunks via WebPMux.
// SPDX-License-Identifier: Apache-2.0
#include <webp/decode.h>
#include <webp/demux.h>
#include <webp/encode.h>
#include <webp/mux.h>

#include <cstdio>
#include <cstring>

#include "image/decode.hpp"
#include "image/encode.hpp"
#include "image/metaio.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

namespace enh {
namespace {

std::vector<uint8_t> read_file(const std::string& path) {
  if (fs::file_size(path) > kMaxFileBytes) fail(ENH_E_LIMIT, "file is larger than 200 MB");
  return fs::read_all(path);
}

WebPBitstreamFeatures features(const std::vector<uint8_t>& data) {
  WebPBitstreamFeatures f{};
  if (WebPGetFeatures(data.data(), data.size(), &f) != VP8_STATUS_OK)
    fail(ENH_E_INVALID, "WebP header is corrupt");
  return f;
}

std::vector<uint8_t> chunk(WebPDemuxer* d, const char* fourcc) {
  WebPChunkIterator it{};
  std::vector<uint8_t> out;
  if (WebPDemuxGetChunk(d, fourcc, 1, &it)) {
    if (it.chunk.size <= kMaxMetaBytes) out.assign(it.chunk.bytes, it.chunk.bytes + it.chunk.size);
    WebPDemuxReleaseChunkIterator(&it);
  }
  return out;
}

struct Demux {
  WebPDemuxer* d = nullptr;
  explicit Demux(const std::vector<uint8_t>& data) {
    WebPData wd{data.data(), data.size()};
    d = WebPDemux(&wd);
  }
  ~Demux() { WebPDemuxDelete(d); }
};

}  // namespace

ImageInfo webp_probe(const std::string& path) {
  const auto data = read_file(path);
  const WebPBitstreamFeatures f = features(data);
  ImageInfo i;
  i.w = f.width;
  i.h = f.height;
  i.alpha = f.has_alpha;
  i.animated = f.has_animation;
  Demux dm(data);
  if (dm.d) {
    const auto exif = chunk(dm.d, "EXIF");
    i.orientation = exif_orientation(exif.data(), exif.size());
    if (i.animated) {  // the canvas, not the first frame's bitstream, is what we decode
      i.w = int(WebPDemuxGetI(dm.d, WEBP_FF_CANVAS_WIDTH));
      i.h = int(WebPDemuxGetI(dm.d, WEBP_FF_CANVAS_HEIGHT));
    }
  }
  return i;
}

Rgb8 webp_decode(const std::string& path, SourceMeta* meta) {
  const auto data = read_file(path);
  const WebPBitstreamFeatures f = features(data);
  Rgb8 img;
  if (f.has_animation) {
    WebPAnimDecoderOptions opt;
    WebPAnimDecoderOptionsInit(&opt);
    opt.color_mode = MODE_RGBA;
    opt.use_threads = 0;
    WebPData wd{data.data(), data.size()};
    WebPAnimDecoder* dec = WebPAnimDecoderNew(&wd, &opt);
    if (!dec) fail(ENH_E_INVALID, "animated WebP is corrupt");
    WebPAnimInfo ai{};
    uint8_t* frame = nullptr;
    int ts = 0;
    if (!WebPAnimDecoderGetInfo(dec, &ai) || !WebPAnimDecoderGetNext(dec, &frame, &ts)) {
      WebPAnimDecoderDelete(dec);
      fail(ENH_E_INVALID, "animated WebP is corrupt");
    }
    img.w = int(ai.canvas_width);
    img.h = int(ai.canvas_height);
    const size_t n = size_t(img.w) * img.h;
    img.px.assign(frame, frame + n * 4);
    WebPAnimDecoderDelete(dec);
    rgba_to_rgb_on_white(img.px, n, false, meta ? &meta->alpha : nullptr);
  } else {
    img.w = f.width;
    img.h = f.height;
    const size_t n = size_t(img.w) * img.h;
    if (f.has_alpha) {
      img.px.resize(n * 4);
      if (!WebPDecodeRGBAInto(data.data(), data.size(), img.px.data(), img.px.size(), img.w * 4)) {
        fail(ENH_E_INVALID, "WebP decode failed");
      }
      rgba_to_rgb_on_white(img.px, n, false, meta ? &meta->alpha : nullptr);
    } else {
      img.px.resize(n * 3);
      if (!WebPDecodeRGBInto(data.data(), data.size(), img.px.data(), img.px.size(), img.w * 3)) {
        fail(ENH_E_INVALID, "WebP decode failed");
      }
    }
  }
  if (meta) {
    Demux dm(data);
    if (dm.d) {
      const auto exif = chunk(dm.d, "EXIF");
      meta->exif = exif_to_tiff(exif.data(), exif.size());
      meta->icc = chunk(dm.d, "ICCP");
    }
  }
  return img;
}

// ---- output ----

struct WebpWriter::Impl {
  std::string path;
  int w = 0, h = 0, quality = 0, y = 0;
  bool lossless = false, finished = false, alpha = false;
  OutputMeta meta;
  std::vector<uint8_t> rgb;  // libwebp encodes a whole picture; RGBA with [alpha]
};

WebpWriter::WebpWriter(const std::string& path, int w, int h, int quality, bool lossless,
                       const OutputMeta* meta, bool alpha)
    : impl_(std::make_unique<Impl>()) {
  if (w > kWebpMaxSide || h > kWebpMaxSide)
    fail(ENH_E_LIMIT, "WebP is limited to 16383 px per side");
  if (double(w) * h > (lossless ? kWebpLosslessMaxPixels : kWebpMaxPixels)) {
    fail(ENH_E_LIMIT, lossless ? "lossless WebP is limited to 24 MP" : "WebP is limited to 50 MP");
  }
  Impl& m = *impl_;
  m.path = path;
  m.w = w;
  m.h = h;
  m.quality = quality;
  m.lossless = lossless;
  if (meta) m.meta = *meta;
  m.alpha = alpha;
  m.rgb.resize(size_t(w) * h * (alpha ? 4 : 3));
}

WebpWriter::~WebpWriter() = default;

void WebpWriter::write_rows(const uint8_t* rgb, int rows, const uint8_t* alpha) {
  Impl& m = *impl_;
  if (rows > m.h - m.y) fail(ENH_E_INTERNAL, "WebP: too many rows");
  if (m.alpha != (alpha != nullptr)) fail(ENH_E_INTERNAL, "WebP: alpha rows expected or not");
  if (!m.alpha) {
    std::memcpy(m.rgb.data() + size_t(m.y) * m.w * 3, rgb, size_t(rows) * m.w * 3);
  } else {
    uint8_t* d = m.rgb.data() + size_t(m.y) * m.w * 4;
    for (size_t i = 0; i < size_t(rows) * m.w; ++i, d += 4) {
      d[0] = rgb[i * 3];
      d[1] = rgb[i * 3 + 1];
      d[2] = rgb[i * 3 + 2];
      d[3] = alpha[i];
    }
  }
  m.y += rows;
}

void WebpWriter::finish() {
  Impl& m = *impl_;
  if (m.finished) return;
  if (m.y != m.h) fail(ENH_E_INTERNAL, "WebP: rows do not add up");

  WebPConfig cfg;
  if (!WebPConfigInit(&cfg)) fail(ENH_E_INTERNAL, "libwebp version mismatch");
  if (m.lossless) {
    WebPConfigLosslessPreset(&cfg, 3);  // levels above 3 cost minutes on large photos
  } else {
    cfg.quality = float(m.quality);
    cfg.method = 4;
  }
  WebPPicture pic;
  if (!WebPPictureInit(&pic)) fail(ENH_E_INTERNAL, "libwebp version mismatch");
  pic.width = m.w;
  pic.height = m.h;
  pic.use_argb = m.lossless;
  WebPMemoryWriter mw;
  WebPMemoryWriterInit(&mw);
  pic.writer = WebPMemoryWrite;
  pic.custom_ptr = &mw;
  bool ok = m.alpha ? WebPPictureImportRGBA(&pic, m.rgb.data(), m.w * 4)
                    : WebPPictureImportRGB(&pic, m.rgb.data(), m.w * 3);
  std::vector<uint8_t>().swap(m.rgb);  // the picture holds its own copy now
  ok = ok && WebPEncode(&cfg, &pic);
  const WebPEncodingError err = pic.error_code;
  WebPPictureFree(&pic);
  struct Out {
    WebPMemoryWriter* mw;
    WebPData assembled{};
    WebPMux* mux = nullptr;
    ~Out() {
      WebPMemoryWriterClear(mw);
      WebPDataClear(&assembled);
      WebPMuxDelete(mux);
    }
  } out{&mw};
  if (!ok) {
    fail(err == VP8_ENC_ERROR_OUT_OF_MEMORY || err == VP8_ENC_ERROR_BITSTREAM_OUT_OF_MEMORY
             ? ENH_E_OOM
             : ENH_E_INTERNAL,
         "WebP encode failed: " + std::to_string(int(err)));
  }

  const uint8_t* bytes = mw.mem;
  size_t size = mw.size;
  const OutputMeta& md = m.meta;
  if (!md.exif.empty() || !md.icc.empty() || !md.xmp.empty()) {
    const WebPData bits{mw.mem, mw.size};
    out.mux = WebPMuxCreate(&bits, 0);
    if (!out.mux) fail(ENH_E_INTERNAL, "WebPMuxCreate");
    auto set = [&](const char* fourcc, const void* p, size_t n) {
      if (n == 0) return;
      const WebPData d{static_cast<const uint8_t*>(p), n};
      if (WebPMuxSetChunk(out.mux, fourcc, &d, 1) != WEBP_MUX_OK)
        fail(ENH_E_INTERNAL, "WebPMuxSetChunk");
    };
    set("ICCP", md.icc.data(), md.icc.size());
    set("EXIF", md.exif.data(), md.exif.size());
    set("XMP ", md.xmp.data(), md.xmp.size());
    if (WebPMuxAssemble(out.mux, &out.assembled) != WEBP_MUX_OK)
      fail(ENH_E_INTERNAL, "WebPMuxAssemble");
    bytes = out.assembled.bytes;
    size = out.assembled.size;
  }
  FILE* f = std::fopen(m.path.c_str(), "wb");
  if (!f) fail(ENH_E_IO, "cannot create output");
  const bool wrote = std::fwrite(bytes, 1, size, f) == size;
  const bool closed = std::fclose(f) == 0;
  if (!wrote || !closed) fail(ENH_E_IO, "WebP write failed");
  m.finished = true;
}

}  // namespace enh
