python
import gdb
import os
import struct
import sys


HANDOFF_PC = 0xACA00000
BOOT_ARGS_REVISION = 2
BOOT_ARGS_VERSION = 2
COMMAND_LINE_OFFSET = 108
COMMAND_LINE_SIZE = 608
DEVICE_TREE_POINTER_OFFSET = 96
DEVICE_TREE_LENGTH_OFFSET = 104
VIRTUAL_BASE_OFFSET = 8
PHYSICAL_BASE_OFFSET = 16


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

csr_config_text = os.environ.get("QEMU_27ON86_CSR_CONFIG")
csr_config = None
if csr_config_text:
    try:
        csr_config = int(csr_config_text, 0)
    except ValueError as error:
        raise gdb.GdbError("QEMU_27ON86_CSR_CONFIG must be an integer") from error
    if not 0 <= csr_config <= 0xFFFFFFFF:
        raise gdb.GdbError("QEMU_27ON86_CSR_CONFIG must fit in 32 bits")

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

if csr_config is not None:
    # GDB does not expose the command-file path. The wrapper runs from any
    # directory, so use the repository script path supplied by the wrapper.
    script_dir = required_environment("QEMU_27ON86_SCRIPT_DIR")
    sys.path.insert(0, script_dir)
    import apple_device_tree

    virtual_base, physical_base = struct.unpack(
        "<QQ", bytes(inferior.read_memory(boot_args + VIRTUAL_BASE_OFFSET, 16))
    )
    device_tree_virtual, device_tree_length = struct.unpack(
        "<QI",
        bytes(inferior.read_memory(boot_args + DEVICE_TREE_POINTER_OFFSET, 12)),
    )
    if device_tree_virtual < virtual_base:
        raise gdb.GdbError("device tree pointer is below the kernel virtual base")
    device_tree = device_tree_virtual - virtual_base + physical_base
    flattened = bytearray(inferior.read_memory(device_tree, device_tree_length))
    root = apple_device_tree.parse(flattened)
    chosen = apple_device_tree.child_named(flattened, root, "chosen")
    asmb = apple_device_tree.child_named(flattened, chosen, "asmb")
    old_name = "lp-sip0" if "lp-sip0" in asmb["properties"] else "lp-stng"
    apple_device_tree.replace_property(
        flattened, asmb, old_name, "lp-sip0", struct.pack("<Q", csr_config)
    )
    inferior.write_memory(device_tree, flattened)
    print(f"injected XNU CSR configuration: {csr_config:#x}")
breakpoint.delete()
gdb.execute("detach", to_string=True)
end
