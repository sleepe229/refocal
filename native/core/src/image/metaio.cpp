// SPDX-License-Identifier: Apache-2.0
#include "image/metaio.hpp"

#include <algorithm>
#include <cstring>
#include <map>
#include <memory>
#include <utility>

namespace enh {
namespace {

struct Bad {};  // malformed TIFF; never escapes this file

// Bytes per component of the TIFF field types 1..13 (0 = unknown type: the entry is dropped).
size_t type_size(uint16_t t) {
  static const size_t sz[] = {0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4};
  return t < sizeof sz / sizeof sz[0] ? sz[t] : 0;
}

constexpr uint16_t kTypeShort = 3, kTypeLong = 4;
constexpr uint16_t kInteropIfd = 0xA005;
constexpr uint16_t kOrientation = 0x0112;
constexpr uint16_t kPixelX = 0xA002, kPixelY = 0xA003;

bool is_ifd_pointer(uint16_t tag) { return tag == kExifIfd || tag == kGpsIfd || tag == kInteropIfd; }

// Tags that point into data we do not carry over (thumbnail, strips, sub-images), that the
// result replaces (embedded XMP/ICC, size) or that identify the camera or the original
// (PRIV-META-002). Everything else is copied as is.
bool dropped(uint16_t tag) {
  switch (tag) {
    case 0x0100: case 0x0101:  // ImageWidth/Length (the result has its own)
    case 0x0111: case 0x0117:  // StripOffsets/ByteCounts
    case 0x0144: case 0x0145:  // TileOffsets/ByteCounts
    case 0x014A:               // SubIFDs
    case 0x0201: case 0x0202:  // JPEGInterchangeFormat(Length): thumbnail
    case 0x02BC:               // XMP in TIFF
    case 0x8773:               // ICC in TIFF
    case 0x927C:               // MakerNote: vendor offsets break when moved; serials inside
    case 0xA420:               // ImageUniqueID: identifies the original
    case 0xA431:               // BodySerialNumber
    case 0xA435:               // LensSerialNumber
    case 0xC4A5:               // PrintIM
      return true;
    default:
      return false;
  }
}

struct Entry {
  uint16_t tag = 0, type = 0;
  uint32_t count = 0;
  std::vector<uint8_t> data;  // raw, in the source byte order
};

struct Ifd {
  std::vector<Entry> entries;
  std::map<uint16_t, std::unique_ptr<Ifd>> subs;  // by pointer tag
};

class Tiff {
 public:
  Tiff(const uint8_t* d, size_t n) : d_(d), n_(n) {
    if (n < 8) throw Bad{};
    if (d[0] == 'I' && d[1] == 'I') le_ = true;
    else if (d[0] == 'M' && d[1] == 'M') le_ = false;
    else throw Bad{};
    if (u16(2) != 42) throw Bad{};
  }
  bool le() const { return le_; }
  uint32_t root() const { return u32(4); }

  uint32_t u16(uint64_t o) const {
    need(o, 2);
    return le_ ? uint32_t(d_[o]) | uint32_t(d_[o + 1]) << 8 : uint32_t(d_[o]) << 8 | uint32_t(d_[o + 1]);
  }
  uint32_t u32(uint64_t o) const {
    return le_ ? u16(o) | u16(o + 2) << 16 : u16(o) << 16 | u16(o + 2);
  }

  std::unique_ptr<Ifd> ifd(uint32_t off, int depth) const {
    if (depth > 3) throw Bad{};
    auto out = std::make_unique<Ifd>();
    const uint32_t count = u16(off);
    if (count > 1024) throw Bad{};
    for (uint32_t i = 0; i < count; ++i) {
      const uint64_t e = uint64_t(off) + 2 + uint64_t(i) * 12;
      need(e, 12);
      Entry en;
      en.tag = uint16_t(u16(e));
      en.type = uint16_t(u16(e + 2));
      en.count = u32(e + 4);
      if (is_ifd_pointer(en.tag) && en.count == 1 && (en.type == kTypeLong || en.type == 13)) {
        try {
          out->subs[en.tag] = ifd(u32(e + 8), depth + 1);
        } catch (const Bad&) {  // a broken sub-IFD costs that IFD, not the whole EXIF
        }
        continue;
      }
      const size_t ts = type_size(en.type);
      if (ts == 0) continue;
      const uint64_t size = uint64_t(en.count) * ts;
      if (size > n_) continue;
      const uint64_t at = size <= 4 ? e + 8 : u32(e + 8);
      if (at + size > n_) continue;  // dangling offset: drop the entry
      en.data.assign(d_ + at, d_ + at + size);
      out->entries.push_back(std::move(en));
    }
    return out;
  }

