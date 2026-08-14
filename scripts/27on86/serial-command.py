#!/usr/bin/env python3

import argparse
import os
from pathlib import Path
import re
import secrets
import socket
import sys
import time


BOOT_PROMPT = b"-sh-3.2# "
READY_PROMPT = b"__27ON86_PROMPT__ "
MAX_BUFFER = 4 * 1024 * 1024


class SerialCommandError(Exception):
    pass


def receive_until(sock, buffer, pattern, deadline):
    while True:
        match = pattern.search(buffer)
        if match:
            return match
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SerialCommandError(f"timed out waiting for {pattern.pattern!r}")
        sock.settimeout(min(1.0, remaining))
        try:
            chunk = sock.recv(65536)
        except TimeoutError:
            continue
        if not chunk:
            raise SerialCommandError("serial connection closed")
        buffer.extend(chunk)
        if len(buffer) > MAX_BUFFER:
            del buffer[:-MAX_BUFFER]


def connect(path, deadline):
    last_error = None
    while time.monotonic() < deadline:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(path)
            return sock
        except (FileNotFoundError, ConnectionRefusedError) as error:
            last_error = error
            sock.close()
            time.sleep(0.1)
    raise SerialCommandError(f"could not connect to {path}: {last_error}")


def run_command(path, command, timeout):
    deadline = time.monotonic() + timeout
    token = secrets.token_hex(12).encode()
    begin = b"__27ON86_BEGIN_" + token + b"__"
    end = b"__27ON86_END_" + token + b"__"
    end_pattern = re.compile(re.escape(end) + rb":([0-9]+)\r*\n")
    buffer = bytearray()

    with connect(path, deadline) as sock:
        sock.sendall(b"\n")
        prompt_pattern = re.compile(
            b"(?:" + re.escape(BOOT_PROMPT) + b"|" + re.escape(READY_PROMPT) + b")"
        )
        receive_until(sock, buffer, prompt_pattern, deadline)
        del buffer[:]
        sock.sendall(b"stty -echo; export PS1='" + READY_PROMPT + b"'\n")
        receive_until(sock, buffer, re.compile(re.escape(READY_PROMPT)), deadline)
        del buffer[:]

        payload = (
            b"export PS1=''\nprintf '\\n"
            + begin
            + b"\\n'\n"
            + command.encode()
            + b"\n__27on86_status=$?\nexport PS1='"
            + READY_PROMPT
            + b"'; printf '\\n"
            + end
            + b":%d\\n' \"$__27on86_status\"\n"
        )
        sock.sendall(payload)
        match = receive_until(sock, buffer, end_pattern, deadline)

    start = buffer.rfind(begin, 0, match.start())
    if start < 0:
        raise SerialCommandError("command output start marker was lost")
    start += len(begin)
    while buffer[start:start + 1] == b"\r":
        start += 1
    if buffer[start:start + 1] == b"\n":
        start += 1
    output = bytes(buffer[start:match.start()]).replace(b"\r", b"")
    status = int(match.group(1))
    return status, output


def parse_args():
    parser = argparse.ArgumentParser(
        description="run a command in a VMApple single-user serial shell"
    )
    parser.add_argument("socket", type=Path, help="QEMU Unix serial socket")
    parser.add_argument("command", help="shell command to execute")
    parser.add_argument("--timeout", type=float, default=180.0)
    return parser.parse_args()


def main():
    args = parse_args()
    if args.timeout <= 0:
        print("timeout must be positive", file=sys.stderr)
        return 2
    try:
        status, output = run_command(os.fspath(args.socket), args.command, args.timeout)
    except SerialCommandError as error:
        print(f"serial command failed: {error}", file=sys.stderr)
        return 124
    sys.stdout.buffer.write(output)
    return status if status <= 125 else 125


if __name__ == "__main__":
    sys.exit(main())
