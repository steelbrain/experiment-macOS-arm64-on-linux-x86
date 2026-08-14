# E0006: repeatable headless guest workloads

## Question

Can fresh VMApple storage clones provide remote command execution, networking,
representative workloads, and clean lifecycle behavior under eight-vCPU TCG?

## Environment

- Host OS and architecture: Linux, x86-64
- QEMU revision: `30db52796a`
- Guest generation: macOS 13
- Machine contract: VMApple, TCG, `max` CPU, 8 GiB RAM
- Primary configuration: eight vCPUs with the E0005 TCG time-scale contract
- Regression configuration: one vCPU
- Graphics contract: headless, inert software MMIO devices
- Storage contract: new private writable clones for every validation run
- Auxiliary-storage contract: valid mirrored NVRAM banks at bank-aligned offsets

## Procedure

Build QEMU, set the four local input variables described in E0004, and run:

```sh
scripts/27on86/validate-headless.py --runs 2 --cpus 8
```

The validator performs the following operations for each run:

1. Create new writable auxiliary and root-storage clones.
2. Start VMApple paused with a private serial socket, GDB port, QMP socket, and
   forwarded SSH port.
3. Configure the XNU command line and guest security policy at kernel handoff.
4. Mount the Data volume, establish firmlinks, start the minimum network and
   directory services, and expose a generated SSH identity.
5. Run architecture, CPU-count, memory, parallel CPU, storage, network, and
   monotonic-timer checks over SSH.
6. Request a guest halt and require a guest-originated QMP shutdown event.

After the two eight-vCPU runs, the validator repeats the complete procedure
with one vCPU unless `--skip-one-cpu-regression` is supplied.

To validate a real reset and second boot in the same QEMU process, run one
eight-vCPU validation with:

```sh
scripts/27on86/validate-headless.py --runs 1 --cpus 8 \
    --skip-one-cpu-regression --reboot-cycle
```

This enables QEMU reset, requests a guest reboot, requires a guest-originated
QMP RESET event, configures the second kernel handoff, restores SSH, verifies
the vCPU count, and then requires a clean guest halt.

Long serial uploads are divided into short, acknowledged base64 chunks. This
is required because a single-core translated guest may not drain an emulated
UART quickly enough to accept a large unacknowledged command.

## Observation

Two independent eight-vCPU runs passed the full workload and reported eight
online, active, and logical CPUs. Both touched and verified 256 MiB of memory,
ran eight concurrent digest workers, wrote and read back 32 MiB of storage,
fetched distinct payloads from a host HTTP service through user networking,
and measured a two-second monotonic interval within tolerance.

The runs emitted guest-originated clean shutdown events after 492.3 and 523.5
seconds. A fresh one-vCPU regression passed the same checks with one worker and
shut down cleanly after 238.6 seconds.

The reboot-cycle run emitted a guest-originated RESET event with reason
`guest-reset`, reached a second XNU handoff, restored SSH with eight online
vCPUs, and then emitted a guest-originated clean shutdown. The complete
boot-workload-reboot-boot-halt cycle took 1201.7 seconds.

The installed network service binds only when the emulated NIC presents the
stable VMApple address used by the guest's interface record. The runner now
uses that address by default while retaining an environment override.

An auxiliary image whose valid NVRAM banks are displaced from bank boundaries
causes a firmware shutdown before kernel handoff. The runner now rejects this
layout before creating a VM, while accepting boot-normalized auxiliary state.

## Conclusion

The macOS 13 VMApple guest is usable headlessly under AArch64 TCG on an x86-64
host with eight vCPUs. Fresh writable clones repeatedly support authenticated
host-to-guest commands, storage and network I/O, timer progress, concurrent CPU
work, clean guest reboot, a second boot, and clean guest shutdown. The one-vCPU
path remains functional.

## Next experiment

Use the lifecycle harness for the next guest version in the compatibility
ladder and record the first contract that diverges from this baseline.
