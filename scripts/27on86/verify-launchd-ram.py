#!/usr/bin/env python3

import argparse
import mmap
import struct
import sys


PROC_COMM_OFFSET = 1464
PROC_NAME_OFFSET = PROC_COMM_OFFSET + 17
PROC_PID_OFFSET = 0x60
PROC_STAT_OFFSET = 0x64
PROC_STATE_RUNNABLE = 2
PROCESS_NAME = b"launchd\0"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="verify a live PID 1 launchd process in a raw RAM range"
    )
    parser.add_argument("dump", help="raw physical-memory range from QEMU")
    args = parser.parse_args()

    with open(args.dump, "rb") as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as memory:
            offset = 0
            while True:
                offset = memory.find(PROCESS_NAME, offset)
                if offset < 0:
                    break

                proc_offset = offset - PROC_COMM_OFFSET
                if (proc_offset >= 0 and
                        memory[offset:offset + len(PROCESS_NAME)] ==
                        PROCESS_NAME and
                        memory[proc_offset + PROC_NAME_OFFSET:
                               proc_offset + PROC_NAME_OFFSET +
                               len(PROCESS_NAME)] == PROCESS_NAME):
                    pid = struct.unpack_from(
                        "<i", memory, proc_offset + PROC_PID_OFFSET)[0]
                    state = memory[proc_offset + PROC_STAT_OFFSET]
                    if pid == 1 and state == PROC_STATE_RUNNABLE:
                        print("live launchd PID 1: PASS")
                        return 0
                offset += 1

    print("live launchd PID 1: NOT FOUND", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
