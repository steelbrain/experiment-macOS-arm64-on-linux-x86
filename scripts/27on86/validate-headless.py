#!/usr/bin/env python3

"""Run repeatable VMApple headless validation from fresh disk clones."""

import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import time


SCRIPT_DIR = Path(__file__).resolve().parent
SOURCE_ROOT = SCRIPT_DIR.parents[1]
RUNNER = SCRIPT_DIR / "run-vmapple-tcg.sh"
INJECTOR = SCRIPT_DIR / "inject-xnu-boot-args.sh"
BOOTSTRAP = SCRIPT_DIR / "bootstrap-headless.py"
WORKLOAD = SCRIPT_DIR / "guest-headless-workload.sh"


def reserve_tcp_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def wait_for_path(path: Path, process: subprocess.Popen, timeout: float):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise RuntimeError(f"QEMU exited with status {process.returncode}")
        time.sleep(0.1)
    raise RuntimeError(f"timed out waiting for {path}")


class QMP:
    def __init__(self, path: Path, timeout: float = 30):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(timeout)
        self.socket.connect(os.fspath(path))
        self.stream = self.socket.makefile("rwb", buffering=0)
        greeting = self.receive()
        if "QMP" not in greeting:
            raise RuntimeError("QMP greeting is missing")
        self.execute("qmp_capabilities")

    def close(self):
        self.stream.close()
        self.socket.close()

    def send(self, message):
        self.stream.write(json.dumps(message).encode() + b"\n")

    def receive(self):
        line = self.stream.readline()
        if not line:
            raise RuntimeError("QMP connection closed")
        return json.loads(line)

    def execute(self, command, arguments=None):
        message = {"execute": command}
        if arguments is not None:
            message["arguments"] = arguments
        self.send(message)
        while True:
            response = self.receive()
            if "error" in response:
                raise RuntimeError(f"QMP {command} failed: {response['error']}")
            if "return" in response:
                return response["return"]

    def wait_for_shutdown(self, timeout: float):
        self.socket.settimeout(timeout)
        while True:
            message = self.receive()
            if message.get("event") == "SHUTDOWN":
                return message.get("data", {})


