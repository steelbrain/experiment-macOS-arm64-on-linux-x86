#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_dir=${QEMU_27ON86_BUILD_DIR:-"$source_root/build"}
input_dir=${QEMU_27ON86_CONTROL_DIR:-"$source_root/artifacts/control"}
output_dir=${QEMU_27ON86_OUTPUT_DIR:-"$source_root/out"}
qemu="$build_dir/qemu-system-aarch64"

if ! test -x "$qemu"; then
    echo "missing emulator; run scripts/27on86/build-aarch64.sh" >&2
    exit 1
fi

for input in "$input_dir/a" "$input_dir/b"; do
    if ! test -f "$input"; then
        echo "missing opaque control input: $input" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"

run_control()
{
    run_number=$1
    log="$output_dir/tcg-control-$run_number.log"
    status=0

    timeout --signal=TERM 12s "$qemu" \
        -machine virt-11.1,accel=tcg \
        -cpu max \
        -smp 1 \
        -m 512M \
        -nodefaults \
        -display none \
        -monitor none \
        -serial stdio \
        -no-reboot \
        -kernel "$input_dir/a" \
        -initrd "$input_dir/b" \
        -append 'console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/bin/sh' \
        >"$log" 2>&1 || status=$?

    if test "$status" -ne 0 && test "$status" -ne 124; then
        echo "control run $run_number exited unexpectedly: $status" >&2
        return 1
    fi

    grep -Fq 'Booting Linux on physical CPU' "$log"
    grep -Fq 'Machine model: linux,dummy-virt' "$log"
    grep -Fq 'Run /bin/sh as init process' "$log"
    echo "control run $run_number: PASS"
}

run_control 1
run_control 2
