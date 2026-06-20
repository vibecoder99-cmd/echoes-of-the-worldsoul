#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Echoes of the Worldsoul -- Item.dbc Patch Script
#
# Inserts the two custom item entries (Worldsoul Echo Fragment 900010
# and Worldsoul Residue 900011) into a vanilla WoW 3.3.5a Item.dbc
# (client build 12340).
#
# Records are inserted at the correct sorted position within the
# record region of the DBC file. The file is never modified in place;
# output is always written to a separate file.
#
# After writing, the script performs a mandatory self-check:
#   - Header record count matches original + 2
#   - Output file size matches the header calculation exactly
#   - Both new entries can be re-parsed at their correct offsets
#   - The string block is byte-for-byte unchanged
#
# Usage:
#   python patch_item_dbc.py <input_Item.dbc> <output_Item.dbc>

import struct
import sys
import os
import bisect

HEADER_SIZE = 20
HEADER_FMT  = '<4sIIII'   # magic, record_count, field_count, record_size, string_block_size

EXPECTED_FIELD_COUNT = 8
EXPECTED_RECORD_SIZE = 32  # 8 fields x 4 bytes = 32

# Exact record bytes verified against a working patched 3.3.5a (build 12340) client.
# Field layout (all little-endian uint32 / int32):
#   entry, class, subclass, SoundOverrideSubclass, Material,
#   DisplayInfoID, InventoryType, SheatheType
NEW_RECORDS = [
    (900010, bytes([
        0xAA, 0xBB, 0x0D, 0x00,   # entry          = 900010
        0x0F, 0x00, 0x00, 0x00,   # class          = 15  (Quest)
        0x00, 0x00, 0x00, 0x00,   # subclass       = 0
        0xFF, 0xFF, 0xFF, 0xFF,   # SoundOverride  = -1
        0xFF, 0xFF, 0xFF, 0xFF,   # Material       = -1
        0xCB, 0xD7, 0x00, 0x00,   # DisplayInfoID  = 55243
        0x00, 0x00, 0x00, 0x00,   # InventoryType  = 0
        0x00, 0x00, 0x00, 0x00,   # SheatheType    = 0
    ])),
    (900011, bytes([
        0xAB, 0xBB, 0x0D, 0x00,   # entry          = 900011
        0x0F, 0x00, 0x00, 0x00,   # class          = 15  (Quest)
        0x00, 0x00, 0x00, 0x00,   # subclass       = 0
        0xFF, 0xFF, 0xFF, 0xFF,   # SoundOverride  = -1
        0xFF, 0xFF, 0xFF, 0xFF,   # Material       = -1
        0xCA, 0xD7, 0x00, 0x00,   # DisplayInfoID  = 55242
        0x00, 0x00, 0x00, 0x00,   # InventoryType  = 0
        0x00, 0x00, 0x00, 0x00,   # SheatheType    = 0
    ])),
]


def read_header(data):
    magic, record_count, field_count, record_size, string_block_size = \
        struct.unpack_from(HEADER_FMT, data, 0)
    return magic, record_count, field_count, record_size, string_block_size


