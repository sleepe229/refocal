// SPDX-License-Identifier: Apache-2.0
#include "image/heif_meta.hpp"

#include <algorithm>
#include <cstring>
#include <map>
#include <set>

#include "util/error.hpp"

namespace enh {
namespace {

[[noreturn]] void bad(const char* why) { fail(ENH_E_INVALID, std::string("heif: ") + why); }

// Bounds-checked big-endian reader over [p, p + n).
struct Reader {
  const uint8_t* p;
  size_t n, o = 0;
  void need(size_t k) const {
    if (k > n - o) bad("truncated box");
  }
  uint64_t u(int bytes) {
    need(size_t(bytes));
    uint64_t v = 0;
    for (int i = 0; i < bytes; ++i) v = v << 8 | p[o++];
    return v;
  }
  uint8_t u8() { return uint8_t(u(1)); }
  uint16_t u16() { return uint16_t(u(2)); }
  uint32_t u32() { return uint32_t(u(4)); }
  std::string fourcc() {
    need(4);
    std::string s(reinterpret_cast<const char*>(p + o), 4);
    o += 4;
    return s;
  }
  // A NUL-terminated string; an unterminated one ends at the box end (lenient, as readers are).
  std::string cstr() {
    const uint8_t* e = static_cast<const uint8_t*>(std::memchr(p + o, 0, n - o));
    const size_t len = e ? size_t(e - (p + o)) : n - o;
    std::string s(reinterpret_cast<const char*>(p + o), len);
    o += e ? len + 1 : len;
    return s;
  }
};

struct Box {
  std::string type;
  size_t start = 0, header = 0, size = 0;  // absolute in the buffer
  size_t body() const { return start + header; }
  size_t end() const { return start + size; }
};

// The boxes in [b, e) of buf. Size 0 ("to the end") is only valid for a top-level box: inside a
// container it would swallow the boxes we append.
std::vector<Box> boxes(const uint8_t* buf, size_t b, size_t e, bool top = false) {
  std::vector<Box> out;
  while (b < e) {
    if (e - b < 8) bad("truncated box header");
    Reader r{buf + b, e - b};
    Box x;
    x.start = b;
    const uint64_t size32 = r.u32();
    x.type = r.fourcc();
    x.header = 8;
    uint64_t size = size32;
    if (size32 == 1) {
      size = r.u(8);
      x.header = 16;
    } else if (size32 == 0) {
      if (!top) bad("box size 0 inside a container");
      size = e - b;
    }
    if (x.type == "uuid") {
      r.need(16);
      x.header += 16;
    }
    if (size < x.header || size > e - b) bad("bad box size");
    x.size = size_t(size);
    out.push_back(x);
    b += x.size;
  }
  return out;
}

// Big-endian writer with box nesting.
struct Writer {
  std::vector<uint8_t> b;
  void u(uint64_t v, int bytes) {
    for (int i = bytes - 1; i >= 0; --i) b.push_back(uint8_t(v >> (8 * i)));
  }
  void u8(uint8_t v) { u(v, 1); }
  void u16(uint16_t v) { u(v, 2); }
  void u32(uint32_t v) { u(v, 4); }
  void bytes(const uint8_t* p, size_t n) { b.insert(b.end(), p, p + n); }
  void str(const std::string& s, bool nul = true) {
    b.insert(b.end(), s.begin(), s.end());
    if (nul) b.push_back(0);
  }
  // [type]: exactly four bytes, NULs included (types come from untrusted input); never "uuid",
  // whose header this writer does not produce.
  size_t begin(const std::string& type) {
    if (type.size() != 4 || type == "uuid") bad("box type");
    const size_t at = b.size();
    u32(0);
    str(type, false);
    return at;
  }
  size_t begin_full(const std::string& type, uint8_t version, uint32_t flags) {
    const size_t at = begin(type);
    u8(version);
    u(flags, 3);
    return at;
  }
  void end(size_t at) {
    const size_t n = b.size() - at;
    if (n > 0xFFFFFFFFu) bad("box too large");
    for (size_t i = 0; i < 4; ++i) b[at + i] = uint8_t(n >> (24 - 8 * i));
  }
};

struct Extent {
  uint64_t offset = 0, length = 0;
};
struct Loc {
  uint32_t id = 0;
  int method = 0;  // 0 file, 1 idat
  uint16_t dref = 0;
  std::vector<Extent> extents;  // base offset folded in
};
struct Ref {
  std::string type;
  uint32_t from = 0;
  std::vector<uint32_t> to;
};
struct Assoc {
  bool essential = false;
  uint16_t index = 0;  // 1-based in ipco
};
struct Infe {
  uint32_t id = 0;
  std::string type, content_type;
  size_t start = 0, size = 0;  // the box in the input
};

constexpr const char* kXmpMime = "application/rdf+xml";

// The parsed file: top-level layout and the `meta` box.
struct Model {
  const uint8_t* data = nullptr;
  size_t n = 0;
  Box meta;
  uint32_t meta_version_flags = 0;
  std::vector<Box> children;  // of meta
  uint32_t primary = 0;
  std::vector<Loc> locs;
  std::vector<Infe> infes;
  std::vector<Ref> refs;
  std::vector<Box> ipco;  // property boxes, index = position + 1
  Box ipco_box, iprp;
  bool has_iprp = false, has_ipco = false;
  std::map<uint32_t, std::vector<Assoc>> assoc;
  std::vector<uint8_t> idat;

