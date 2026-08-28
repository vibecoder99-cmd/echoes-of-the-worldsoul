#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Echoes of the Worldsoul -- Minimal single-file MPQ writer/reader
#
# Packages one file into a minimal, uncompressed, single-hash-slot MPQ v1
# archive -- the exact shape this project's Patch-4.MPQ uses (one file,
# no compression, no locale variants). This is deliberately NOT a
# general-purpose MPQ library: it contains no compression codecs, no
# multi-file support, and no listfile handling. It exists to package the
# output of patch_item_dbc.py (or any other single file) reproducibly,
# without depending on a third-party MPQ editor.
#
# Extracted from this project's original ad hoc create_mpq() helper
# (previously duplicated in two untracked, personal-path-hardcoded
# scripts), with all client-specific assumptions removed and a
# corresponding reader added for verification. See
# docs/e2j5h-evidence/ for unrelated historical material -- this file
# has no connection to that work.
#
# Contains no DBC-mutation logic. Pair with patch_item_dbc.py for the
# DBC transformation step; see build_patch_mpq.py for a thin
# orchestration example that keeps both steps independently testable.
#
# Usage:
#   python mpq_writer.py pack <internal_path> <input_file> <output.mpq>
#   python mpq_writer.py unpack <internal_path> <input.mpq> <output_file>

import struct
import sys


def _build_crypt_table():
    t = [0] * 0x500
    seed = 0x00100001
    for i in range(0x100):
        idx = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t[idx] = t1 | (seed & 0xFFFF)
            idx += 0x100
    return t


_CT = _build_crypt_table()