def patch(input_path, output_path):
    with open(input_path, 'rb') as f:
        data = f.read()

    magic, record_count, field_count, record_size, string_block_size = read_header(data)

    # --- Validate input ---
    if magic != b'WDBC':
        print(f"ERROR: Not a valid DBC file (magic={magic!r}, expected b'WDBC').")
        return False
    if field_count != EXPECTED_FIELD_COUNT:
        print(f"ERROR: Unexpected field_count={field_count} (expected {EXPECTED_FIELD_COUNT}).")
        print("       This script is written for WoW 3.3.5a (build 12340) Item.dbc only.")
        return False
    if record_size != EXPECTED_RECORD_SIZE:
        print(f"ERROR: Unexpected record_size={record_size} (expected {EXPECTED_RECORD_SIZE}).")
        return False

    expected_input_size = HEADER_SIZE + record_count * record_size + string_block_size
    if len(data) != expected_input_size:
        print(f"ERROR: File size {len(data):,} does not match header calculation "
              f"{expected_input_size:,}. The file may be corrupt.")
        return False

    if os.path.abspath(output_path) == os.path.abspath(input_path):
        print("ERROR: Output path is the same as input path. Refusing to overwrite.")
        return False

    # --- Read existing records ---
    records_start    = HEADER_SIZE
    string_block     = data[records_start + record_count * record_size:]
    all_records      = []
    existing_entries = set()

    for i in range(record_count):
        offset = records_start + i * record_size
        entry  = struct.unpack_from('<I', data, offset)[0]
        existing_entries.add(entry)
        all_records.append((entry, data[offset : offset + record_size]))

    # --- Check for duplicates ---
    for entry_id, _ in NEW_RECORDS:
        if entry_id in existing_entries:
            print(f"ERROR: Entry {entry_id} already exists in this DBC. Nothing written.")
            return False

    # --- Print before state ---
    print()
    print("=== INPUT ===")
    print(f"  Path         : {input_path}")
    print(f"  File size    : {len(data):,} bytes")
    print(f"  Record count : {record_count:,}")
    print(f"  Record size  : {record_size} bytes/record")
    print(f"  String block : {string_block_size} bytes")

    # --- Insert new records at correct sorted positions ---
    for entry_id, record_bytes in sorted(NEW_RECORDS):
        keys = [r[0] for r in all_records]
        idx  = bisect.bisect_right(keys, entry_id)
        all_records.insert(idx, (entry_id, record_bytes))
        print(f"  Queued       : entry {entry_id} -> inserts at record index {idx}")

    new_record_count  = len(all_records)
    new_records_block = b''.join(rb for _, rb in all_records)
    new_header        = struct.pack(
        HEADER_FMT,
        b'WDBC',
        new_record_count,
        field_count,
        record_size,
        string_block_size,
    )
    output_data      = new_header + new_records_block + string_block
    expected_out_size = HEADER_SIZE + new_record_count * record_size + string_block_size

    # --- Write output ---
    with open(output_path, 'wb') as f:
        f.write(output_data)

    print()
    print("=== OUTPUT ===")
    print(f"  Path         : {output_path}")
    print(f"  File size    : {len(output_data):,} bytes  (was {len(data):,}, "
          f"+{len(output_data)-len(data)})")
    print(f"  Record count : {new_record_count:,}  (was {record_count:,}, "
          f"+{new_record_count-record_count})")

    # --- Self-verification ---
    print()
    print("=== SELF-VERIFICATION ===")
    with open(output_path, 'rb') as f:
        vdata = f.read()

    v_magic, v_rc, v_fc, v_rs, v_sbs = read_header(vdata)
    all_pass = True

    def check(label, cond, detail=""):
        nonlocal all_pass
        if cond:
            print(f"  [PASS] {label}" + (f"  ({detail})" if detail else ""))
        else:
            print(f"  [FAIL] {label}" + (f"  ({detail})" if detail else ""))
            all_pass = False

    check("Header magic",
          v_magic == b'WDBC',
          f"got {v_magic!r}")
    check("Header record count",
          v_rc == new_record_count,
          f"{v_rc:,} == {new_record_count:,}")
    check("File size matches header",
          len(vdata) == expected_out_size,
          f"{len(vdata):,} == {expected_out_size:,}")
    check("String block unchanged",
          vdata[HEADER_SIZE + v_rc * v_rs:] == string_block,
          f"{string_block_size} bytes")

    for entry_id, expected_bytes in NEW_RECORDS:
        found       = False
        found_index = -1
        for i in range(v_rc):
            offset = HEADER_SIZE + i * v_rs
            e      = struct.unpack_from('<I', vdata, offset)[0]
            if e == entry_id:
                actual = vdata[offset : offset + v_rs]
                check(f"Entry {entry_id} bytes match",
                      actual == expected_bytes,
                      f"record index {i}, offset {offset}")
                found       = True
                found_index = i
                # Verify it is inside the record region, not the string block
                in_record_region = (offset >= HEADER_SIZE and
                                    offset + v_rs <= HEADER_SIZE + v_rc * v_rs)
                check(f"Entry {entry_id} is inside record region",
                      in_record_region,
                      f"offset {offset}, record region ends at "
                      f"{HEADER_SIZE + v_rc * v_rs}")
                break
        if not found:
            check(f"Entry {entry_id} found in output", False)

    print()
    if all_pass:
        print("  All checks passed. The output file is valid.")
    else:
        print("  One or more checks FAILED. Do not use the output file.")
        return False

    return True


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python patch_item_dbc.py <input_Item.dbc> <output_Item.dbc>")
        print()
        print("  Patches a vanilla WoW 3.3.5a (build 12340) Item.dbc to include")
        print("  the Echoes of the Worldsoul custom items:")
        print("    900010  Worldsoul Echo Fragment   (DisplayInfoID 55243)")
        print("    900011  Worldsoul Residue          (DisplayInfoID 55242)")
        print()
        print("  The input file is never modified. A new file is written to <output_Item.dbc>.")
        print("  The script performs a mandatory self-check after writing and will")
        print("  report FAIL if any verification step does not pass.")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2]

    if not os.path.isfile(inp):
        print(f"ERROR: Input file not found: {inp}")
        sys.exit(1)

    ok = patch(inp, out)
    sys.exit(0 if ok else 1)