 private:
  void need(uint64_t o, uint64_t len) const {
    if (o + len > n_) throw Bad{};
  }
  const uint8_t* d_;
  size_t n_;
  bool le_ = true;
};

class Writer {
 public:
  explicit Writer(bool le) : le_(le) {
    const uint8_t hdr[4] = {uint8_t(le ? 'I' : 'M'), uint8_t(le ? 'I' : 'M'), 0, 0};
    out_.assign(hdr, hdr + 4);
    put16(out_, 2, 42);
    put32_append(out_, 8);
  }

  uint32_t write_ifd(const Ifd& ifd) {
    struct Item {
      uint16_t tag;
      const Entry* e;  // null: sub-IFD pointer
    };
    std::vector<Item> items;
    for (const auto& e : ifd.entries) items.push_back({e.tag, &e});
    for (const auto& [tag, sub] : ifd.subs) items.push_back({tag, nullptr});
    std::sort(items.begin(), items.end(), [](const Item& a, const Item& b) { return a.tag < b.tag; });

    const uint32_t off = uint32_t(out_.size());
    const uint32_t data_start = off + 2 + 12 * uint32_t(items.size()) + 4;
    std::vector<uint8_t> data;
    std::vector<std::pair<uint16_t, size_t>> patches;  // sub tag -> value position in out_
    append16(uint16_t(items.size()));
    for (const Item& it : items) {
      append16(it.tag);
      if (!it.e) {
        append16(kTypeLong);
        append32(1);
        patches.push_back({it.tag, out_.size()});
        append32(0);
        continue;
      }
      append16(it.e->type);
      append32(it.e->count);
      if (it.e->data.size() <= 4) {
        uint8_t v[4] = {};
        if (!it.e->data.empty()) std::memcpy(v, it.e->data.data(), it.e->data.size());
        out_.insert(out_.end(), v, v + 4);
      } else {
        if (data.size() % 2) data.push_back(0);  // word alignment
        append32(data_start + uint32_t(data.size()));
        data.insert(data.end(), it.e->data.begin(), it.e->data.end());
      }
    }
    append32(0);  // no next IFD: the thumbnail IFD1 is dropped
    out_.insert(out_.end(), data.begin(), data.end());
    for (auto [tag, pos] : patches) {
      if (out_.size() % 2) out_.push_back(0);
      const uint32_t sub = write_ifd(*ifd.subs.at(tag));
      put32(out_, pos, sub);
    }
    return off;
  }

  std::vector<uint8_t> take() { return std::move(out_); }

 private:
  void put16(std::vector<uint8_t>& b, size_t pos, uint16_t v) const {
    b[pos] = uint8_t(le_ ? v : v >> 8);
    b[pos + 1] = uint8_t(le_ ? v >> 8 : v);
  }
  void put32(std::vector<uint8_t>& b, size_t pos, uint32_t v) const {
    put16(b, pos + (le_ ? 0 : 2), uint16_t(v));
    put16(b, pos + (le_ ? 2 : 0), uint16_t(v >> 16));
  }
  void put32_append(std::vector<uint8_t>& b, uint32_t v) const {
    b.resize(b.size() + 4);
    put32(b, b.size() - 4, v);
  }
  void append16(uint16_t v) {
    out_.resize(out_.size() + 2);
    put16(out_, out_.size() - 2, v);
  }
  void append32(uint32_t v) { put32_append(out_, v); }

