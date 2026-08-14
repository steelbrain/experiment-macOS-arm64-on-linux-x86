# E0005: reliable eight-vCPU userspace boot under TCG

## Question

Can an arm64 VMApple guest reach and remain in XNU userspace with eight vCPUs
on an x86-64 Linux host using TCG?

## Environment

- Host OS and architecture: Linux, x86-64
- QEMU revision: `48e08c5e9e`
- Guest generation: macOS 13
- Machine contract: VMApple, TCG, `max` CPU, eight vCPUs, 8 GiB RAM
- Graphics contract: headless, inert software MMIO devices
- Storage contract: new private writable clones for every start

## Procedure

Build QEMU and run with the local inputs described in E0004, adding:

```sh
QEMU_27ON86_CPUS=8 scripts/27on86/run-vmapple-tcg.sh
```

For each run, query `info registers -a` through QMP and require a nonzero PC
for all eight CPUs. Save a raw physical-memory range containing kernel process
objects and verify the userspace transition with:

```sh
scripts/27on86/verify-launchd-ram.py local-ram-range.bin
```

Keep the VM running beyond the previous four-minute cross-call failure window.
Repeat from a new QEMU process and new writable storage clones. Finally repeat
with `QEMU_27ON86_CPUS=1` as a regression check.

## Observation

Two independent eight-vCPU starts powered all eight CPUs, reached a runnable
PID 1 named `launchd`, and remained running at 4:35 and 4:53 respectively.
The one-vCPU regression independently reached the same live PID 1 contract.

Secondary startup exposed two coupled TCG requirements:

- An implementation-defined pointer-authentication compatibility mode must
  generate signatures deterministically across vCPUs while accepting and
  stripping signatures that TCG cannot validate. Otherwise identical kernel
  function pointers compare unequal during per-CPU interrupt registration.
- Guest time must advance quickly through serialized CPU startup, then use a
  slower instruction-to-time conversion after all PSCI CPUs are powered. This
  keeps fixed guest cross-call deadlines meaningful under translated SMP
  execution without changing the architectural 24 MHz counter frequency.

The runner starts precise icount at shift 0 and the VMApple machine changes it
continuously to shift -4 after all CPUs are powered and the final secondary has
had 100 ms of guest time to initialize.

## Conclusion

VMApple can boot this arm64 guest reliably through AArch64 TCG on an x86-64
host with eight vCPUs. All eight CPUs become active and XNU reaches a live,
runnable PID 1 in repeated fresh starts without HVF or a host graphics
framework.

## Next experiment

Add a reachable guest console or service, then measure translated execution
and timer behavior before reducing the conservative post-startup time scale.
