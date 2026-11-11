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

Host: a Ryzen 7 8745H with a Radeon 780M, on CachyOS with kernel
`7.3.3-1-cachyos` and Mesa 26.2.6 (RADV). Its details are under
[Requirements](#requirements).

Built by `scripts/build.sh` from an empty `$WORK` at the pins below, both
guests pass all 15 checks of reims-vgpu's `firmware/ambrosia/check-boot.sh`
under TCG (`-t`) with 4 vCPUs. The build took 6 min 57 s, with the Rust
toolchains and Cargo's download cache already on the host.

| Guest | Checks | SSH login after QEMU starts | Metal app, 10 s on screen | Whole check |
| --- | --- | --- | --- | --- |
| macOS 27.0.1 (26A434) | 15 of 15 | 115.9 s | 172 frames presented, 30 dropped, 24.5 fps | 9 min 7 s |
| macOS 27.2.1 (26B131) | 15 of 15 | 123.5 s | 238 frames presented, 168 dropped, 56.6 fps | 8 min 50 s |

- The desktop renders on the 780M. QEMU's screendump at the end of each check
  shows Finder's menu bar, the Dock and the desktop widgets (27.0.1: 481,375
  distinct colours; 27.2.1: 440,992; the check fails a screen of one colour).
- System Integrity Protection is enabled and `kern.bootargs` is empty.
  reims-vgpu's kexts (Graft, ReimsGraphics, RgfxGate) load, and the guest's
  Metal device is `AMD Radeon 780M Graphics (RADV PHOENIX)`.
- Under `-t`, the check passes the Metal app on presented frames and does not
  judge its dropped frames: the emulated CPU sets the rate at which
  WindowServer composites.
- The 27.0.1 guest was first copied with `scripts/prepare-guest-nominibuddy.sh`
  (step 3), which took 12 min 15 s. Before that it passed 14 of 15: Setup
  Assistant's "Sign In to Your Apple Account" covered the session, and the
  check reported the Metal app as unread. The 27.2.1 guest needed no copy.

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
| The `max` CPU offers SME with streaming vectors of up to 2048 bits, and a macOS 14.6.1 kernel panics sizing its SME state | QEMU `d2bd3447`: no SME by default on `vmapple` under TCG. macOS 27.0.1 boots either way |

The guest's RAM is a shared memfd (`memory-backend-memfd,share=on`), so
reims-vgpu maps the guest's pages for the GPU in place, through `/dev/udmabuf`,
instead of copying each IOSurface.

On Asahi Linux under KVM, macOS's GIC driver uses a store that KVM cannot
emulate, and
[experiment-macOS-arm64-on-asahi-linux-arm64](https://github.com/steelbrain/experiment-macOS-arm64-on-asahi-linux-arm64)
patches it at boot. TCG emulates every instruction, so this repository boots
reims-vgpu's configuration bundle unchanged.

## Requirements

- An x86-64 Linux host with a GPU that has a Vulkan driver. Tested: a Ryzen 7
  8745H (8 cores, 16 threads) with its Radeon 780M and 29 GiB of RAM, on
  CachyOS with kernel `7.3.3-1-cachyos` and Mesa 26.2.6, whose Vulkan driver
  for the GPU is RADV. KVM is not used.
- Where Vulkan lists more than one GPU, reims-vgpu times each and uses the
  fastest. To choose one, set `MESA_VK_DEVICE_SELECT=<vendor>:<device>!` for
  QEMU. The test host also has an RTX 3090, and every run below set
  `MESA_VK_DEVICE_SELECT=1002:1900!` (the 780M).
- `/dev/udmabuf` usable by your user. reims-vgpu maps the guest's memory for
  the GPU through it. On CachyOS it belongs to the `kvm` group:
  `sudo usermod -aG kvm "$USER"`, then log in again.
- Build packages and rustup. On CachyOS or Arch Linux:

  ```sh
  sudo pacman -S --needed base-devel git curl python ninja pkgconf flex bison bzip2 cmake \
    glib2 pixman libslirp zlib dtc gnutls pipewire libpulse alsa-lib libusb spice \
    vulkan-icd-loader vulkan-tools libx11 libxext libxrandr libxcursor libxi libxfixes libxss \
    libxtst libxkbcommon wayland libdecor mesa libdrm dbus systemd-libs gtk3 clang lld cpio \
    sshpass perl
  curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none --profile minimal
  ```

  Add your GPU's Vulkan driver (`vulkan-radeon` for AMD). The list is
  reims-vgpu's `scripts/install-ctl.sh` list with `gnutls`, `vulkan-tools`,
  `clang`, `lld`, `cpio`, `sshpass` and `perl` added. reims-vgpu's and
  Ambrosia's `rust-toolchain.toml` files select their toolchains.
- An installed arm64 macOS VM. This repository does not install or restore
  macOS: Virtualization.framework installs it, on an Apple silicon Mac.
  Supply the installed VM as a directory holding:
  - `disk.img`, the installed system disk, raw;
  - `aux.img`, the VM's auxiliary storage, or `aux.img.trimmed`, the same
    without its first 16 KiB;
  - `vm.toml`, with the line `ecid = <the VM's ECID in decimal>`.

  Tested with macOS 27.0.1 (26A434) and 27.2.1 (26B131). The scripts boot
  reflink clones of the disks, so the directory must be on a filesystem with
  reflinks (btrfs, or XFS with reflink), and the guest's own files are never
  written.
- For the boot check only: reims-vgpu's guest probes `bench` and
  `present_probe`, which build with Xcode on a Mac, from a checkout of
  reims-vgpu at the pinned commit:
  `make -C firmware/ambrosia guest-tools`, then copy
  `firmware/ambrosia/build/guest-tools` to the host.
- Memory: the guest gets 8 GiB. The jobs that ran the boot checks above
  peaked at 12.9 to 13.5 GiB, page cache included.
- Disk space: the guest's sparse disk, a reflink clone per boot, `$WORK` at
  7.3 GiB after the build, the two Rust toolchains at 2.7 GiB, and Cargo's
  download cache.

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

It boots the guest as `boot-ambrosia.sh` does, with `~/work`'s `Config.cpio`,
logs in over SSH, and runs 15 checks, from Ambrosia's entry into the kernel to
QMP's screendump at the end. The script's header describes each. Under `-t` it
waits 300 s for the SSH login and 300 s more for the desktop, gives each command
in the guest five times its limit under HVF, and prints the Metal app's dropped
frames without judging them.

If Setup Assistant opens at the guest's login, it covers the session, and the
check reports the Metal app as unread, as it did for the 27.0.1 guest above.
Make a copy of the guest without it first. This boots a clone under TCG, waits
for the desktop, runs reims-vgpu's `scripts/internal/guest-minibuddy-off.sh` in
it, shuts it down and keeps the clone:

```sh
GUEST_USER=... GUEST_PASS=... scripts/prepare-guest-nominibuddy.sh \
  ~/guests/macos ~/guests/macos-nominibuddy
```

## Project boundaries

- Never commit firmware, IPSWs, restore images, VM disks, VM identities, or
  logs. The repository's ignore rules cover the expected locations and
  formats.
- This project does not redistribute macOS or bypass Apple's restore signing.
- There is no support promise. Reproduction reports with exact host, kernel,
  QEMU, firmware, and guest versions are welcome.
