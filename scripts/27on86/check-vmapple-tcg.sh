#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_dir=${QEMU_27ON86_BUILD_DIR:-"$source_root/build"}
output_dir=${QEMU_27ON86_OUTPUT_DIR:-"$source_root/out"}
qemu="$build_dir/qemu-system-aarch64"
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/27on86-vmapple.XXXXXX")
firmware="$fixture_dir/firmware"
firmware_object="$fixture_dir/firmware.o"
aux="$fixture_dir/aux"
root="$fixture_dir/root"
log="$output_dir/vmapple-tcg-smoke.log"

cleanup()
{
    rm -f "$firmware" "$firmware_object" "$aux" "$root"
    rmdir "$fixture_dir"
}
trap cleanup EXIT HUP INT TERM

if ! test -x "$qemu"; then
    echo "missing emulator; run scripts/27on86/build-aarch64.sh" >&2
    exit 1
fi

clang --target=aarch64-none-elf \
    -c "$source_root/tests/27on86/vmapple-smoke.S" \
    -o "$firmware_object"
llvm-objcopy -O binary -j .text.boot "$firmware_object" "$firmware"
truncate -s 16384 "$aux"
truncate -s 16384 "$root"
mkdir -p "$output_dir"

status=0
timeout --signal=TERM 5s "$qemu" \
    -machine vmapple,uuid=1,accel=tcg \
    -cpu max \
    -smp 1 \
    -m 1G \
    -nodefaults \
    -display none \
    -monitor none \
    -serial stdio \
    -no-reboot \
    -bios "$firmware" \
    -drive file="$aux",if=pflash,format=raw \
    -drive file="$root",if=pflash,format=raw \
    >"$log" 2>&1 || status=$?

if test "$status" -ne 0 && test "$status" -ne 124; then
    cat "$log" >&2
    echo "VMApple TCG smoke test exited unexpectedly: $status" >&2
    exit 1
fi

grep -Fq 'VMAPPLE_TCG_SMOKE_OK' "$log"
echo "VMApple TCG smoke test: PASS"
