python
import gdb
import os
import struct


HANDOFF_PC = 0xACA00000
BOOT_ARGS_REVISION = 2
BOOT_ARGS_VERSION = 2
COMMAND_LINE_OFFSET = 108
COMMAND_LINE_SIZE = 608


def required_environment(name):
    value = os.environ.get(name)
    if not value:
        raise gdb.GdbError(f"set {name}")
    return value


port = required_environment("QEMU_27ON86_GDB_PORT")
command_line = required_environment("QEMU_27ON86_XNU_BOOT_ARGS").encode()
if b"\0" in command_line:
    raise gdb.GdbError("XNU boot arguments must not contain a NUL byte")
if len(command_line) >= COMMAND_LINE_SIZE:
    raise gdb.GdbError(
        f"XNU boot arguments must be shorter than {COMMAND_LINE_SIZE} bytes"
    )

gdb.execute("set architecture aarch64", to_string=True)
gdb.execute(f"target remote :{port}", to_string=True)

# The reset path uses the handoff trampoline once for the second-stage loader
# and a second time for XNU. At the second entry, x1 is the public boot_args
# structure that the trampoline passes to the kernel in x0.
breakpoint = gdb.Breakpoint(
    f"*{HANDOFF_PC:#x}", type=gdb.BP_HARDWARE_BREAKPOINT, internal=True
)
breakpoint.ignore_count = 1
gdb.execute("continue", to_string=True)

pc = int(gdb.parse_and_eval("$pc"))
if pc != HANDOFF_PC:
    raise gdb.GdbError(f"unexpected stop at {pc:#x}")

boot_args = int(gdb.parse_and_eval("$x1"))
inferior = gdb.selected_inferior()
header = bytes(inferior.read_memory(boot_args, 4))
revision, version = struct.unpack("<HH", header)
if (revision, version) != (BOOT_ARGS_REVISION, BOOT_ARGS_VERSION):
    raise gdb.GdbError(
        f"unexpected boot_args revision/version {revision}/{version}"
    )

payload = (command_line + b"\0").ljust(COMMAND_LINE_SIZE, b"\0")
inferior.write_memory(boot_args + COMMAND_LINE_OFFSET, payload)
readback = bytes(
    inferior.read_memory(boot_args + COMMAND_LINE_OFFSET, len(command_line) + 1)
)
if readback != command_line + b"\0":
    raise gdb.GdbError("XNU boot-argument write did not verify")

print(f"injected XNU boot arguments: {command_line.decode(errors='replace')}")
breakpoint.delete()
gdb.execute("detach", to_string=True)
end