def _hash(s, kind):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for c in s.upper():
        ch = ord(c)
        s1 = (_CT[(kind << 8) + ch] ^ (s1 + s2)) & 0xFFFFFFFF
        s2 = (ch + s1 + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return s1


def _encrypt(data, key):
    # StormLib EncryptMpqBlock: key2 state advances using the PLAINTEXT
    # value (captured before the XOR), not the ciphertext being written.
    s1, s2 = key & 0xFFFFFFFF, 0xEEEEEEEE
    out = bytearray(data)
    for i in range(0, len(data), 4):
        s2 = (s2 + _CT[0x400 + (s1 & 0xFF)]) & 0xFFFFFFFF
        plain = struct.unpack_from('<I', data, i)[0]
        cipher = (plain ^ (s1 + s2)) & 0xFFFFFFFF
        struct.pack_into('<I', out, i, cipher)
        s1 = ((((~s1) & 0xFFFFFFFF) << 0x15) + 0x11111111 | (s1 >> 0x0B)) & 0xFFFFFFFF
        s2 = (plain + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return bytes(out)


def _decrypt(data, key):
    # StormLib DecryptMpqBlock: key2 state advances using the recovered
    # PLAINTEXT value (computed by the XOR), not the ciphertext input.
    # This is NOT the same update as _encrypt's -- an earlier attempt to
    # share one "symmetric" routine for both directions silently produced
    # wrong output on decrypt; see docs/distribution/E2J16-MPQ-DBC-PROVENANCE.md
    # in the WSL development repo for the full note.
    s1, s2 = key & 0xFFFFFFFF, 0xEEEEEEEE
    out = bytearray(data)
    for i in range(0, len(data), 4):
        s2 = (s2 + _CT[0x400 + (s1 & 0xFF)]) & 0xFFFFFFFF
        cipher = struct.unpack_from('<I', data, i)[0]
        plain = (cipher ^ (s1 + s2)) & 0xFFFFFFFF
        struct.pack_into('<I', out, i, plain)
        s1 = ((((~s1) & 0xFFFFFFFF) << 0x15) + 0x11111111 | (s1 >> 0x0B)) & 0xFFFFFFFF
        s2 = (plain + s2 + (s2 << 5) + 3) & 0xFFFFFFFF
    return bytes(out)


_HT_KEY = _hash("(hash table)", 3)
_BT_KEY = _hash("(block table)", 3)

HDR_SZ = 32
HASH_N = 16


def write_single_file_mpq(out_path, internal_path, file_data):
    """Write a minimal single-file, uncompressed MPQ v1 archive.

    out_path: destination archive path.
    internal_path: the client-facing path the game will look up inside
        the archive (e.g. "DBFilesClient\\Item.dbc").
    file_data: raw bytes to store, uncompressed, as a single unit.

    Deterministic: identical (internal_path, file_data) always produces
    a byte-identical archive (no timestamps, no padding, no compression).
    """
    ha = _hash(internal_path, 1)
    hb = _hash(internal_path, 2)
    slot = _hash(internal_path, 0) % HASH_N

    f_off = HDR_SZ
    f_sz = len(file_data)
    ht_off = f_off + f_sz
    bt_off = ht_off + HASH_N * 16
    arc_sz = bt_off + 16

    hdr = struct.pack('<4sIIHHIIII',
                       b'MPQ\x1a', HDR_SZ, arc_sz,
                       0, 3,
                       ht_off, bt_off, HASH_N, 1)

    ht = bytearray(HASH_N * 16)
    for i in range(HASH_N):
        struct.pack_into('<IIHHI', ht, i * 16,
                          0xFFFFFFFF, 0xFFFFFFFF, 0xFFFF, 0xFFFF, 0xFFFFFFFF)
    struct.pack_into('<IIHHI', ht, slot * 16, ha, hb, 0, 0, 0)
    ht_enc = _encrypt(bytes(ht), _HT_KEY)

    bt_enc = _encrypt(struct.pack('<IIII', f_off, f_sz, f_sz, 0x81000000), _BT_KEY)

    with open(out_path, 'wb') as f:
        f.write(hdr)
        f.write(file_data)
        f.write(ht_enc)
        f.write(bt_enc)

    return arc_sz


def read_single_file_mpq(in_path, internal_path):
    """Read back the single file from a minimal single-file MPQ v1 archive
    of the exact shape write_single_file_mpq() produces. Returns the raw
    file bytes, or raises ValueError if the archive doesn't match this
    narrow format or the internal path isn't found at its expected slot.
    """
    with open(in_path, 'rb') as f:
        data = f.read()

    magic, hdr_sz, arc_sz, fmt_ver, sector_shift, ht_off, bt_off, ht_n, bt_n = \
        struct.unpack_from('<4sIIHHIIII', data, 0)

    if magic != b'MPQ\x1a':
        raise ValueError(f"not an MPQ archive (magic={magic!r})")
    if len(data) != arc_sz:
        raise ValueError(f"archive size mismatch: file is {len(data)} bytes, header claims {arc_sz}")

    ha = _hash(internal_path, 1)
    hb = _hash(internal_path, 2)
    slot = _hash(internal_path, 0) % ht_n

    ht_enc = data[ht_off:ht_off + ht_n * 16]
    ht = _decrypt(ht_enc, _HT_KEY)
    e_ha, e_hb, locale, platform, block_idx = struct.unpack_from('<IIHHI', ht, slot * 16)

    if e_ha != ha or e_hb != hb:
        raise ValueError(f"internal path {internal_path!r} not found at expected hash-table slot {slot}")
    if block_idx >= bt_n:
        raise ValueError(f"hash table points at out-of-range block index {block_idx}")

    bt_enc = data[bt_off:bt_off + bt_n * 16]
    bt = _decrypt(bt_enc, _BT_KEY)
    f_off, c_size, u_size, flags = struct.unpack_from('<IIII', bt, block_idx * 16)

    if not (flags & 0x80000000):
        raise ValueError(f"block {block_idx} MPQ_FILE_EXISTS flag not set (flags={flags:#x})")
    if flags & 0x00000200:
        raise ValueError("compressed files are not supported by this minimal reader")
    if c_size != u_size:
        raise ValueError(f"compressed size {c_size} != uncompressed size {u_size}, but no compression flag set")

    return data[f_off:f_off + u_size]


def archive_file_count(in_path):
    """Return (occupied_hash_slots, block_table_entries) for a minimal
    single-file MPQ v1 archive -- a structural sanity check that exactly
    one file is present and nothing unexpected was added."""
    with open(in_path, 'rb') as f:
        data = f.read()
    magic, hdr_sz, arc_sz, fmt_ver, sector_shift, ht_off, bt_off, ht_n, bt_n = \
        struct.unpack_from('<4sIIHHIIII', data, 0)
    ht_enc = data[ht_off:ht_off + ht_n * 16]
    ht = _decrypt(ht_enc, _HT_KEY)
    count = 0
    for i in range(ht_n):
        e_ha, e_hb, locale, platform, block_idx = struct.unpack_from('<IIHHI', ht, i * 16)
        if block_idx != 0xFFFFFFFF:
            count += 1
    return count, bt_n


if __name__ == '__main__':
    if len(sys.argv) != 5 or sys.argv[1] not in ('pack', 'unpack'):
        print("Usage:")
        print("  python mpq_writer.py pack <internal_path> <input_file> <output.mpq>")
        print("  python mpq_writer.py unpack <internal_path> <input.mpq> <output_file>")
        sys.exit(1)

    mode, internal_path, in_path, out_path = sys.argv[1:5]

    if mode == 'pack':
        with open(in_path, 'rb') as f:
            data = f.read()
        size = write_single_file_mpq(out_path, internal_path, data)
        print(f"Packed {len(data)} bytes as {internal_path!r} -> {out_path} ({size} bytes)")
    else:
        data = read_single_file_mpq(in_path, internal_path)
        with open(out_path, 'wb') as f:
            f.write(data)
        print(f"Unpacked {internal_path!r} from {in_path} -> {out_path} ({len(data)} bytes)")
