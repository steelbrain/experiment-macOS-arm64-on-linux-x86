# macOS on x86-64 Linux under TCG

Boots an installed arm64 macOS guest on an x86-64 Linux host, with QEMU's TCG
translating the guest's arm64 code. The guest runs in QEMU's `vmapple` machine
on [Ambrosia](https://github.com/steelbrain/ambrosia), which replaces Apple's
AVPBooter and iBoot. It displays through
[reims-vgpu](https://github.com/steelbrain/reims-vgpu)'s `reims-graphics-pci`
device, which renders with Vulkan on the host's GPU.

This repository holds the scripts that build the pinned sources and boot or
check a guest. Nothing is patched: reims-vgpu's QEMU, Ambrosia and reims-vgpu's
configuration bundle run macOS 27 under TCG as they are. This is research code,
not a virtual-machine product.

The QEMU fork and experiment records this repository held before are on the
`vmapple-tcg` branch.

## Status (2026-11-11)

TBD

## Pinned sources

`scripts/build.sh` clones and builds these commits:

| Source | Commit |
| --- | --- |
| reims-vgpu `development` | `6179228984e33c643799b2249f5a5f6bea1d1fac` |
| its `vendor/qemu` ([qemu-reims-vgpu](https://github.com/steelbrain/qemu-reims-vgpu)) | `b95dc452f7087ec21c9bb3787518a81aee53e62a` |
| [metal2vulkan](https://github.com/steelbrain/metal2vulkan), as reims-vgpu's `Cargo.toml` names it | `30cadd8dda54670522e0d9dce59205fe7c84a023` |
| Ambrosia v0.1.2 | `db6aa658fef8f20097d6a24fe85536bfecfc15d8` |

## What TCG needs

macOS was built for Apple silicon under Apple's hypervisor. Under TCG, QEMU
emulates the CPU, and these are the differences macOS meets. Each is handled in
reims-vgpu's `vendor/qemu` at the pinned commit:

| Under TCG | Handled by |
| --- | --- |
| `vmapple` needed HVF, and its default CPU was `host`, which TCG does not have | QEMU `a52f4a20`: `vmapple` builds without HVF, and its default CPU is `max` |
| TCG's generic timer counts at 1 GHz, while macOS's device tree gives every CPU a 24 MHz timebase | QEMU `a52f4a20`: under TCG, `vmapple` sets each CPU's `cntfrq` to 24 MHz |
| macOS makes pointer-authentication calls (SMCCC 0xC1000000-0xC10000FF) over HVC | QEMU `a52f4a20`: QEMU answers them as not supported, as Hypervisor.framework does under HVF |
| macOS writes a DMA request to a doorbell at 0x4ffff8, where the machine has no device. Under TCG that write is an external abort, and a 27.0.1 kernel panics on it | QEMU `58a6f887`: an unimplemented device there ignores the write |
| The `max` CPU offers SME with streaming vectors of up to 2048 bits, and a macOS 14.6.1 kernel panics sizing its SME state | QEMU `d2bd3447`: no SME by default on `vmapple` under TCG. macOS 27 boots either way |

The guest's RAM is a shared memfd (`memory-backend-memfd,share=on`), so
reims-vgpu maps the guest's pages for the GPU in place, through `/dev/udmabuf`,
instead of copying each IOSurface.

On Asahi Linux under KVM, macOS's GIC driver uses a store that KVM cannot
emulate, and
[experiment-macOS-arm64-on-asahi-linux-arm64](https://github.com/steelbrain/experiment-macOS-arm64-on-asahi-linux-arm64)
patches it at boot. TCG emulates every instruction, so this repository boots
reims-vgpu's configuration bundle unchanged.

## Requirements

TBD

Do not commit or share guest files: the disk holds an installed copy of macOS,
and the auxiliary storage and ECID identify the VM.

## 1. Build

On the x86-64 Linux host, from a clone of this repository:

```sh
CONFIRM=1 scripts/build.sh
scripts/check-host.sh
```

`build.sh` clones the pinned sources into `$WORK` (default `~/work`), refuses a
checkout at any other commit or with local changes, and builds them without
patches: reims-vgpu's library, `qemu-system-aarch64` with TCG and
`reims-graphics-pci`, `ambrosia.bin`, and reims-vgpu's Ambrosia configuration
bundle, `Config.cpio` (its early-console module, Graft, ReimsGraphics and
RgfxGate). Logs go to `$WORK/logs`.

`check-host.sh` checks the architecture, that the built QEMU has the `vmapple`
machine, TCG and `reims-graphics-pci`, that `/dev/udmabuf` is usable, and lists
the Vulkan devices.

## 2. Boot

```sh
scripts/boot-ambrosia.sh -o ~/work/logs/boot-1 ~/guests/macos
```

QEMU runs in the foreground under TCG with 4 vCPUs and 8 GiB of RAM, on reflink
clones of the guest's disks, with `~/work`'s `Config.cpio` as the configuration
bundle (`-b`). Stop it with Ctrl-C or with QMP `quit` on `OUT/qmp.sock`.
Serial, QEMU and QMP logs go to the `-o` directory, which must be on the guest's
filesystem for the clones to be reflinks. The guest's SSH is forwarded to host
port 10090 (`-p`).

## 3. Run reims-vgpu's boot check

reims-vgpu's `firmware/ambrosia/check-boot.sh` runs under TCG with `-t`:

```sh
GUEST_USER=... GUEST_PASS=... ~/work/reims-vgpu/firmware/ambrosia/check-boot.sh -t \
  -f ~/work/ambrosia/target/ambrosia.bin \
  -q ~/work/reims-vgpu/build/qemu-aarch64/qemu-system-aarch64 \
  -T ~/guest-tools -o ~/work/logs/check-1 ~/guests/macos
```

It boots the guest with the same command line as `boot-ambrosia.sh`, logs in
over SSH, and runs 14 checks, from the firmware's console to an on-screen Metal
app's presented frames. Under `-t` its time limits are five times those under
HVF, and it does not judge the Metal app's frame pacing.

TBD minibuddy

## Known issues

TBD

## Project boundaries

- Never commit firmware, IPSWs, restore images, VM disks, VM identities, or
  logs. The repository's ignore rules cover the expected locations and
  formats.
- This project does not redistribute macOS or bypass Apple's restore signing.
- There is no support promise. Reproduction reports with exact host, kernel,
  QEMU, firmware, and guest versions are welcome.
