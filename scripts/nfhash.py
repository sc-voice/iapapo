#!/usr/bin/env python3
"""Content hash in the nf alphabet: SHA-256 of the bytes, encoded as order-preserving base64.

Matches `nf hash <file>` (43 characters for SHA-256). The first characters of a result serve as
short labels, such as the version in a wake-word run folder.
"""

import hashlib

OPB64_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
_CHUNK = 1 << 20


def opb64(data: bytes) -> str:
    """Encode bytes as order-preserving base64 (nf alphabet, no padding).

    Packs 6 bits per character, most significant bit first. A final partial group is
    zero-padded on the right, as nf does.

    Args:
        data: bytes to encode.

    Returns:
        The encoded string.
    """
    out = []
    bits = 0
    count = 0
    for byte in data:
        bits = (bits << 8) | byte
        count += 8
        while count >= 6:
            count -= 6
            out.append(OPB64_ALPHABET[(bits >> count) & 0x3F])
    if count > 0:
        out.append(OPB64_ALPHABET[(bits << (6 - count)) & 0x3F])
    return "".join(out)


def nf_hash(data: bytes) -> str:
    """SHA-256 of the bytes, encoded with opb64. 43 characters.

    Args:
        data: bytes to hash.

    Returns:
        The nf hash of data.
    """
    return opb64(hashlib.sha256(data).digest())


def nf_hash_file(path: str) -> str:
    """nf hash of a file's contents, read in chunks. Equal to nf_hash of the same bytes.

    Args:
        path: path to the file.

    Returns:
        The nf hash of the file.
    """
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(_CHUNK), b""):
            digest.update(chunk)
    return opb64(digest.digest())


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        sys.exit("usage: nfhash.py <file>")
    print(nf_hash_file(sys.argv[1]))
