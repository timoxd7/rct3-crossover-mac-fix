#!/usr/bin/env python3
"""Write a minimal Windows .lnk shortcut (MS-SHLLINK) without needing Windows.

Usage: make_lnk.py OUT.lnk TARGET_WINDOWS_PATH WORKING_DIR [DESCRIPTION]
"""
import struct
import sys
import uuid


def counted_utf16(s):
    return struct.pack("<H", len(s)) + s.encode("utf-16-le")


def make_lnk(target, workdir, description):
    # HasLinkInfo | HasName | HasWorkingDir | HasIconLocation | IsUnicode
    flags = 0x02 | 0x04 | 0x10 | 0x40 | 0x80
    header = struct.pack(
        "<I16sIIQQQIiIHHII",
        0x4C,
        uuid.UUID("00021401-0000-0000-C000-000000000046").bytes_le,
        flags,
        0x20,          # FILE_ATTRIBUTE_ARCHIVE
        0, 0, 0,       # creation/access/write time
        0,             # file size
        0,             # icon index
        1,             # SW_SHOWNORMAL
        0, 0, 0, 0,    # hotkey, reserved
    )

    volume_id = struct.pack("<IIII", 0x11, 3, 0, 0x10) + b"\0"  # DRIVE_FIXED, empty label
    base_path = target.encode("cp1252") + b"\0"
    link_info_header = 0x1C
    volume_off = link_info_header
    base_off = volume_off + len(volume_id)
    suffix_off = base_off + len(base_path)
    link_info_size = suffix_off + 1
    link_info = struct.pack(
        "<IIIIIII",
        link_info_size, link_info_header,
        1,             # VolumeIDAndLocalBasePath
        volume_off, base_off,
        0,             # no network link
        suffix_off,
    ) + volume_id + base_path + b"\0"

    strings = (
        counted_utf16(description)
        + counted_utf16(workdir)
        + counted_utf16(target)  # icon location
    )
    return header + link_info + strings + b"\0\0\0\0"


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out, target, workdir = sys.argv[1:4]
    desc = sys.argv[4] if len(sys.argv) > 4 else ""
    with open(out, "wb") as f:
        f.write(make_lnk(target, workdir, desc))
