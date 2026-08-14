#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_dir=${QEMU_27ON86_BUILD_DIR:-"$source_root/build"}
output_dir=${QEMU_27ON86_OUTPUT_DIR:-"$source_root/out"}
qemu=${QEMU_27ON86_QEMU:-"$build_dir/qemu-system-aarch64"}
cpus=${QEMU_27ON86_CPUS:-1}
memory=${QEMU_27ON86_MEMORY:-8G}
ssh_port=${QEMU_27ON86_SSH_PORT:-10022}
mac=${QEMU_27ON86_MAC:-52:54:00:76:61:70}
pcap=${QEMU_27ON86_PCAP:-}
tcg_smp_final_shift=${QEMU_27ON86_TCG_SMP_FINAL_SHIFT:--4}
run_installer=${QEMU_27ON86_RUN_INSTALLER:-off}
serial=${QEMU_27ON86_SERIAL:-}
boot_args=${QEMU_27ON86_BOOT_ARGS:-}
trace_event=${QEMU_27ON86_TRACE_EVENT:-}
virtio_console_chardev=${QEMU_27ON86_VIRTIO_CONSOLE_CHARDEV:-}
virtio_console_max_ports=${QEMU_27ON86_VIRTIO_CONSOLE_MAX_PORTS:-31}
gdb_port=${QEMU_27ON86_GDB_PORT:-}
pause_at_start=${QEMU_27ON86_PAUSE_AT_START:-off}

: "${QEMU_27ON86_FIRMWARE:?set QEMU_27ON86_FIRMWARE}"
: "${QEMU_27ON86_AUX:?set QEMU_27ON86_AUX}"
: "${QEMU_27ON86_ROOT:?set QEMU_27ON86_ROOT}"
: "${QEMU_27ON86_ECID:?set QEMU_27ON86_ECID}"

for input in "$QEMU_27ON86_FIRMWARE" "$QEMU_27ON86_AUX" \
             "$QEMU_27ON86_ROOT"; do
    if ! test -f "$input"; then
        echo "missing local input: $input" >&2
        exit 1
    fi
done

if ! test -x "$qemu"; then
    echo "missing emulator; run scripts/27on86/build-aarch64.sh" >&2
    exit 1
fi

case "$cpus:$ssh_port:$virtio_console_max_ports:$QEMU_27ON86_ECID" in
    *[!0-9:]* | :* | *::*)
        echo "CPU count, SSH port, console port count, and ECID must be unsigned decimal values" >&2
        exit 1
        ;;
esac

case "$gdb_port" in
    '' | *[!0-9]*)
        if test -n "$gdb_port"; then
            echo "GDB port must be an unsigned decimal value" >&2
            exit 1
        fi
        ;;
esac

case "$mac" in
    [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:\
[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:\
[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f])
        ;;
    *)
        echo "MAC address must contain six hexadecimal octets" >&2
        exit 1
        ;;
esac

case "$tcg_smp_final_shift" in
    -10 | -[0-9] | [0-9] | 10)
        ;;
    *)
        echo "TCG SMP final shift must be between -10 and 10" >&2
        exit 1
        ;;
esac

case "$run_installer" in
    on | off)
        ;;
    *)
        echo "installer selector must be 'on' or 'off'" >&2
        exit 1
        ;;
esac

case "$pause_at_start" in
    on | off)
        ;;
    *)
        echo "pause-at-start selector must be 'on' or 'off'" >&2
        exit 1
        ;;
esac

mkdir -p "$output_dir"
run_dir=$(mktemp -d "$output_dir/vmapple-run.XXXXXX")
aux_work="$run_dir/aux.work"
root_work="$run_dir/root.work"

cp --reflink=auto -- "$QEMU_27ON86_AUX" "$aux_work"
cp --reflink=auto -- "$QEMU_27ON86_ROOT" "$root_work"

if test -n "$boot_args"; then
    "$script_dir/set-aux-boot-args.py" "$aux_work" "$boot_args"
fi

echo "VMApple run directory: $run_dir"

if test -z "$serial"; then
    serial="file:$run_dir/serial.log"
fi

set --
if test "$cpus" -gt 1; then
    set -- "$@" -icount shift=0,align=off,sleep=off
    machine="vmapple,uuid=$QEMU_27ON86_ECID,accel=tcg,run-installer=$run_installer,tcg-smp-final-shift=$tcg_smp_final_shift"
else
    machine="vmapple,uuid=$QEMU_27ON86_ECID,accel=tcg,run-installer=$run_installer"
fi

if test -n "$pcap"; then
    set -- "$@" -object "filter-dump,id=netcap,netdev=net0,file=$pcap"
fi

if test -n "$trace_event"; then
    set -- "$@" -trace "enable=$trace_event,file=$run_dir/trace.log"
fi

if test -n "$virtio_console_chardev"; then
    set -- "$@" \
        -chardev "$virtio_console_chardev,id=vconsole0" \
        -device "virtio-serial-pci,id=vserial0,max_ports=$virtio_console_max_ports" \
        -device virtconsole,id=vconsoleport0,chardev=vconsole0
fi

if test -n "$gdb_port"; then
    set -- "$@" -gdb "tcp::$gdb_port"
fi

if test "$pause_at_start" = on; then
    set -- "$@" -S
fi

exec "$qemu" \
    -machine "$machine" \
    -cpu max \
    -smp "$cpus" \
    "$@" \
    -m "$memory" \
    -display none \
    -monitor none \
    -serial "$serial" \
    -qmp "unix:$run_dir/qmp.sock,server=on,wait=off" \
    -action panic=pause,shutdown=pause \
    -no-reboot \
    -bios "$QEMU_27ON86_FIRMWARE" \
    -drive "if=pflash,format=raw,file.filename=$aux_work,file.locking=off" \
    -drive "if=pflash,format=raw,file.filename=$root_work,file.locking=off" \
    -drive "if=none,format=raw,file.filename=$aux_work,file.locking=off,id=aux" \
    -device vmapple-virtio-blk-pci,variant=aux,drive=aux,share-rw=on \
    -drive "if=none,format=raw,file.filename=$root_work,file.locking=off,id=root" \
    -device vmapple-virtio-blk-pci,variant=root,drive=root,share-rw=on \
    -netdev "user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:$ssh_port-:22" \
    -device "virtio-net-pci,netdev=net0,mac=$mac"
