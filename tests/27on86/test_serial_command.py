import importlib.util
from pathlib import Path
import re
import socket
import tempfile
import threading
import unittest


SOURCE_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = SOURCE_ROOT / "scripts" / "27on86" / "serial-command.py"
SPEC = importlib.util.spec_from_file_location("serial_command", SCRIPT)
SERIAL_COMMAND = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERIAL_COMMAND)


class FakeSerialShell(threading.Thread):
    def __init__(self, path, output, status):
        super().__init__(daemon=True)
        self.path = path
        self.output = output
        self.status = status
        self.error = None

    def run(self):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                server.bind(self.path)
                server.listen(1)
                with server.accept()[0] as client:
                    client.sendall(SERIAL_COMMAND.BOOT_PROMPT)
                    self.receive_until(client, b"\n")
                    setup = self.receive_until(client, b"\n")
                    self.assert_contains(setup, b"stty -echo")
                    client.sendall(SERIAL_COMMAND.READY_PROMPT)
                    request = self.receive_until(client, b"$__27on86_status\"\n")
                    match = re.search(rb"__27ON86_BEGIN_([0-9a-f]+)__", request)
                    if not match:
                        raise AssertionError("missing begin marker")
                    token = match.group(1)
                    response = (
                        request
                        + b"__27ON86_BEGIN_"
                        + token
                        + b"__\r\r\n"
                        + self.output
                        + b"\r\n__27ON86_END_"
                        + token
                        + b"__:%d\r\r\n" % self.status
                    )
                    client.sendall(response)
        except Exception as error:
            self.error = error

    @staticmethod
    def receive_until(client, marker):
        data = bytearray()
        while marker not in data:
            chunk = client.recv(65536)
            if not chunk:
                raise AssertionError("client disconnected")
            data.extend(chunk)
        return bytes(data)

    @staticmethod
    def assert_contains(value, expected):
        if expected not in value:
            raise AssertionError(f"{expected!r} not in {value!r}")


class SerialCommandTests(unittest.TestCase):
    def test_returns_framed_output_and_guest_status(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "serial.sock")
            server = FakeSerialShell(path, b"guest output", 7)
            server.start()
            while not Path(path).exists():
                server.join(0.01)

            status, output = SERIAL_COMMAND.run_command(path, "false", 2)
            server.join(2)

            self.assertIsNone(server.error)
            self.assertEqual(status, 7)
            self.assertEqual(output, b"guest output\n")


if __name__ == "__main__":
    unittest.main()
