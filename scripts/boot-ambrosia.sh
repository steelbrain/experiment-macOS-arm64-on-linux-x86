#!/usr/bin/env bash
# Boots an installed arm64 macOS guest on Ambrosia with reims-vgpu's QEMU under TCG, on reflink
# clones of its disks, with persistent serial, QEMU and QMP logs. The command line is the one
# reims-vgpu's firmware/ambrosia/check-boot.sh gives with -t (TCG). The guest's own files are never
# booted or written.
#
# VM_DIR holds disk.img, aux.img.trimmed (or aux.img, of which a trimmed copy is made: the same
# without its first 16 KiB) and vm.toml, whose `ecid` line is the guest's ECID unless -e gives it.
#
# usage: scripts/boot-ambrosia.sh [-c CPUS] [-m RAM] [-b BUNDLE] [-p PORT] [-o OUT] [-e ECID] [-k]
#                                 VM_DIR [-- extra QEMU args]
#   -c  vCPUs (default 4)
#   -m  guest RAM (default 8G), a shared memfd as reims-ctl and check-boot give it on Linux
#   -b  configuration bundle (default: scripts/build.sh's Config.cpio under WORK; `none` for none)
#   -p  host port forwarded to the guest's SSH (default 10090)
#   -o  log directory, new (default logs/ambrosia-tcg-<time> under the repository)
#   -e  ECID (default: vm.toml's ecid)
#   -k  keep the clones after QEMU exits
# env:  QEMU, AMBROSIA (the binaries, default scripts/build.sh's under WORK), WORK (~/work),
#       REIMS_VGPU_LOG (info), REIMS_VGPU_WINDOW (0)
#
# Runs QEMU in the foreground; stop it with Ctrl-C or QMP `quit`. QMP is at OUT/qmp.sock.
# shellcheck disable=SC2054 # QEMU's options are comma lists, not array separators
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "boot-ambrosia: $*" >&2; exit 2; }
WORK=${WORK:-$HOME/work}
cpus=4 ram=8G bundle=$WORK/reims-vgpu/firmware/ambrosia/build/Config.cpio port=10090 out='' ecid=''
keep=0
while getopts c:m:b:p:o:e:kh opt; do
  case $opt in
  c) cpus=$OPTARG ;; m) ram=$OPTARG ;; b) bundle=$OPTARG ;; p) port=$OPTARG ;;
  o) out=$OPTARG ;; e) ecid=$OPTARG ;; k) keep=1 ;;
  *) sed -n '/^# usage:/,/^# Runs QEMU/p' "$0" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 ]] || die "give the guest's directory"
vm=$(cd "$1" && pwd) || die "no directory $1"
shift
[[ ${1:-} == -- ]] && shift
extra=("$@")

QEMU=${QEMU:-$WORK/reims-vgpu/build/qemu-aarch64/qemu-system-aarch64}
AMBROSIA=${AMBROSIA:-$WORK/ambrosia/target/ambrosia.bin}
[[ $bundle == none ]] && bundle=''
[[ -x $QEMU ]] || die "no QEMU at $QEMU"
[[ -f $AMBROSIA ]] || die "no Ambrosia image at $AMBROSIA"
[[ -z $bundle || -f $bundle ]] || die "no bundle $bundle (give -b none to boot without one)"
[[ -f $vm/disk.img ]] || die "no $vm/disk.img"
[[ -f $vm/aux.img.trimmed || -f $vm/aux.img ]] || die "no $vm/aux.img.trimmed or $vm/aux.img"
if [[ -z $ecid ]]; then
  ecid=$(sed -n 's/^ecid *= *"\{0,1\}\([0-9a-fA-Fx]*\)"\{0,1\} *$/\1/p' "$vm/vm.toml" 2> /dev/null | head -1)
  [[ -n $ecid ]] || die "no ECID in $vm/vm.toml; give -e"
fi
[[ -n $out ]] || out=$here/../logs/ambrosia-tcg-$(date +%Y%m%d-%H%M%S)
mkdir -p "$(dirname "$out")"
mkdir "$out" || die "can't make $out (it must be new)"
out=$(cd "$out" && pwd)

mkdir "$out/clone"
cp --reflink=always "$vm/disk.img" "$out/clone/disk.img" || die "can't reflink $vm/disk.img into $out"
if [[ -f $vm/aux.img.trimmed ]]; then
  cp --reflink=always "$vm/aux.img.trimmed" "$out/clone/aux.img.trimmed"
else
  dd if="$vm/aux.img" of="$out/clone/aux.img.trimmed" bs=16384 skip=1 2> /dev/null || die "can't trim $vm/aux.img"
fi
# shellcheck disable=SC2329 # run by the EXIT trap
cleanup() { ((keep)) || rm -rf "$out/clone"; }
trap cleanup EXIT

loader=()
[[ -n $bundle ]] && loader=(-device "loader,file=$bundle,addr=0x120000000,force-raw=on")
cmd=(env REIMS_VGPU_WINDOW="${REIMS_VGPU_WINDOW:-0}" REIMS_VGPU_LOG="${REIMS_VGPU_LOG:-info}"
  "$QEMU" -accel tcg,thread=multi
  -M "vmapple,uuid=$ecid,memory-backend=ram,dump-guest-core=off"
  -m "$ram" -object "memory-backend-memfd,id=ram,size=$ram,share=on"
  -smp "$cpus" -bios "$AMBROSIA"
  -drive "file=$out/clone/aux.img.trimmed,if=pflash,format=raw"
  -drive "file=$out/clone/disk.img,if=pflash,format=raw"
  -drive "file=$out/clone/aux.img.trimmed,if=none,id=aux,format=raw"
  -drive "file=$out/clone/disk.img,if=none,id=root,format=raw"
  -device vmapple-virtio-blk-pci,variant=aux,drive=aux
  -device vmapple-virtio-blk-pci,variant=root,drive=root
  -netdev "user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:$port-:22"
  -device virtio-net-pci,netdev=net0,romfile=
  -device reims-graphics-pci
  "${loader[@]}"
  -display none -serial "file:$out/serial.log"
  -qmp "unix:$out/qmp.sock,server=on,wait=off"
  "${extra[@]}")
printf '%q ' "${cmd[@]}" > "$out/command.sh"
echo >> "$out/command.sh"
{
  echo "host: $(uname -r) $(uname -m)"
  echo "qemu: $QEMU $(sha256sum < "$QEMU" | cut -c1-16)"
  echo "ambrosia: $AMBROSIA $(sha256sum < "$AMBROSIA" | cut -c1-16)"
  echo "bundle: ${bundle:-none} ${bundle:+$(sha256sum < "$bundle" | cut -c1-16)}"
  echo "guest: $vm ecid $ecid; tcg, $cpus vCPU, $ram"
} > "$out/run.txt"
cat "$out/run.txt"
echo "boot-ambrosia: logs in $out"
rc=0
"${cmd[@]}" > "$out/qemu.log" 2>&1 < /dev/null || rc=$?
echo "boot-ambrosia: QEMU exited $rc" | tee -a "$out/run.txt"
exit "$rc"
