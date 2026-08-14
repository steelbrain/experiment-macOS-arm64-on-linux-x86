# E0004: macOS userspace boot under TCG

## Question

Can a locally provisioned arm64 VMApple guest reach XNU userspace on an
x86-64 Linux host using TCG and no host graphics framework?

## Environment

- Host OS and architecture: Linux, x86-64
- QEMU revision: `1b2b73b7fc`
- Guest generation: macOS 13
- Machine contract: VMApple, TCG, `max` CPU, one vCPU, 8 GiB RAM
- Graphics contract: headless, inert software MMIO devices
- Storage contract: private writable clones presented through both boot and
  runtime interfaces

## Procedure

Build QEMU, set the four local-input environment variables required by the
runner, and start it:

```sh
scripts/27on86/build-aarch64.sh
QEMU_27ON86_FIRMWARE=/local/input \
QEMU_27ON86_AUX=/local/input \
QEMU_27ON86_ROOT=/local/input \
QEMU_27ON86_ECID=decimal-value \
scripts/27on86/run-vmapple-tcg.sh
```

The runner makes private reflink-capable working copies. It does not use
QEMU's snapshot mode because the boot and runtime views must share writes to
the same backing files. The AUX input is the raw 32 MiB pflash payload; any
outer metadata wrapper is not part of the pflash contract.

For each run, confirm XNU's version and platform logs, resolve the live kernel
slide, and inspect the process-list contract. Success requires a process with
PID 1 and the short name `launchd`. Repeat from new working copies and a new
QEMU process.

## Observation

Two independent clean starts completed both bootloader stages, entered XNU
22.6.0, initialized security policy and root storage, and produced a live PID
1 named `launchd`. The two runs used different kernel address slides. Neither
run panicked before or after the userspace transition.

The following compatibility limits remain:

- multi-vCPU operation requires the precise guest-time policy tested in
  E0005;
- pointer authentication instructions preserve pointer stripping, but the
  unavailable implementation-defined authentication cipher is not validated;
- the headless graphics windows accept probes but expose no rendering
  capability;
- some AES requests and storage barriers still take compatibility paths;
- the tested guest installation did not expose an SSH service.

## Conclusion

VMApple can boot an arm64 macOS 13 guest through AArch64 TCG on an x86-64
Linux host through XNU and into launchd. This result is repeatable from clean
starts without HVF or a host graphics framework.

## Next experiment

See E0005 for reliable eight-vCPU startup, then add a guest-side reachable
service or console path for interactive use.
