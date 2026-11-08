"""Unit tests for scripts/nfhash.py. Run with: .venv/bin/python scripts/python/tests/test_nfhash.py

The golden values were produced by `nf hash` on files holding exactly these bytes.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from nfhash import OPB64_ALPHABET, nf_hash, nf_hash_file, opb64  # noqa: E402

EMPTY_HASH = "ux34GfZy71IQ-_J8cM-v92UkGUHacvDCf9MP6tXIk5K"
ABC_HASH = "kdWMluy1p-f1GK3UNQuY8x03OQEM5tgSj13_OV805Qq"


def nf_available():
    return shutil.which("nf") is not None


class NfHashTests(unittest.TestCase):
    def test_empty_input_matches_nf(self):
        self.assertEqual(nf_hash(b""), EMPTY_HASH)

    def test_abc_matches_nf(self):
        self.assertEqual(nf_hash(b"abc"), ABC_HASH)

    def test_output_is_43_characters_from_alphabet(self):
        h = nf_hash(b"any bytes at all")
        self.assertEqual(len(h), 43)
        self.assertTrue(set(h) <= set(OPB64_ALPHABET))

    def test_file_hash_equals_bytes_hash(self):
        data = os.urandom(3 * (1 << 20) + 17)  # spans several read chunks
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "blob.bin")
            with open(path, "wb") as f:
                f.write(data)
            self.assertEqual(nf_hash_file(path), nf_hash(data))

    def test_different_content_gives_different_hash(self):
        self.assertNotEqual(nf_hash(b"abc"), nf_hash(b"abd"))

    def test_command_line_prints_file_hash(self):
        data = b"command line\n"
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "cli.bin")
            with open(path, "wb") as f:
                f.write(data)
            script = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "nfhash.py")
            out = subprocess.run(
                [sys.executable, script, path], capture_output=True, text=True, check=True
            ).stdout.strip()
        self.assertEqual(out, nf_hash(data))

    @unittest.skipUnless(nf_available(), "nf is not on PATH")
    def test_matches_nf_hash_command(self):
        data = b"parity with the nf command\n"
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "parity.bin")
            with open(path, "wb") as f:
                f.write(data)
            out = subprocess.run(
                ["nf", "hash", path], capture_output=True, text=True, check=True
            ).stdout.strip()
        self.assertEqual(out, nf_hash(data))


class Opb64Tests(unittest.TestCase):
    def test_single_byte_packs_and_pads(self):
        # 0xFF -> 111111 | 11 padded to 110000: index 63 is '_', index 48 is 'm'
        self.assertEqual(opb64(b"\xff"), "_m")
        self.assertEqual(opb64(b""), "")

    def test_order_preserved_for_ascending_values(self):
        # Order is the alphabet's rank order, not ASCII: '-' and '_' rank above 'z'.
        def rank_key(s):
            return [OPB64_ALPHABET.index(c) for c in s]

        values = [n.to_bytes(2, "big") for n in range(0, 65536, 97)]
        encoded = [opb64(v) for v in values]
        self.assertEqual(
            [rank_key(s) for s in encoded], sorted(rank_key(s) for s in encoded)
        )
        self.assertEqual(encoded, sorted(encoded, key=rank_key))


if __name__ == "__main__":
    unittest.main()
