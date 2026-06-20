# DBC Editing Notes — Echoes of the Worldsoul

This document explains the rules for correctly modifying WoW 3.3.5a `.dbc` files
and why raw byte-appending is wrong. Read this before editing any DBC file by hand
or writing a new patch script.

---

## DBC File Structure

Every `.dbc` file has three regions, in this exact order:

```
[ HEADER (20 bytes) ][ RECORD REGION ][ STRING BLOCK ]
```

### Header (always exactly 20 bytes)

| Offset | Size | Field             | Notes                                     |
|--------|------|-------------------|-------------------------------------------|
| 0      | 4    | Magic             | Always `WDBC` (ASCII, no null terminator) |
| 4      | 4    | `record_count`    | Number of records currently in the file   |
| 8      | 4    | `field_count`     | Number of fields per record               |
| 12     | 4    | `record_size`     | Bytes per record (`field_count * 4`)      |
| 16     | 4    | `string_block_size` | Byte length of the string block         |

All header integers are **little-endian unsigned 32-bit**.

### Record Region

Starts at byte offset **20** (immediately after the header).  
Total size: `record_count * record_size` bytes.  
Each record is `record_size` bytes wide with no separators.  
Records are sorted ascending by their first field (entry ID) in all vanilla DBC files.

### String Block

Starts at byte offset `20 + record_count * record_size`.  
Total size: `string_block_size` bytes.  
Contains null-terminated UTF-8 strings referenced by record fields that hold a
string-block offset (rather than an integer value directly). A DBC with no string
fields still has a 1-byte string block containing a single `\x00` null byte.

---

## The Rule: Insert Into the Record Region, Never Append to EOF

The client's DBC loader calculates the string block start offset using the formula:

```
string_block_start = 20 + record_count * record_size
```

If you append new record bytes **after** the last byte of the file instead of
inserting them before the string block, the string block is no longer where the
client expects it. The client misreads the byte region that was the string block
as record data, and misreads the byte region that was the new records as string
data. This produces garbage values for every affected record's string-type fields,
and for non-string DBC files (like Item.dbc) it produces silent field-value
corruption and invalid pointer arithmetic in the client's memory.

**The correct procedure for adding new records:**

1. Read the full file into memory.
2. Identify the record region: `data[20 : 20 + record_count * record_size]`.
3. Identify the string block: `data[20 + record_count * record_size :]`.
4. Insert the new record bytes at the correct sorted position within the record region.
5. Rebuild the file as: `new_header + updated_record_region + original_string_block`.
6. Update `record_count` in the new header to `original_count + N`.
7. Do **not** change `record_size`, `field_count`, or `string_block_size`.
8. Write the result to a **new output file**. Never overwrite the input.

---

## Item.dbc Field Layout (WoW 3.3.5a, build 12340)

`Item.dbc` has `field_count=8` and `record_size=32` (8 × 4 bytes). All fields
are 32-bit little-endian. Signed fields are noted.

| Index | Offset | Type    | Name                   | Notes                            |
|-------|--------|---------|------------------------|----------------------------------|
| 0     | +0     | uint32  | Entry                  | Item entry ID (primary key)      |
| 1     | +4     | uint32  | Class                  | Item class (e.g. 15 = Quest)     |
| 2     | +8     | uint32  | Subclass               |                                  |
| 3     | +12    | int32   | SoundOverrideSubclass  | -1 = none                        |
| 4     | +16    | int32   | Material               | -1 = none                        |
| 5     | +20    | uint32  | DisplayInfoID          | Links to ItemDisplayInfo.dbc     |
| 6     | +24    | uint32  | InventoryType          | 0 = non-equippable               |
| 7     | +28    | uint32  | SheatheType            | 0 = none                         |

`Item.dbc` contains **no string fields**. Its string block is always 1 byte (`\x00`).
String data for items (names, descriptions) lives in `item_template` in the world DB,
not in this DBC.

---

## Verified Custom Records for This Project

The following records are the canonical values used by the Echoes of the Worldsoul
mod. These bytes have been verified against a working patched 3.3.5a (build 12340)
client that loads both items without triggering `CMSG_ITEM_QUERY_SINGLE` retry loops
or client crashes.

### Entry 900010 — Worldsoul Echo Fragment

```
AA BB 0D 00   entry=900010
0F 00 00 00   class=15 (Quest)
00 00 00 00   subclass=0
FF FF FF FF   SoundOverrideSubclass=-1
FF FF FF FF   Material=-1
CB D7 00 00   DisplayInfoID=55243
00 00 00 00   InventoryType=0
00 00 00 00   SheatheType=0
```

### Entry 900011 — Worldsoul Residue

```
AB BB 0D 00   entry=900011
0F 00 00 00   class=15 (Quest)
00 00 00 00   subclass=0
FF FF FF FF   SoundOverrideSubclass=-1
FF FF FF FF   Material=-1
CA D7 00 00   DisplayInfoID=55242
00 00 00 00   InventoryType=0
00 00 00 00   SheatheType=0
```

---

## Verification Checklist

After generating or receiving a patched Item.dbc, verify all of the following
before putting it in a patch MPQ or distributing it:

- [ ] Magic bytes at offset 0 are exactly `57 44 42 43` (`WDBC`)
- [ ] `record_count` in header = original count + number of new records
- [ ] `file_size == 20 + record_count * record_size + string_block_size` (no extra bytes)
- [ ] Both new entries can be read back at the expected byte offsets
- [ ] Both new entries fall within the record region (not in or after the string block)
- [ ] String block (final `string_block_size` bytes) is byte-for-byte unchanged

`patch_item_dbc.py` in this directory performs all six checks automatically and
prints `[PASS]` / `[FAIL]` for each one. Do not use the output file if any check fails.

---

## Known Failure Mode

The crash that inspired these notes: appending new DBC records after EOF (outside
the record region) causes the client to misalign its string block pointer. On
Item.dbc specifically (which has no string fields and a 1-byte string block), this
manifests as record-count misalignment. The client reads `record_count` records
starting at offset 20, but since the file is now longer than the header implies,
the extra bytes at the end become unreachable. For DBC files that DO have string
fields, the same mistake corrupts all string offsets for every record past the
insertion point, causing immediate client crashes or garbage item names.

**Always rebuild as `header + record_region + string_block`, never append.**