  uint32_t max_id() const {
    uint32_t m = primary;
    for (const auto& l : locs) m = std::max(m, l.id);
    for (const auto& i : infes) m = std::max(m, i.id);
    return m;
  }
  const Infe* infe(uint32_t id) const {
    for (const auto& i : infes)
      if (i.id == id) return &i;
    return nullptr;
  }
  bool is_meta_item(const Infe& i) const {
    return i.type == "Exif" || (i.type == "mime" && i.content_type == kXmpMime);
  }
  std::string colr_type(uint16_t index) const {
    if (index == 0 || index > ipco.size()) return {};
    const Box& b = ipco[index - 1];
    if (b.type != "colr" || b.size - b.header < 4) return {};
    return std::string(reinterpret_cast<const char*>(data + b.body()), 4);
  }
  bool is_icc_prop(uint16_t index) const {
    const std::string t = colr_type(index);
    return t == "prof" || t == "rICC";
  }
};

void parse_iloc(Model& m, const Box& b) {
  Reader r{m.data + b.body(), b.size - b.header};
  const uint8_t version = r.u8();
  r.u(3);
  if (version > 2) bad("iloc version");
  const uint8_t s1 = r.u8(), s2 = r.u8();
  const int off_size = s1 >> 4, len_size = s1 & 15, base_size = s2 >> 4;
  const int index_size = version >= 1 ? (s2 & 15) : 0;
  for (int s : {off_size, len_size, base_size})
    if (s != 0 && s != 4 && s != 8) bad("iloc field size");
  if (index_size != 0) bad("iloc extent_index is not supported");
  const uint32_t count = version < 2 ? r.u16() : r.u32();
  for (uint32_t i = 0; i < count; ++i) {
    Loc l;
    l.id = version < 2 ? r.u16() : r.u32();
    if (version >= 1) l.method = r.u16() & 15;
    if (l.method > 1) bad("iloc construction method");
    l.dref = r.u16();
    const uint64_t base = base_size ? r.u(base_size) : 0;
    const uint16_t extents = r.u16();
    // Each extent takes at least one byte of input unless both sizes are 0: bounded either way.
    if (off_size + len_size == 0 && extents > 1) bad("iloc extents");
    for (uint16_t e = 0; e < extents; ++e) {
      Extent x;
      const uint64_t off = off_size ? r.u(off_size) : 0;
      x.length = len_size ? r.u(len_size) : 0;
      if (off > UINT64_MAX - base) bad("iloc offset overflow");
      x.offset = base + off;
      l.extents.push_back(x);
    }
    m.locs.push_back(std::move(l));
  }
}

void parse_iinf(Model& m, const Box& b) {
  Reader r{m.data + b.body(), b.size - b.header};
  const uint8_t version = r.u8();
  r.u(3);
  const uint32_t count = version == 0 ? r.u16() : r.u32();
  const auto kids = boxes(m.data, b.body() + r.o, b.end());
  if (kids.size() != count) bad("iinf entry count");
  for (const auto& k : kids) {
    if (k.type != "infe") bad("iinf child");
    Reader e{m.data + k.body(), k.size - k.header};
    const uint8_t v = e.u8();
    e.u(3);
    Infe i;
    i.start = k.start;
    i.size = k.size;
    if (v < 2) {
      i.id = e.u16();  // legacy entries: no item type
    } else {
      i.id = v == 2 ? e.u16() : e.u32();
      e.u16();  // protection index
      i.type = e.fourcc();
      e.cstr();  // name
      if (i.type == "mime") i.content_type = e.cstr();
    }
    m.infes.push_back(std::move(i));
  }
}

void parse_iref(Model& m, const Box& b) {
  Reader r{m.data + b.body(), b.size - b.header};
  const uint8_t version = r.u8();
  r.u(3);
  for (const auto& k : boxes(m.data, b.body() + r.o, b.end())) {
    // A reference type is a four-character code; a "uuid" box would be written back without
    // its 16-byte usertype and break the file (fuzz-ga, heif shard 4).
    if (k.type == "uuid") bad("uuid box in iref");
    Reader e{m.data + k.body(), k.size - k.header};
    Ref ref;
    ref.type = k.type;
    ref.from = version == 0 ? e.u16() : e.u32();
    const uint16_t n = e.u16();
    for (uint16_t i = 0; i < n; ++i) ref.to.push_back(version == 0 ? e.u16() : e.u32());
    m.refs.push_back(std::move(ref));
  }
}

void parse_iprp(Model& m, const Box& b) {
  m.iprp = b;
  m.has_iprp = true;
  for (const auto& k : boxes(m.data, b.body(), b.end())) {
    if (k.type == "ipco") {
      if (m.has_ipco) bad("two ipco");
      m.has_ipco = true;
      m.ipco_box = k;
      m.ipco = boxes(m.data, k.body(), k.end());
    } else if (k.type == "ipma") {
      Reader r{m.data + k.body(), k.size - k.header};
      const uint8_t version = r.u8();
      const uint32_t flags = uint32_t(r.u(3));
      const uint32_t count = r.u32();
      for (uint32_t i = 0; i < count; ++i) {
        const uint32_t id = version < 1 ? r.u16() : r.u32();
        const uint8_t n = r.u8();
        auto& list = m.assoc[id];
        for (uint8_t j = 0; j < n; ++j) {
          Assoc a;
          if (flags & 1) {
            const uint16_t v = r.u16();
            a.essential = v >> 15;
            a.index = v & 0x7FFF;
          } else {
            const uint8_t v = r.u8();
            a.essential = v >> 7;
            a.index = v & 0x7F;
          }
          list.push_back(a);
        }
      }
    }
  }
  if (!m.has_ipco) bad("no ipco");
}

Model parse(const uint8_t* data, size_t n) {
  if (n > kHeifMaxBytes) bad("file too large");
  Model m;
  m.data = data;
  m.n = n;
  bool found = false;
  for (const auto& b : boxes(data, 0, n, true)) {
    if (b.type == "moov") bad("image sequences (moov) are not supported");
    if (b.type == "meta") {
      if (found) bad("two meta boxes");
      found = true;
      m.meta = b;
    }
  }
  if (!found) bad("no meta box");
  Reader r{data + m.meta.body(), m.meta.size - m.meta.header};
  m.meta_version_flags = r.u32();
  m.children = boxes(data, m.meta.body() + 4, m.meta.end());
  bool hdlr = false, pitm = false, iloc = false, iinf = false, iref = false, idat = false;
  for (const auto& c : m.children) {
    if (c.type == "hdlr") {
      Reader h{data + c.body(), c.size - c.header};
      h.u32();
      h.u32();  // pre_defined
      if (h.fourcc() != "pict") bad("not an image (hdlr)");
      hdlr = true;
    } else if (c.type == "pitm") {
      Reader p{data + c.body(), c.size - c.header};
      const uint8_t v = p.u8();
      p.u(3);
      m.primary = v == 0 ? p.u16() : p.u32();
      pitm = true;
    } else if (c.type == "iloc") {
      if (iloc) bad("two iloc");
      iloc = true;
      parse_iloc(m, c);
    } else if (c.type == "iinf") {
      if (iinf) bad("two iinf");
      iinf = true;
      parse_iinf(m, c);
    } else if (c.type == "iref") {
      if (iref) bad("two iref");
      iref = true;
      parse_iref(m, c);
    } else if (c.type == "iprp") {
      if (m.has_iprp) bad("two iprp");
      parse_iprp(m, c);
    } else if (c.type == "idat") {
      if (idat) bad("two idat");
      idat = true;
      m.idat.assign(data + c.body(), data + c.end());
    }
  }
  if (!hdlr || !pitm || !iloc || !iinf || !m.has_iprp) {
    bad("missing hdlr, pitm, iloc, iinf or iprp");
  }
  if (!m.infe(m.primary)) bad("primary item has no infe");
  return m;
}

// The bytes of an item, or empty if its location does not resolve within the file.
std::vector<uint8_t> item_data(const Model& m, uint32_t id) {
  for (const auto& l : m.locs) {
    if (l.id != id) continue;
    if (l.dref != 0) return {};
    std::vector<uint8_t> out;
    for (const auto& e : l.extents) {
      const uint8_t* src = l.method == 0 ? m.data : m.idat.data();
      const size_t size = l.method == 0 ? m.n : m.idat.size();
      if (e.offset > size || e.length > size - e.offset) return {};
      if (out.size() + e.length > kHeifMaxBytes) return {};
      out.insert(out.end(), src + e.offset, src + e.offset + e.length);
    }
    return out;
  }
  return {};
}

std::vector<uint32_t> tiles_of(const Model& m, uint32_t id) {
  std::vector<uint32_t> out;
  for (const auto& r : m.refs)
    if (r.type == "dimg" && r.from == id) out.insert(out.end(), r.to.begin(), r.to.end());
  return out;
}

void write_iloc(Writer& w, const std::vector<Loc>& locs) {
  bool wide = false;
  for (const auto& l : locs) wide |= l.id > 0xFFFF;
  const uint8_t version = wide ? 2 : 1;
  const size_t at = w.begin_full("iloc", version, 0);
  w.u8(0x88);  // offset_size 8, length_size 8
  w.u8(0x00);  // base_offset_size 0, index_size 0
  if (version < 2) {
    if (locs.size() > 0xFFFF) bad("too many items");
    w.u16(uint16_t(locs.size()));
  } else {
    w.u32(uint32_t(locs.size()));
  }
  for (const auto& l : locs) {
    if (version < 2)
      w.u16(uint16_t(l.id));
    else
      w.u32(l.id);
    w.u16(uint16_t(l.method));
    w.u16(l.dref);
    if (l.extents.size() > 0xFFFF) bad("too many extents");
    w.u16(uint16_t(l.extents.size()));
    for (const auto& e : l.extents) {
      w.u(e.offset, 8);
      w.u(e.length, 8);
    }
  }
  w.end(at);
}

void write_infe(Writer& w, uint32_t id, const char* type, const char* content_type) {
  const size_t at = w.begin_full("infe", id > 0xFFFF ? 3 : 2, 0);
  if (id > 0xFFFF)
    w.u32(id);
  else
    w.u16(uint16_t(id));
  w.u16(0);  // protection
  w.str(type, false);
  w.str("");  // name
  if (content_type) w.str(content_type);
  w.end(at);
}

}  // namespace

std::vector<uint8_t> heif_item_data(const uint8_t* data, size_t n, uint32_t id) {
  return item_data(parse(data, n), id);
}

HeifMetaInfo heif_read_meta(const uint8_t* data, size_t n) {
  const Model m = parse(data, n);
  HeifMetaInfo info;
  info.primary = m.primary;
  for (const auto& l : m.locs) {
    bool ok = l.dref == 0;
    for (const auto& e : l.extents) {
      const size_t size = l.method == 0 ? m.n : m.idat.size();
      ok &= e.offset <= size && e.length <= size - e.offset;
    }
    info.items += ok;
  }
  for (const auto& [id, list] : m.assoc) {
    for (const auto& a : list) {
      if (!m.is_icc_prop(a.index)) continue;
      info.icc_items.push_back(id);
      if (id == m.primary) {
        const Box& b = m.ipco[a.index - 1];
        info.icc.assign(data + b.body() + 4, data + b.end());
      }
    }
  }
  for (const auto& r : m.refs) {
    if (r.type != "cdsc" || std::find(r.to.begin(), r.to.end(), m.primary) == r.to.end()) continue;
    const Infe* i = m.infe(r.from);
    if (!i) continue;
    const auto d = item_data(m, r.from);
    if (i->type == "Exif" && d.size() >= 4) {
      const uint32_t off =
          uint32_t(d[0]) << 24 | uint32_t(d[1]) << 16 | uint32_t(d[2]) << 8 | uint32_t(d[3]);
      if (off <= d.size() - 4) info.exif_tiff.assign(d.begin() + 4 + off, d.end());
    } else if (i->type == "mime" && i->content_type == kXmpMime) {
      info.xmp.assign(d.begin(), d.end());
    }
  }
  return info;
}

std::vector<uint8_t> heif_attach_meta(const std::vector<uint8_t>& in, const OutputMeta& meta) {
  const Model m = parse(in.data(), in.size());

  // Items to drop (existing Exif/XMP) and the new ones.
  std::set<uint32_t> dropped;
  for (const auto& i : m.infes)
    if (m.is_meta_item(i)) dropped.insert(i.id);
  if (dropped.count(m.primary)) bad("primary item is metadata");
  uint32_t next = m.max_id();
  if (next >= 0xFFFFFFFDu) bad("item ids exhausted");
  const uint32_t exif_id = meta.exif.empty() ? 0 : ++next;
  const uint32_t xmp_id = meta.xmp.empty() ? 0 : ++next;

  std::vector<uint8_t> idat = m.idat;
  std::vector<Loc> locs;
  for (const auto& l : m.locs) {
    if (dropped.count(l.id)) continue;
    // File offsets are moved when the meta box grows: each must lie within this file, so the
    // shift below cannot overflow (fuzz-ga: an offset near INT64_MAX was signed overflow).
    if (l.method == 0)
      for (const auto& e : l.extents)
        if (e.offset > in.size() || e.length > in.size() - e.offset)
          bad("item data outside the file");
    locs.push_back(l);
  }
  auto add_item = [&](uint32_t id, const std::vector<uint8_t>& head, const uint8_t* p, size_t n) {
    Loc l;
    l.id = id;
    l.method = 1;
    l.extents.push_back({idat.size(), head.size() + n});
    idat.insert(idat.end(), head.begin(), head.end());
    idat.insert(idat.end(), p, p + n);
    locs.push_back(l);
  };
  if (exif_id) {
    const std::vector<uint8_t> head = {0, 0, 0, 6, 'E', 'x', 'i', 'f', 0, 0};
    add_item(exif_id, head, meta.exif.data(), meta.exif.size());
  }
  if (xmp_id) {
    add_item(xmp_id, {}, reinterpret_cast<const uint8_t*>(meta.xmp.data()), meta.xmp.size());
  }

  // References: drop those of dropped items, add cdsc to the primary item.
  std::vector<Ref> refs;
  for (const auto& r : m.refs) {
    if (dropped.count(r.from)) continue;
    Ref x = r;
    x.to.erase(
        std::remove_if(x.to.begin(), x.to.end(), [&](uint32_t t) { return dropped.count(t); }),
        x.to.end());
    if (!x.to.empty()) refs.push_back(std::move(x));
  }
  for (uint32_t id : {exif_id, xmp_id})
    if (id) refs.push_back({"cdsc", id, {m.primary}});

  // Properties: the ICC profile as a new colr (prof) on the primary item and its tiles.
  auto assoc = m.assoc;
  for (uint32_t id : dropped) assoc.erase(id);
  const uint16_t icc_index = uint16_t(m.ipco.size() + 1);
  if (!meta.icc.empty()) {
    if (icc_index > 0x7FFF) bad("too many properties");
    std::vector<uint32_t> targets = tiles_of(m, m.primary);
    targets.push_back(m.primary);
    for (uint32_t id : targets) {
      auto& list = assoc[id];
      list.erase(std::remove_if(list.begin(), list.end(),
                                [&](const Assoc& a) { return m.is_icc_prop(a.index); }),
                 list.end());
      if (list.size() >= 255) bad("too many associations");
      list.push_back({false, icc_index});
    }
  }

  auto build = [&](int64_t delta) {
    // File offsets behind the old meta box move by delta; none may point into it.
    std::vector<Loc> moved = locs;
    for (auto& l : moved) {
      if (l.method != 0) continue;
      for (auto& e : l.extents) {
        if (e.offset >= m.meta.end())
          e.offset = uint64_t(int64_t(e.offset) + delta);
        else if (e.offset + e.length > m.meta.start && e.length)
          bad("item data inside meta");
      }
    }
    bool wide = false;
    for (const auto& r : refs) {
      wide |= r.from > 0xFFFF;
      for (uint32_t t : r.to) wide |= t > 0xFFFF;
    }
    bool wide_ids = false, wide_index = false;
    for (const auto& [id, list] : assoc) {
      wide_ids |= id > 0xFFFF;
      for (const auto& a : list) wide_index |= a.index > 0x7F;
    }

    Writer w;
    const size_t meta_at = w.begin("meta");
    w.u32(m.meta_version_flags);
    bool wrote_iref = false, wrote_idat = false;
    auto write_iref = [&] {
      if (refs.empty()) return;
      const size_t at = w.begin_full("iref", wide ? 1 : 0, 0);
      for (const auto& r : refs) {
        if (r.to.size() > 0xFFFF) bad("too many references");
        const size_t rat = w.begin(r.type);
        if (wide)
          w.u32(r.from);
        else
          w.u16(uint16_t(r.from));
        w.u16(uint16_t(r.to.size()));
        for (uint32_t t : r.to) {
          if (wide)
            w.u32(t);
          else
            w.u16(uint16_t(t));
        }
        w.end(rat);
      }
      w.end(at);
    };
    auto write_idat = [&] {
      if (idat.empty()) return;
      const size_t at = w.begin("idat");
      w.bytes(idat.data(), idat.size());
      w.end(at);
    };
    for (const auto& c : m.children) {
      if (c.type == "iloc") {
        write_iloc(w, moved);
      } else if (c.type == "iinf") {
        size_t count = 0;
        for (const auto& i : m.infes) count += !dropped.count(i.id);
        count += size_t(exif_id != 0) + size_t(xmp_id != 0);
        const bool v1 = count > 0xFFFF;
        const size_t at = w.begin_full("iinf", v1 ? 1 : 0, 0);
        if (v1)
          w.u32(uint32_t(count));
        else
          w.u16(uint16_t(count));
        for (const auto& i : m.infes)
          if (!dropped.count(i.id)) w.bytes(in.data() + i.start, i.size);
        if (exif_id) write_infe(w, exif_id, "Exif", nullptr);
        if (xmp_id) write_infe(w, xmp_id, "mime", kXmpMime);
        w.end(at);
      } else if (c.type == "iref") {
        write_iref();
        wrote_iref = true;
      } else if (c.type == "idat") {
        write_idat();
        wrote_idat = true;
      } else if (c.type == "iprp") {
        const size_t at = w.begin("iprp");
        const size_t co = w.begin("ipco");
        for (const auto& p : m.ipco) w.bytes(in.data() + p.start, p.size);
        if (!meta.icc.empty()) {
          const size_t colr = w.begin("colr");
          w.str("prof", false);
          w.bytes(meta.icc.data(), meta.icc.size());
          w.end(colr);
        }
        w.end(co);
        const size_t ma = w.begin_full("ipma", wide_ids ? 1 : 0, wide_index ? 1 : 0);
        size_t entries = 0;
        for (const auto& kv : assoc) entries += !kv.second.empty();
        w.u32(uint32_t(entries));
        for (const auto& [id, list] : assoc) {  // std::map: increasing item_ID
          if (list.empty()) continue;
          if (wide_ids)
            w.u32(id);
          else
            w.u16(uint16_t(id));
          w.u8(uint8_t(list.size()));
          for (const auto& a : list) {
            if (wide_index)
              w.u16(uint16_t(a.essential << 15 | a.index));
            else
              w.u8(uint8_t(a.essential << 7 | a.index));
          }
        }
        w.end(ma);
        w.end(at);
      } else {
        w.bytes(in.data() + c.start, c.size);
      }
    }
    if (!wrote_iref) write_iref();
    if (!wrote_idat) write_idat();
    w.end(meta_at);
    return std::move(w.b);
  };

  // iloc fields are fixed-width, so the size does not depend on delta.
  const auto probe = build(0);
  const int64_t delta = int64_t(probe.size()) - int64_t(m.meta.size);
  const auto meta_box = build(delta);
  if (meta_box.size() != probe.size()) bad("internal size mismatch");

  std::vector<uint8_t> out;
  out.reserve(in.size() + meta_box.size());
  out.insert(out.end(), in.data(), in.data() + m.meta.start);
  out.insert(out.end(), meta_box.begin(), meta_box.end());
  out.insert(out.end(), in.data() + m.meta.end(), in.data() + in.size());
  return out;
}

}  // namespace enh
