#!/usr/bin/env python3
"""Extract the first icon group from a Windows .exe into an .ico file.

Usage: extract_icon.py GAME.exe OUT.ico
"""
import struct
import sys

RT_ICON, RT_GROUP_ICON = 3, 14


def main(exe_path, ico_path):
    data = open(exe_path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    rsrc_rva = struct.unpack_from("<I", data, opt + (112 if magic == 0x20B else 96) + 2 * 8)[0]

    sections = []
    for i in range(nsec):
        s = pe + 24 + opt_size + i * 40
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, s + 8)
        sections.append((va, max(vsize, rawsize), rawptr))

    def off(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError("RVA not in any section")

    base = off(rsrc_rva)

    def entries(dir_off):
        named, ids = struct.unpack_from("<HH", data, dir_off + 12)
        for i in range(named + ids):
            name, target = struct.unpack_from("<II", data, dir_off + 16 + i * 8)
            yield name, target

    def first_leaf(target):
        # Descend through subdirectories (name -> language) to the data entry.
        while target & 0x80000000:
            target = next(entries(base + (target & 0x7FFFFFFF)))[1]
        rva, size = struct.unpack_from("<II", data, base + target)
        return data[off(rva):off(rva) + size]

    types = dict(entries(base))
    icons = {}
    for name, target in entries(base + (types[RT_ICON] & 0x7FFFFFFF)):
        icons[name] = first_leaf(target)
    group = first_leaf(next(entries(base + (types[RT_GROUP_ICON] & 0x7FFFFFFF)))[1])

    count = struct.unpack_from("<H", group, 4)[0]
    header = struct.pack("<HHH", 0, 1, count)
    dir_entries, images = b"", b""
    offset = 6 + 16 * count
    for i in range(count):
        w, h, colors, res, planes, bpp, size, icon_id = struct.unpack_from("<BBBBHHIH", group, 6 + i * 14)
        img = icons[icon_id]
        dir_entries += struct.pack("<BBBBHHII", w, h, colors, res, planes, bpp, len(img), offset)
        images += img
        offset += len(img)
    with open(ico_path, "wb") as f:
        f.write(header + dir_entries + images)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
