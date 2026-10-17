#!/usr/bin/env python3
"""Checks a HEIC saved by the app (FR-EXP-002, e2e): HeifWriter's image plus what the core adds.

- the primary item and every tile it references resolve to bytes inside the file;
- an XMP item with the AI marker (FR-META-004) and an Exif item (if --exif), both cdsc -> primary;
- a colr prof property with a valid ICC header on the primary item and its tiles (if --icc);
- optionally the file decodes with pillow-heif (libheif), and its ICC is the one written.

Usage: check_heic.py FILE [--icc] [--exif]
"""
import struct
import sys

MARKER = b"compositeWithTrainedAlgorithmicMedia"


def boxes(d, b, e):
    while b < e:
        size, typ = struct.unpack(">I4s", d[b:b + 8])
        hdr = 8
        if size == 1:
            size = struct.unpack(">Q", d[b + 8:b + 16])[0]
            hdr = 16
        elif size == 0:
            size = e - b
        assert 8 <= size <= e - b, f"bad box {typ} at {b}"
        yield typ.decode("latin1"), b + hdr, b + size
        b += size


def u(d, o, n):
    return int.from_bytes(d[o:o + n], "big"), o + n


def main():
    path, flags = sys.argv[1], set(sys.argv[2:])
    d = open(path, "rb").read()
    top = {t: (b, e) for t, b, e in boxes(d, 0, len(d))}
    assert "meta" in top and "moov" not in top, f"top-level boxes: {list(top)}"
    mb, me = top["meta"]
    kids = {t: (b, e) for t, b, e in boxes(d, mb + 4, me)}

    b, _ = kids["pitm"]
    v = d[b]
    primary, _ = u(d, b + 4, 2 if v == 0 else 4)

    infe = {}
    b, e = kids["iinf"]
    v = d[b]
    o = b + 4 + (2 if v == 0 else 4)
    for t, ib, ie in boxes(d, o, e):
        iv = d[ib]
        item, p = u(d, ib + 4, 2 if iv == 2 else 4)
        p += 2
        typ = d[p:p + 4].decode("latin1")
        p += 4
        p = d.index(b"\0", p) + 1
        ctype = d[p:d.index(b"\0", p)].decode() if typ == "mime" else ""
        infe[item] = (typ, ctype)

    refs = []
    if "iref" in kids:
        b, e = kids["iref"]
        v = d[b]
        w = 2 if v == 0 else 4
        for t, rb, re_ in boxes(d, b + 4, e):
            frm, p = u(d, rb, w)
            n, p = u(d, p, 2)
            to = []
            for _ in range(n):
                x, p = u(d, p, w)
                to.append(x)
            refs.append((t, frm, to))

    idat = d[slice(*kids["idat"])] if "idat" in kids else b""
    locs = {}
    b, e = kids["iloc"]
    v = d[b]
    p = b + 4
    s1, s2 = d[p], d[p + 1]
    p += 2
    osz, lsz, bsz, isz = s1 >> 4, s1 & 15, s2 >> 4, (s2 & 15) if v else 0
    n, p = u(d, p, 2 if v < 2 else 4)
    for _ in range(n):
        item, p = u(d, p, 2 if v < 2 else 4)
        method = 0
        if v:
            method, p = u(d, p, 2)
            method &= 15
        _, p = u(d, p, 2)
        base, p = u(d, p, bsz)
        ext, p = u(d, p, 2)
        data = b""
        for _ in range(ext):
            _, p = u(d, p, isz)
            off, p = u(d, p, osz)
            ln, p = u(d, p, lsz)
            src = d if method == 0 else idat
            assert base + off + ln <= len(src), f"item {item} outside the file"
            data += src[base + off:base + off + ln]
        locs[item] = data

    tiles = [x for t, f, to in refs if t == "dimg" and f == primary for x in to]
    for item in [primary] + tiles:
        if infe[item][0] != "grid":
            assert locs.get(item), f"item {item} has no data"
    print(f"primary {primary} ({infe[primary][0]}), {len(tiles)} tiles, items {sorted(infe)}")

    described = {f: infe[f] for t, f, to in refs if t == "cdsc" and primary in to}
    xmp = [locs[f] for f, (t, c) in described.items() if t == "mime" and c == "application/rdf+xml"]
    assert xmp and MARKER in xmp[0], "no XMP AI marker"
    print("XMP AI marker: ok")
    exif = [locs[f] for f, (t, c) in described.items() if t == "Exif"]
    if "--exif" in flags:
        assert exif, "no Exif item"
        off = int.from_bytes(exif[0][:4], "big")
        assert exif[0][4 + off:4 + off + 2] in (b"II", b"MM"), "Exif item is not TIFF"
        print("Exif: ok")

    b, e = top["meta"]
    ib, ie = kids["iprp"]
    props, assoc = [], {}
    for t, pb, pe in boxes(d, ib, ie):
        if t == "ipco":
            props = list(boxes(d, pb, pe))
        elif t == "ipma":
            v, fl = d[pb], int.from_bytes(d[pb + 1:pb + 4], "big")
            n, p = u(d, pb + 4, 4)
            for _ in range(n):
                item, p = u(d, p, 2 if v < 1 else 4)
                k = d[p]
                p += 1
                for _ in range(k):
                    a, p = u(d, p, 2 if fl & 1 else 1)
                    assoc.setdefault(item, []).append(a & (0x7FFF if fl & 1 else 0x7F))
    icc_on = [i for i, ix in assoc.items()
              for x in ix if props[x - 1][0] == "colr" and d[props[x - 1][1]:props[x - 1][1] + 4] == b"prof"]
    if "--icc" in flags:
        assert primary in icc_on and all(t in icc_on for t in tiles), f"prof colr on {icc_on}"
        x = [x for x in assoc[primary] if props[x - 1][0] == "colr" and d[props[x - 1][1]:props[x - 1][1] + 4] == b"prof"][0]
        icc = d[props[x - 1][1] + 4:props[x - 1][2]]
        assert icc[36:40] == b"acsp" and int.from_bytes(icc[:4], "big") == len(icc), "bad ICC"
        print(f"ICC on primary and tiles: ok ({len(icc)} bytes)")
    else:
        icc = None

    try:
        import pillow_heif
    except ImportError:
        print("pillow-heif not installed: decode not checked")
        return
    img = pillow_heif.open_heif(path)
    assert img.size[0] > 0 and len(img.data) > 0
    if icc is not None:
        assert img.info.get("icc_profile") == icc, "libheif reads another ICC"
    print(f"libheif decodes {img.size[0]}x{img.size[1]}" + (", same ICC" if icc else ""))


if __name__ == "__main__":
    main()
