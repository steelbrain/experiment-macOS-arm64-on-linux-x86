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
mac=${QEMU_27ON86_MAC:-52:54:00:12:34:56}
pcap=${QEMU_27ON86_PCAP:-}

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

case "$cpus:$ssh_port:$QEMU_27ON86_ECID" in
    *[!0-9:]* | :* | *::*)
        echo "CPU count, SSH port, and ECID must be unsigned decimal values" >&2
        exit 1
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

mkdir -p "$output_dir"
run_dir=$(mktemp -d "$output_dir/vmapple-run.XXXXXX")
aux_work="$run_dir/aux.work"
root_work="$run_dir/root.work"

cp --reflink=auto -- "$QEMU_27ON86_AUX" "$aux_work"
cp --reflink=auto -- "$QEMU_27ON86_ROOT" "$root_work"

echo "VMApple run directory: $run_dir"

set --
if test "$cpus" -gt 1; then
    set -- "$@" -icount shift=0,align=off,sleep=off
    machine="vmapple,uuid=$QEMU_27ON86_ECID,accel=tcg,tcg-smp-final-shift=-4"
else
    machine="vmapple,uuid=$QEMU_27ON86_ECID,accel=tcg"
fi

if test -n "$pcap"; then
    set -- "$@" -object "filter-dump,id=netcap,netdev=net0,file=$pcap"
fi

exec "$qemu" \
    -machine "$machine" \
    -cpu max \
    -smp "$cpus" \
    "$@" \
    -m "$memory" \
    -display none \
    -monitor none \
    -serial "file:$run_dir/serial.log" \
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
