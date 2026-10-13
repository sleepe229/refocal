// WebP input on libwebp (ADR-0003): still images via WebPDecode, animations via WebPAnimDecoder
// (first frame, FR-IMP-007), EXIF/ICCP chunks via WebPDemux.
// SPDX-License-Identifier: Apache-2.0
#include <webp/decode.h>
#include <webp/demux.h>

#include "image/decode.hpp"
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
  if (WebPGetFeatures(data.data(), data.size(), &f) != VP8_STATUS_OK) fail(ENH_E_INVALID, "WebP header is corrupt");
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
    i.orientation = tiff_orientation(exif.data(), exif.size());
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
    rgba_to_rgb_on_white(img.px, n, false);
  } else {
    img.w = f.width;
    img.h = f.height;
    const size_t n = size_t(img.w) * img.h;
    if (f.has_alpha) {
      img.px.resize(n * 4);
      if (!WebPDecodeRGBAInto(data.data(), data.size(), img.px.data(), img.px.size(), img.w * 4)) {
        fail(ENH_E_INVALID, "WebP decode failed");
      }
      rgba_to_rgb_on_white(img.px, n, false);
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

}  // namespace enh
