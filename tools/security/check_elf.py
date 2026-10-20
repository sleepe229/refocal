#!/usr/bin/env python3
"""SEC-INP-003: checks the hardening of the native libraries in an APK (pr.yml).

Every lib/*/*.so in APK must be position-independent (ET_DYN) with a non-executable stack, and,
if it has relocations, a GNU_RELRO segment and bind now (DT_FLAGS BIND_NOW or DT_FLAGS_1 NOW).
Flutter's libapp.so (the Dart AOT snapshot) has none: nothing for RELRO to protect. Refocal's
own core, libenh.so, must also use the stack protector (__stack_chk_fail) and _FORTIFY_SOURCE
(__*_chk functions). The NDK gives all of this by default; this keeps a toolchain change from
dropping it unnoticed.

    tools/security/check_elf.py APK
"""

import re
import struct
import sys
import zipfile

PT_DYNAMIC, PT_GNU_STACK, PT_GNU_RELRO = 2, 0x6474E551, 0x6474E552
DT_FLAGS, DT_FLAGS_1 = 30, 0x6FFFFFFB
DT_RELOCS = {7, 17, 23}  # DT_RELA, DT_REL, DT_JMPREL
DF_BIND_NOW, DF_1_NOW = 0x8, 0x1


def problems(name: str, d: bytes) -> list[str]:
    if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
        return [f"{name}: not a 64-bit little-endian ELF"]
    out = []
    (e_type,) = struct.unpack_from("<H", d, 16)
    if e_type != 3:
        out.append(f"{name}: not position-independent (e_type {e_type})")
    (phoff,) = struct.unpack_from("<Q", d, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
    relro = now = relocs = False
    stack_exec = True  # no PT_GNU_STACK: the loader may make the stack executable
    for i in range(phnum):
        p_type, p_flags, p_offset, _, _, p_filesz, _, _ = struct.unpack_from(
            "<IIQQQQQQ", d, phoff + i * phentsize
        )
        if p_type == PT_GNU_RELRO:
            relro = True
        elif p_type == PT_GNU_STACK:
            stack_exec = bool(p_flags & 1)
        elif p_type == PT_DYNAMIC:
            for j in range(0, p_filesz, 16):
                tag, val = struct.unpack_from("<qQ", d, p_offset + j)
                relocs |= tag in DT_RELOCS
                if (tag == DT_FLAGS and val & DF_BIND_NOW) or (
                    tag == DT_FLAGS_1 and val & DF_1_NOW
                ):
                    now = True
    if relocs and not relro:
        out.append(f"{name}: no RELRO")
    if relocs and not now:
        out.append(f"{name}: no BIND_NOW")
    if stack_exec:
        out.append(f"{name}: executable stack")
    if name.endswith("/libenh.so"):
        if b"__stack_chk_fail" not in d:
            out.append(f"{name}: no stack protector")
        if not re.search(rb"__[a-z_]+_chk\x00", d):
            out.append(f"{name}: no _FORTIFY_SOURCE")
    return out


def main(apk: str) -> int:
    found = []
    with zipfile.ZipFile(apk) as z:
        libs = [n for n in z.namelist() if re.fullmatch(r"lib/[^/]+/[^/]+\.so", n)]
        if not any(n.endswith("/libenh.so") for n in libs):
            found.append("no libenh.so in the APK")
        for n in libs:
            found += problems(n, z.read(n))
    for p in found:
        print(f"::error::{p}")
    if not found:
        print(f"{len(libs)} libraries hardened")
    return 1 if found else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
