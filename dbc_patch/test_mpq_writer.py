#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
#
# Plain-assertion test suite for mpq_writer.py -- no external test
# framework dependency, matching this directory's existing style
# (patch_item_dbc.py's own self-check). Run directly:
#
#   python test_mpq_writer.py
#
# This suite exists because an earlier attempt to unify mpq_writer's
# encrypt/decrypt into one routine silently produced wrong reads (the
# stream cipher's key2 state must advance using the plaintext word on
# both encrypt and decrypt, not whichever value the function received).
# The round-trip test below would have caught that; keep it.

import os
import sys
import tempfile

from mpq_writer import write_single_file_mpq, read_single_file_mpq, archive_file_count

FAILURES = []


def check(label, cond):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILURES.append(label)


def with_tmp(fn):
    tmp = tempfile.mktemp(suffix=".mpq")
    try:
        fn(tmp)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def test_basic_roundtrip():
    print("test_basic_roundtrip")

    def run(tmp):
        payload = b"hello world, this is a test payload"
        write_single_file_mpq(tmp, "Some\\Internal\\Path.dat", payload)
        out = read_single_file_mpq(tmp, "Some\\Internal\\Path.dat")
        check("payload round-trips exactly", out == payload)

    with_tmp(run)


def test_empty_file():
    print("test_empty_file")

    def run(tmp):
        write_single_file_mpq(tmp, "Empty.dat", b"")
        out = read_single_file_mpq(tmp, "Empty.dat")
        check("empty file round-trips exactly", out == b"")

    with_tmp(run)


def test_one_byte_file():
    print("test_one_byte_file")

    def run(tmp):
        write_single_file_mpq(tmp, "One.dat", b"X")
        out = read_single_file_mpq(tmp, "One.dat")
        check("1-byte file round-trips exactly", out == b"X")

    with_tmp(run)


def test_odd_length_file():
    print("test_odd_length_file")

    def run(tmp):
        payload = b"12345"  # 5 bytes, not a multiple of 4
        write_single_file_mpq(tmp, "Odd.bin", payload)
        out = read_single_file_mpq(tmp, "Odd.bin")
        check("odd-length (5 byte) file round-trips exactly", out == payload)

    with_tmp(run)


def test_case_insensitive_lookup():
    print("test_case_insensitive_lookup")

    def run(tmp):
        write_single_file_mpq(tmp, "DBFilesClient\\Item.dbc", b"payload")
        lower = read_single_file_mpq(tmp, "dbfilesclient\\item.dbc")
        upper = read_single_file_mpq(tmp, "DBFILESCLIENT\\ITEM.DBC")
        check("lowercase lookup matches", lower == b"payload")
        check("uppercase lookup matches", upper == b"payload")

    with_tmp(run)


def test_wrong_path_raises():
    print("test_wrong_path_raises")

    def run(tmp):
        write_single_file_mpq(tmp, "Real\\Path.dat", b"payload")
        try:
            read_single_file_mpq(tmp, "Wrong\\Path.dat")
            check("wrong internal path raises ValueError", False)
        except ValueError:
            check("wrong internal path raises ValueError", True)

    with_tmp(run)


def test_deterministic_hash_for_identical_input():
    print("test_deterministic_hash_for_identical_input")
    import hashlib

    def run(tmp1):
        def run2(tmp2):
            write_single_file_mpq(tmp1, "Same\\Path.dat", b"identical payload")
            write_single_file_mpq(tmp2, "Same\\Path.dat", b"identical payload")
            h1 = hashlib.sha256(open(tmp1, 'rb').read()).hexdigest()
            h2 = hashlib.sha256(open(tmp2, 'rb').read()).hexdigest()
            check("identical (path, bytes) produces byte-identical archive", h1 == h2)
        with_tmp(run2)

    with_tmp(run)


def test_structural_file_count():
    print("test_structural_file_count")

    def run(tmp):
        write_single_file_mpq(tmp, "Solo.dat", b"only one file here")
        occupied, block_entries = archive_file_count(tmp)
        check("exactly one occupied hash slot", occupied == 1)
        check("exactly one block table entry", block_entries == 1)

    with_tmp(run)


def test_generated_mpq_extraction_equality():
    print("test_generated_mpq_extraction_equality")

    def run(tmp):
        # Simulates the real pipeline shape: a "patched DBC"-sized payload
        # packaged then extracted, confirming byte equality end to end.
        fake_dbc = b"WDBC" + bytes(range(256)) * 50  # arbitrary multi-KB payload
        write_single_file_mpq(tmp, "DBFilesClient\\Item.dbc", fake_dbc)
        extracted = read_single_file_mpq(tmp, "DBFilesClient\\Item.dbc")
        check("generated archive extraction equals original payload", extracted == fake_dbc)

    with_tmp(run)


if __name__ == '__main__':
    test_basic_roundtrip()
    test_empty_file()
    test_one_byte_file()
    test_odd_length_file()
    test_case_insensitive_lookup()
    test_wrong_path_raises()
    test_deterministic_hash_for_identical_input()
    test_structural_file_count()
    test_generated_mpq_extraction_equality()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("All checks passed.")
