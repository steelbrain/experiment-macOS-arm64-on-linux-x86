# E0003: VMApple firmware execution under TCG

## Question

Can VMApple instantiate on an x86-64 host with TCG, realize an emulated
AArch64 CPU, enter its firmware region, and operate a platform device without
an accelerator rejection, assertion, or reset loop?

## Environment

- Host OS and architecture: Linux 7.1.3, x86-64
- Host CPU: x86-64
- QEMU revision: `7107b001c8`
- Machine contract: VMApple, TCG, `max` CPU, one vCPU, 1 GiB RAM
- Graphics contract: headless; no Apple host graphics framework
- Local input identifiers: none

## Procedure

Run:

```sh
scripts/27on86/build-aarch64.sh
scripts/27on86/check-vmapple-tcg.sh
```

The check assembles repository-owned AArch64 firmware in a temporary
directory, creates empty temporary storage fixtures, and starts VMApple with
TCG. The firmware writes a marker through the VMApple UART and then waits for
interrupts. The harness requires that marker and removes all fixtures.

## Observation

The VMApple machine is present in `-machine help`. It realizes the `max`
AArch64 CPU and userspace GICv3 under TCG, enters the firmware region at the
VMApple reset address, writes `VMAPPLE_TCG_SMOKE_OK` through the PL011 device,
and remains running until the harness terminates it.

The baseline required four source corrections:

- VMApple must be selectable when AArch64 TCG is enabled, without requiring
  HVF.
- VMApple must implement QEMU's AArch64 machine interface to appear in the
  target's machine list.
- TCG must use an emulated CPU model instead of the accelerator-only `host`
  CPU model.
- VMApple graphics must be optional when its host framework is unavailable.

A separate C portability correction makes the AES device build with a
compiler that treats a block-scope `const` array bound as a variable-length
array.

## Conclusion

The VMApple machine contract can instantiate and execute firmware through
AArch64 TCG on an x86-64 host without an accelerator rejection, assertion, or
reset loop. CPU execution, reset-vector placement, userspace GIC realization,
memory mapping, configuration devices, storage backends, and serial output
all pass the controlled smoke checkpoint.

This result does not claim that a macOS boot environment or guest kernel has
run. That requires locally provisioned guest inputs and is the next
compatibility layer.

## Next experiment

Run a locally provisioned known-good VMApple boot environment with the same
explicit TCG CPU contract and classify its first divergence from the upstream
HVF path.
