#!/usr/bin/env bash
# Checks that this host can run the guest: an x86-64 Linux kernel, scripts/build.sh's QEMU with the
# vmapple machine, TCG and reims-graphics-pci, /dev/udmabuf usable by this user (reims-vgpu maps the
# guest's pages for the GPU through it), and a Vulkan device (a warning where all are CPU
# implementations such as llvmpipe).
#
# usage: scripts/check-host.sh
# env:   QEMU (default: scripts/build.sh's, under WORK), WORK (~/work)
set -euo pipefail

die() { echo "check-host: $*" >&2; exit 1; }
WORK=${WORK:-$HOME/work}
QEMU=${QEMU:-$WORK/reims-vgpu/build/qemu-aarch64/qemu-system-aarch64}

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die "this needs an x86-64 Linux host"
[[ -x $QEMU ]] || die "no QEMU at $QEMU (run scripts/build.sh, or set QEMU)"
machines=$("$QEMU" -machine help)
accels=$("$QEMU" -accel help)
devices=$("$QEMU" -device help)
grep -q '^vmapple ' <<< "$machines" || die "$QEMU has no vmapple machine"
grep -qx tcg <<< "$accels" || die "$QEMU was built without TCG"
grep -q '"reims-graphics-pci"' <<< "$devices" || die "$QEMU has no reims-graphics-pci device"
[[ -e /dev/udmabuf ]] || die "no /dev/udmabuf (sudo modprobe udmabuf)"
[[ -r /dev/udmabuf && -w /dev/udmabuf ]] ||
  die "$(id -un) cannot use /dev/udmabuf (add the user to its group, $(stat -c %G /dev/udmabuf))"
command -v vulkaninfo > /dev/null || die "needs vulkaninfo (vulkan-tools) to list the Vulkan devices"
gpus=$(vulkaninfo --summary 2> /dev/null | sed -n 's/^[[:space:]]*deviceName *= *//p')
[[ -n $gpus ]] || die "Vulkan lists no device"
grep -qv -i -E 'llvmpipe|lavapipe|swiftshader' <<< "$gpus" ||
  echo "check-host: warning: Vulkan lists only CPU implementations; this flow was tested on a GPU" >&2

printf 'architecture: %s\n' "$(uname -m)"
printf 'kernel: %s\n' "$(uname -r)"
printf 'QEMU: %s\n' "$QEMU"
printf 'Vulkan devices: %s\n' "$(paste -sd, <<< "$gpus" | sed 's/,/, /g')"
printf 'TCG, vmapple, reims-graphics-pci, udmabuf: usable\n'
