#!/usr/bin/env python3

"""Turn a VMApple single-user serial shell into a headless SSH guest."""

import argparse
import base64
import importlib.util
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


SCRIPT_DIR = Path(__file__).resolve().parent
SERIAL_HELPER = SCRIPT_DIR / "serial-command.py"
SPEC = importlib.util.spec_from_file_location("serial_command", SERIAL_HELPER)
serial_command = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(serial_command)

ASSETS = (
    "guest-headless-bootstrap.sh",
    "headless-sshd.conf",
    "headless-sshd.plist",
)


def run_serial(socket_path: Path, command: str, timeout: float = 600):
    status, output = serial_command.run_command(
        os.fspath(socket_path), command, timeout
    )
    if status:
        sys.stdout.buffer.write(output)
        raise RuntimeError(f"guest command exited with status {status}")
    return output.decode(errors="replace")


def ensure_key(path: Path):
    if path.exists() and path.with_name(path.name + ".pub").exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", os.fspath(path)],
        check=True,
    )


def discover_stage(socket_path: Path):
    output = run_serial(
        socket_path,
        """
stage=
for candidate in /System/Volumes/Preboot/*; do
    leaf=${candidate##*/}
    case "$leaf" in
        ????????-????-????-????-????????????)
            stage="$candidate/var/27on86"
            break
            ;;
    esac
done
test -n "$stage"
mkdir -p "$stage"
printf '%s\n' "$stage"
""",
    )
    matches = re.findall(
        r"/System/Volumes/Preboot/[0-9A-Fa-f-]{36}/var/27on86", output
    )
    if not matches:
        raise RuntimeError("guest did not report its staging directory")
    return matches[-1]


def upload(socket_path: Path, stage: str, name: str, content: bytes, mode: int):
    print(f"staging {name}", flush=True)
    encoded = base64.b64encode(content).decode()
    destination = f"{stage}/{name}"
    encoded_path = destination + ".b64"
    run_serial(socket_path, f": > {shlex.quote(encoded_path)}")
    for offset in range(0, len(encoded), 128):
        chunk = encoded[offset : offset + 128]
        run_serial(
            socket_path,
            "printf '%%s' %s >> %s"
            % (shlex.quote(chunk), shlex.quote(encoded_path)),
        )
    run_serial(
        socket_path,
        "/usr/bin/base64 -D < %s > %s"
        % (shlex.quote(encoded_path), shlex.quote(destination)),
    )
    run_serial(socket_path, "rm -f %s" % shlex.quote(encoded_path))
    run_serial(socket_path, "chmod %o %s" % (mode, shlex.quote(destination)))


def stage_command(stage: str):
    return shlex.quote(f"{stage}/guest-headless-bootstrap.sh")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("serial_socket", type=Path)
    parser.add_argument("state_directory", type=Path)
    return parser.parse_args()


def main():
    args = parse_args()
    client_key = args.state_directory / "id_ed25519"
    host_key = args.state_directory / "ssh_host_ed25519_key"
    ensure_key(client_key)
    ensure_key(host_key)

    stage = discover_stage(args.serial_socket)
    upload(args.serial_socket, stage, "authorized_keys", client_key.with_name(
        client_key.name + ".pub"
    ).read_bytes(), 0o600)
    upload(
        args.serial_socket,
        stage,
        "ssh_host_ed25519_key",
        host_key.read_bytes(),
        0o600,
    )
    upload(
        args.serial_socket,
        stage,
        "ssh_host_ed25519_key.pub",
        host_key.with_name(host_key.name + ".pub").read_bytes(),
        0o644,
    )
    for name in ASSETS:
        mode = 0o700 if name.endswith(".sh") else 0o600
        upload(args.serial_socket, stage, name, (SCRIPT_DIR / name).read_bytes(), mode)

    print("running guest headless bootstrap", flush=True)
    output = run_serial(args.serial_socket, stage_command(stage), timeout=900)
    print(output, end="")
    print(f"SSH identity: {client_key}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, serial_command.SerialCommandError, subprocess.CalledProcessError) as error:
        print(f"headless bootstrap failed: {error}", file=sys.stderr)
        sys.exit(1)
