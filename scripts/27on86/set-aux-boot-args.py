#!/usr/bin/env python3

"""Set boot-args in every valid CHRP system partition in an image."""

import argparse
from pathlib import Path
import zlib


HEADER_SIZE = 16
SYSTEM_SIGNATURE = 0x70
NVRAM_SIGNATURE = 0x5A
NVRAM_BANK_SIZE = 0x80000


def header_checksum(header: bytes) -> int:
    total = header[0]
    for value in header[2:16]:
        total += value
        total = (total + (total >> 8)) & 0xFF
    return total


def system_partitions(image: bytearray, start: int = 0, end: int | None = None):
    if end is None:
        end = len(image)
    for offset in range(start, end - HEADER_SIZE + 1, 16):
        header = image[offset : offset + HEADER_SIZE]
        if header[0] != SYSTEM_SIGNATURE or header[4:16].rstrip(b"\0") != b"system":
            continue
        if header_checksum(header) != header[1]:
            continue

        size = int.from_bytes(header[2:4], "little") * 16
        if size < HEADER_SIZE or offset + size > end:
            continue
        yield offset, size


def nvram_banks(image: bytearray):
    for offset in range(0, len(image) - NVRAM_BANK_SIZE + 1, 16):
        header = image[offset : offset + HEADER_SIZE]
        if header[0] != NVRAM_SIGNATURE or header[4:16].rstrip(b"\0") != b"nvram":
            continue
        if header_checksum(header) != header[1]:
            continue

        stored = int.from_bytes(image[offset + 16 : offset + 20], "little")
        actual = zlib.adler32(image[offset + 20 : offset + NVRAM_BANK_SIZE])
        if stored == actual:
            yield offset


def replace_boot_args(partition: bytearray, boot_args: bytes) -> None:
    payload = partition[HEADER_SIZE:]
    end = payload.find(b"\0\0")
    if end < 0:
        raise ValueError("system partition has no variable-list terminator")

    entries = payload[:end].split(b"\0") if end else []
    replacement = b"boot-args=" + boot_args
    for index, entry in enumerate(entries):
        if entry.startswith(b"boot-args="):
            entries[index] = replacement
            break
    else:
        entries.append(replacement)

    encoded = b"\0".join(entries) + b"\0\0"
    if len(encoded) > len(payload):
        raise ValueError("boot arguments do not fit in the system partition")

    partition[HEADER_SIZE:] = encoded.ljust(len(payload), b"\0")


def validate_nvram_layout(image: bytearray) -> list[int]:
    banks = list(nvram_banks(image))
    if not banks:
        raise ValueError("no valid NVRAM banks found")
    if any(offset % NVRAM_BANK_SIZE for offset in banks):
        raise ValueError("NVRAM banks must start at bank-aligned offsets")
    for bank_offset in banks:
        bank_end = bank_offset + NVRAM_BANK_SIZE
        if not list(system_partitions(image, bank_offset, bank_end)):
            raise ValueError("NVRAM bank has no valid CHRP system partition")
    return banks


def set_boot_args(image: bytearray, boot_args: bytes) -> int:
    banks = validate_nvram_layout(image)

    count = 0
    for bank_offset in banks:
        bank_end = bank_offset + NVRAM_BANK_SIZE
        matches = list(system_partitions(image, bank_offset, bank_end))
        for offset, size in matches:
            partition = image[offset : offset + size]
            replace_boot_args(partition, boot_args)
            image[offset : offset + size] = partition
            count += 1

        checksum = zlib.adler32(image[bank_offset + 20 : bank_end])
        image[bank_offset + 16 : bank_offset + 20] = checksum.to_bytes(4, "little")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("image", type=Path)
    parser.add_argument("boot_args", nargs="?")
    args = parser.parse_args()

    if args.check_only and args.boot_args is not None:
        parser.error("boot_args cannot be used with --check-only")
    if not args.check_only and args.boot_args is None:
        parser.error("boot_args is required unless --check-only is used")
    if args.boot_args is not None and "\0" in args.boot_args:
        parser.error("boot arguments must not contain NUL bytes")

    image = bytearray(args.image.read_bytes())
    try:
        if args.check_only:
            validate_nvram_layout(image)
            return
        count = set_boot_args(image, args.boot_args.encode())
    except ValueError as error:
        parser.error(str(error))
    args.image.write_bytes(image)
    print(f"updated {count} CHRP system partition(s)")


if __name__ == "__main__":
    main()
