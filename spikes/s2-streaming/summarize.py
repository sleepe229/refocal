"""Markdown tables from out/matrix/*.json (s2_stream --stats)."""
import json, glob, os, sys

d = sys.argv[1] if len(sys.argv) > 1 else "out/matrix"
rows = []
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    s = json.load(open(f)); t = s["times_s"]; n = s["num"]; sp = s["stage_peak_mb"]
    name = os.path.basename(f)[:-5]
    sr = n["to_sr_done_s"]
    io_bg = t.get("band_write_total", 0)
    rows.append(dict(
        run=name, peak=s["peak_rss_mb"], sr_peak=sp.get("sr_banded", 0),
        drv=sp.get("gpu_init", 0), enc_peak=max(sp.get("encode_jpeg", 0), sp.get("encode_png", 0)),
        total=n["total_s"], sr=sr, decode=t.get("decode", 0) + t.get("fast2_downscale", 0),
        infer=t.get("infer", 0), prepost=t.get("prep", 0) + t.get("post", 0) + t.get("downscale_x2", 0),
        preview=t.get("preview", 0), bw=io_bg, lz4=t.get("lz4_compress", 0),
        stall=t.get("io_stall", 0), jpg=t.get("encode_jpeg", 0), jpg_rd=t.get("encode_jpeg_read", 0),
        png=t.get("encode_png", 0), store=n["bandstore_bytes"] / 1e6, raw=n["raw_bytes"] / 1e6,
        spmp=sr / n["input_mp"], io_share=100 * io_bg / sr, stall_share=100 * t.get("io_stall", 0) / sr,
        bands=s["geometry"]["bands"], jpg_mb=n.get("encode_jpeg_bytes", 0) / 1e6,
        png_mb=n.get("encode_png_bytes", 0) / 1e6,
        drm=n.get("drm_resident_peak_mb", float("nan")), comb=n.get("rss_plus_drm_peak_mb", float("nan"))))

print("| run | peak RSS MB | SR stage peak | GPU-init RSS | total s | SR s | s/MP in | infer | prep+post | preview | band write (bg) | I/O stall | I/O share bg/stall % | JPEG s | PNG s | BandStore MB | bands |")
print("|" + "---|" * 17)
for r in rows:
    print(f"| {r['run']} | {r['peak']:.0f} | {r['sr_peak']:.0f} | {r['drv']:.0f} | {r['total']:.1f} | {r['sr']:.1f} | "
          f"{r['spmp']:.2f} | {r['infer']:.1f} | {r['prepost']:.2f} | {r['preview']:.2f} | {r['bw']:.2f} | "
          f"{r['stall']:.2f} | {r['io_share']:.1f} / {r['stall_share']:.1f} | {r['jpg']:.1f} | "
          f"{r['png'] if r['png'] else '—'} | {r['store']:.0f} | {r['bands']} |")
print()
print("| run | lz4 compress s | JPEG MB | PNG MB | JPEG band-read s | encode peak MB | iGPU DRM resident MB | RSS+DRM MB |")
print("|---|---|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r['run']} | {r['lz4']:.2f} | {r['jpg_mb']:.1f} | {r['png_mb']:.1f} | {r['jpg_rd']:.2f} | {r['enc_peak']:.0f} | {r['drm']:.0f} | {r['comb']:.0f} |")