  bool le_;
  std::vector<uint8_t> out_;
};

std::vector<uint8_t> encode16(bool le, uint16_t v) {
  return le ? std::vector<uint8_t>{uint8_t(v), uint8_t(v >> 8)} : std::vector<uint8_t>{uint8_t(v >> 8), uint8_t(v)};
}
std::vector<uint8_t> encode32(bool le, uint32_t v) {
  std::vector<uint8_t> b = {uint8_t(v), uint8_t(v >> 8), uint8_t(v >> 16), uint8_t(v >> 24)};
  if (!le) std::reverse(b.begin(), b.end());
  return b;
}

void filter(Ifd& ifd) {
  std::erase_if(ifd.entries, [](const Entry& e) { return dropped(e.tag); });
}

void set_entry(Ifd& ifd, uint16_t tag, uint16_t type, std::vector<uint8_t> data) {
  std::erase_if(ifd.entries, [&](const Entry& e) { return e.tag == tag; });
  ifd.entries.push_back({tag, type, 1, std::move(data)});
}

int64_t read_int(const Entry& e, bool le) {
  if (e.data.empty()) return -1;
  auto b = [&](size_t i) { return int64_t(e.data[i]); };
  switch (e.type) {
    case 1: case 6: case 7:
      return b(0);
    case 3: case 8:
      return e.data.size() < 2 ? -1 : le ? b(0) | b(1) << 8 : b(0) << 8 | b(1);
    case 4: case 9:
      if (e.data.size() < 4) return -1;
      return le ? b(0) | b(1) << 8 | b(2) << 16 | b(3) << 24 : b(0) << 24 | b(1) << 16 | b(2) << 8 | b(3);
    default:
      return int64_t(e.data.size());
  }
}

}  // namespace

namespace {
// The one place that knows the prefix: everything else sees a bare TIFF block.
std::pair<const uint8_t*, size_t> tiff_view(const uint8_t* d, size_t n) {
  if (d && n >= 6 && std::memcmp(d, "Exif\0\0", 6) == 0) return {d + 6, n - 6};
  return {d, d ? n : 0};
}
}  // namespace

std::vector<uint8_t> exif_to_tiff(const uint8_t* exif, size_t n) {
  const auto [d, len] = tiff_view(exif, n);
  if (len < 8 || !((d[0] == 'I' && d[1] == 'I') || (d[0] == 'M' && d[1] == 'M'))) return {};
  return std::vector<uint8_t>(d, d + len);
}

int exif_orientation(const uint8_t* exif, size_t n) {
  const auto [d, len] = tiff_view(exif, n);
  try {
    Tiff t(d, len);
    auto ifd0 = t.ifd(t.root(), 0);
    for (const Entry& e : ifd0->entries) {
      if (e.tag == kOrientation && e.type == kTypeShort) {
        int64_t v = read_int(e, t.le());
        return v >= 1 && v <= 8 ? int(v) : 1;
      }
    }
  } catch (const Bad&) {
  }
  return 1;
}

std::vector<uint8_t> exif_rewrite(const uint8_t* tiff, size_t n, const ExifPolicy& p) {
  try {
    Tiff t(tiff, n);
    const bool le = t.le();
    auto ifd0 = t.ifd(t.root(), 0);
    filter(*ifd0);
    ifd0->subs.erase(kInteropIfd);  // belongs to the Exif IFD
    if (!p.keep_gps) ifd0->subs.erase(kGpsIfd);
    set_entry(*ifd0, kOrientation, kTypeShort, encode16(le, 1));

    auto& exif = ifd0->subs[kExifIfd];
    if (!exif) exif = std::make_unique<Ifd>();
    filter(*exif);
    exif->subs.erase(kExifIfd);
    exif->subs.erase(kGpsIfd);
    set_entry(*exif, kPixelX, kTypeLong, encode32(le, uint32_t(p.width)));
    set_entry(*exif, kPixelY, kTypeLong, encode32(le, uint32_t(p.height)));
    for (auto& [tag, sub] : exif->subs) sub->subs.clear();
    if (auto it = ifd0->subs.find(kGpsIfd); it != ifd0->subs.end()) it->second->subs.clear();

    Writer w(le);
    w.write_ifd(*ifd0);
    return w.take();
  } catch (const Bad&) {
    return {};
  }
}

int64_t exif_get(const std::vector<uint8_t>& tiff, uint16_t ifd_tag, uint16_t tag) {
  try {
    Tiff t(tiff.data(), tiff.size());
    auto ifd0 = t.ifd(t.root(), 0);
    const Ifd* ifd = ifd0.get();
    if (ifd_tag != kIfd0) {
      auto it = ifd0->subs.find(ifd_tag);
      if (it == ifd0->subs.end()) return -1;
      ifd = it->second.get();
    }
    for (const Entry& e : ifd->entries)
      if (e.tag == tag) return read_int(e, t.le());
  } catch (const Bad&) {
  }
  return -1;
}

std::string ai_marker_xmp(const std::string& creator_tool) {
  std::string tool;
  for (char c : creator_tool) {  // attribute value: escape XML specials
    switch (c) {
      case '&': tool += "&amp;"; break;
      case '<': tool += "&lt;"; break;
      case '>': tool += "&gt;"; break;
      case '"': tool += "&quot;"; break;
      default: tool += c;
    }
  }
  return std::string("<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n") +
         "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n"
         " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"
         "  <rdf:Description rdf:about=\"\"\n"
         "    xmlns:Iptc4xmpExt=\"http://iptc.org/std/Iptc4xmpExt/2008-02-29/\"\n"
         "    xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\n"
         "    Iptc4xmpExt:DigitalSourceType=\"" + kDigitalSourceType + "\"\n"
         "    xmp:CreatorTool=\"" + tool + "\"/>\n"
         " </rdf:RDF>\n"
         "</x:xmpmeta>\n"
         "<?xpacket end=\"w\"?>";
}

bool icc_header_valid(const uint8_t* p, size_t n) {
  if (!p || n < 132 || n > kMaxMetaBytes) return false;
  const uint32_t size = uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
  if (size != n || std::memcmp(p + 36, "acsp", 4) != 0) return false;
  return p[8] < 4 || n % 4 == 0;
}

}  // namespace enh
