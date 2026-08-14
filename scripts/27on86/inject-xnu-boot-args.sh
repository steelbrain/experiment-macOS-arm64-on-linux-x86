#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
gdb=${QEMU_27ON86_GDB_BIN:-gdb}

: "${QEMU_27ON86_GDB_PORT:?set QEMU_27ON86_GDB_PORT}"
: "${QEMU_27ON86_XNU_BOOT_ARGS:?set QEMU_27ON86_XNU_BOOT_ARGS}"

case "$QEMU_27ON86_GDB_PORT" in
    *[!0-9]* | '')
        echo "GDB port must be an unsigned decimal value" >&2
        exit 1
        ;;
esac

exec "$gdb" -nx -q -batch -x "$script_dir/inject-xnu-boot-args.gdb"
