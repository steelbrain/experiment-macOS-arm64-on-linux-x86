#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_dir=${QEMU_27ON86_BUILD_DIR:-"$source_root/build"}

mkdir -p "$build_dir"

(
    cd "$build_dir"
    "$source_root/configure" \
        --target-list=aarch64-softmmu \
        --enable-debug \
        --disable-docs \
        --disable-werror
)

ninja -C "$build_dir" qemu-system-aarch64

