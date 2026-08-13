# E0001: x86-64 AArch64 build baseline

## Question

Can the pinned QEMU baseline build an AArch64 system emulator with native
x86-64 TCG on the development host?

## Environment

- Host OS and architecture: Linux 7.1.3, x86-64
- Host CPU: x86-64
- C compiler: GCC 16.1.1
- Meson: 1.11.1
- Ninja: 1.13.2
- Upstream QEMU tag: `v11.1.0`
- Upstream QEMU commit: `84f07211cc5b4fc6a371559bf8a5de4fb068e648`
- Build configuration: debug AArch64 softmmu, documentation disabled
- Local input identifiers: none

## Procedure

Run:

```sh
scripts/27on86/build-aarch64.sh
build/qemu-system-aarch64 --version
build/qemu-system-aarch64 -accel help
```

## Observation

The build completed successfully. The resulting executable reports QEMU
11.1.0 and exposes TCG as its only accelerator. Meson selected the native
x86-64 TCG backend and generated the `aarch64-softmmu` target.

The upstream default AArch64 configuration does not include the VMApple
machine on this host. That is an M1 platform-configuration question rather
than a failure of the AArch64 TCG baseline.

## Conclusion

The pinned source and host toolchain can produce an AArch64 full-system
emulator whose guest instructions are translated to x86-64 by TCG.

## Next experiment

Boot a minimal AArch64 Linux control guest twice with an identical explicit
`virt` machine and CPU contract.