def required_environment():
    names = (
        "QEMU_27ON86_FIRMWARE",
        "QEMU_27ON86_AUX",
        "QEMU_27ON86_ROOT",
        "QEMU_27ON86_ECID",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise RuntimeError("set " + ", ".join(missing))
    return {name: os.environ[name] for name in names}


def ssh_command(port: int, identity: Path, remote_command: str):
    return [
        "ssh",
        "-i",
        os.fspath(identity),
        "-p",
        str(port),
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        "-o",
        "LogLevel=ERROR",
        "-o",
        "ConnectTimeout=10",
        "root@127.0.0.1",
        remote_command,
    ]


def wait_for_ssh(port: int, identity: Path, timeout: float):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(
            ssh_command(port, identity, "true"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return
        time.sleep(2)
    raise RuntimeError("timed out waiting for SSH")


def start_qemu(index: int, cpus: int, output: Path, base_environment):
    ssh_port = reserve_tcp_port()
    gdb_port = reserve_tcp_port()
    serial_socket = Path(f"/tmp/27on86-{os.getpid()}-{index}.serial")
    run_output = output / f"run-{index}-{cpus}cpu"
    run_output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(base_environment)
    environment.update(
        {
            "QEMU_27ON86_OUTPUT_DIR": os.fspath(run_output),
            "QEMU_27ON86_SERIAL": f"unix:{serial_socket},server=on,wait=off",
            "QEMU_27ON86_SSH_PORT": str(ssh_port),
            "QEMU_27ON86_GDB_PORT": str(gdb_port),
            "QEMU_27ON86_PAUSE_AT_START": "on",
            "QEMU_27ON86_CPUS": str(cpus),
        }
    )
    process = subprocess.Popen(
        [os.fspath(RUNNER)],
        cwd=SOURCE_ROOT,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    first_line = process.stdout.readline().strip()
    prefix = "VMApple run directory: "
    if not first_line.startswith(prefix):
        raise RuntimeError(f"runner did not report its directory: {first_line}")
    run_directory = Path(first_line.removeprefix(prefix))
    wait_for_path(serial_socket, process, 30)
    wait_for_path(run_directory / "qmp.sock", process, 30)
    return process, run_directory, serial_socket, ssh_port, gdb_port


def run_validation(index: int, cpus: int, output: Path, base_environment):
    started = time.monotonic()
    process = None
    qmp = None
    http_process = None
    serial_socket = None
    run_directory = None
    try:
        process, run_directory, serial_socket, ssh_port, gdb_port = start_qemu(
            index, cpus, output, base_environment
        )
        print(f"run {index}: QEMU started in {run_directory}", flush=True)

        injector_environment = os.environ.copy()
        injector_environment.update(
            {
                "QEMU_27ON86_GDB_PORT": str(gdb_port),
                "QEMU_27ON86_XNU_BOOT_ARGS": "-s -v serial=11 debug=0x14c",
                "QEMU_27ON86_CSR_CONFIG": "0x2",
            }
        )
        subprocess.run(
            [os.fspath(INJECTOR)], env=injector_environment, check=True
        )
        print(f"run {index}: XNU handoff configured", flush=True)

        state_directory = run_directory / "headless-state"
        subprocess.run(
            [os.fspath(BOOTSTRAP), os.fspath(serial_socket), os.fspath(state_directory)],
            check=True,
        )
        identity = state_directory / "id_ed25519"
        wait_for_ssh(ssh_port, identity, 60)
        print(f"run {index}: SSH ready", flush=True)

        http_port = reserve_tcp_port()
        network_token = f"27on86-network-run-{index}"
        network_file = run_directory / "network-token"
        network_file.write_text(network_token)
        http_process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "http.server",
                str(http_port),
                "--bind",
                "127.0.0.1",
                "--directory",
                os.fspath(run_directory),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        network_url = f"http://10.0.2.2:{http_port}/{network_file.name}"
        with WORKLOAD.open("rb") as workload:
            result = subprocess.run(
                ssh_command(
                    ssh_port,
                    identity,
                    "sh -s -- "
                    + " ".join(
                        shlex.quote(value)
                        for value in (str(cpus), network_url, network_token)
                    ),
                ),
                stdin=workload,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=True,
            )
        workload_output = result.stdout.decode(errors="replace")
        (run_directory / "workload.log").write_text(workload_output)
        print(workload_output, end="", flush=True)

        qmp = QMP(run_directory / "qmp.sock")
        subprocess.run(
            ssh_command(
                ssh_port,
                identity,
                "/bin/launchctl reboot halt",
            ),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        shutdown = qmp.wait_for_shutdown(120)
        status = qmp.execute("query-status")
        if not shutdown.get("guest") or status.get("running"):
            raise RuntimeError(
                f"unclean shutdown evidence: event={shutdown}, status={status}"
            )
        print(
            f"run {index}: clean shutdown ({shutdown.get('reason')}) after "
            f"{time.monotonic() - started:.1f}s",
            flush=True,
        )
        qmp.execute("quit")
        qmp.close()
        qmp = None
        process.wait(timeout=30)
        return run_directory
    finally:
        if http_process is not None and http_process.poll() is None:
            http_process.terminate()
            http_process.wait(timeout=10)
        if qmp is not None:
            try:
                qmp.execute("quit")
            except (OSError, RuntimeError):
                pass
            qmp.close()
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        if process is not None and process.stdout is not None:
            remaining = process.stdout.read()
            if run_directory is not None and remaining:
                (run_directory / "qemu.log").write_text(remaining)
        if serial_socket is not None:
            try:
                serial_socket.unlink()
            except FileNotFoundError:
                pass


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--cpus", type=int, default=8)
    parser.add_argument(
        "--output", type=Path, default=SOURCE_ROOT / "out/headless-validation"
    )
    parser.add_argument("--skip-one-cpu-regression", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.runs < 1 or args.cpus < 1:
        raise RuntimeError("runs and CPUs must be positive")
    base_environment = required_environment()
    args.output.mkdir(parents=True, exist_ok=True)

    completed = []
    for index in range(1, args.runs + 1):
        completed.append(run_validation(index, args.cpus, args.output, base_environment))
    if not args.skip_one_cpu_regression:
        completed.append(
            run_validation(args.runs + 1, 1, args.output, base_environment)
        )

    print("validated fresh VMApple runs:")
    for directory in completed:
        print(f"  {directory}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, socket.timeout) as error:
        print(f"headless validation failed: {error}", file=sys.stderr)
        sys.exit(1)
