# E0002: Repeated AArch64 TCG control boot

## Question

Can the x86-64 build execute an AArch64 Linux system through TCG to a stable,
repeatable userspace checkpoint?

## Environment

- Host OS and architecture: Linux 7.1.3, x86-64
- Host CPU: x86-64
- QEMU revision: `22cd91aa7e`
- Machine contract: `virt-11.1`, TCG, `max` CPU, one vCPU, 512 MiB RAM
- Control input A SHA-256:
  `1a2fa67cb25a2fa9065818712d50d0d543526818b3c6b43695e54deaca33d66d`
- Control input B SHA-256:
  `df5281b4c36f812d0507e219e31a8a7482e0b4175097e292b75c7872c441295c`

## Procedure

Place the two opaque control inputs at `artifacts/control/a` and
`artifacts/control/b`, then run:

```sh
scripts/27on86/check-tcg-control.sh
```

The check launches two clean QEMU processes with an identical command line.
Each process must report CPU entry, the expected virtual machine model, and
entry into the initramfs shell before the harness terminates it.

## Observation

Both independent runs passed. The first reached the userspace checkpoint at
5.45 guest seconds and the second at 5.81 guest seconds. Both reported the
same AArch64 CPU identifier and virtual machine model.

## Conclusion

The host, QEMU build, AArch64 TCG backend, architectural timer, interrupt
controller, memory map, serial device, kernel loader, and initramfs path work
together reproducibly. M0's control-boot exit condition is satisfied.

## Next experiment

Enable the VMApple machine with TCG, select a realizable emulated CPU model,
and classify the first machine-instantiation failure without using guest boot
artifacts.
