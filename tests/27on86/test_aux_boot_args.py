#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/27on86/set-aux-boot-args.py"
SPEC = importlib.util.spec_from_file_location("set_aux_boot_args", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def partition(*entries: bytes) -> bytes:
    size = 512
    header = bytearray(size)
    header[0] = MODULE.SYSTEM_SIGNATURE
    header[2:4] = (size // 16).to_bytes(2, "little")
    header[4:10] = b"system"
    header[1] = MODULE.header_checksum(header[: MODULE.HEADER_SIZE])
    payload = b"\0".join(entries) + b"\0\0"
    header[MODULE.HEADER_SIZE : MODULE.HEADER_SIZE + len(payload)] = payload
    return bytes(header)


def bank(*entries: bytes) -> bytes:
    image = bytearray(MODULE.NVRAM_BANK_SIZE)
    image[0] = MODULE.NVRAM_SIGNATURE
    image[2:4] = (2).to_bytes(2, "little")
    image[4:9] = b"nvram"
    image[1] = MODULE.header_checksum(image[: MODULE.HEADER_SIZE])
    part = partition(*entries)
    image[0x60000 : 0x60000 + len(part)] = part
    checksum = MODULE.zlib.adler32(image[20:])
    image[16:20] = checksum.to_bytes(4, "little")
    return bytes(image)


class AuxBootArgsTest(unittest.TestCase):
    def test_updates_every_valid_mirror(self):
        original = bank(b"binary=\xff\x01", b"boot-args=", b"auto-boot=true")
        image = bytearray(original + original)

        self.assertEqual(MODULE.set_boot_args(image, b"-s serial=3"), 2)
        for bank_offset in MODULE.nvram_banks(image):
            matches = MODULE.system_partitions(
                image, bank_offset, bank_offset + MODULE.NVRAM_BANK_SIZE
            )
            for offset, size in matches:
                self.assertIn(b"boot-args=-s serial=3\0", image[offset : offset + size])

    def test_rejects_missing_partition(self):
        with self.assertRaisesRegex(ValueError, "no valid"):
            MODULE.set_boot_args(bytearray(512), b"-s")

    def test_rejects_oversized_value(self):
        image = bytearray(bank(b"boot-args="))
        with self.assertRaisesRegex(ValueError, "do not fit"):
            MODULE.set_boot_args(image, b"x" * 512)


if __name__ == "__main__":
    unittest.main()
