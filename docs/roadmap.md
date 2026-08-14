# Roadmap

## M0: Reproducible baseline

Status: complete. See E0001 and E0002 in `docs/experiments/`.

- Select and pin an upstream QEMU revision.
- Build `qemu-system-aarch64` on the x86-64 target host.
- Boot an arm64 Linux guest on QEMU's `virt` machine with TCG.
- Record CPU model, accelerator settings, host information, and timings.

Exit condition: the control guest boots twice from a clean process with the
same command-line contract.

## M1: VMApple under TCG

Status: complete. See E0003 in `docs/experiments/`.

- Identify VMApple assumptions tied to HVF or an arm64 host.
- Allow the machine to instantiate with TCG.
- Select an explicit emulated CPU model and feature contract.
- Make early failures observable through QEMU logging and serial output.

Exit condition: VMApple reaches its boot environment under x86-64 TCG without
a QEMU assertion, unsupported-accelerator rejection, or immediate reset loop.

## M2: Known-good guest boot

Status: complete for macOS 13 with one and eight vCPUs. See E0004 and E0005
in `docs/experiments/`.

- Use a locally provisioned VMApple guest.
- Classify failures as CPU, timer/interrupt, memory, boot, or device contract.
- Implement the smallest contract-correct fixes.
- Establish storage and networking.

Exit condition: two clean starts reach XNU userspace with a live PID 1.

## M3: Guest-version ladder

Advance one major macOS release at a time. For every version:

- preserve the last known-good configuration;
- capture the first divergent checkpoint;
- document contract changes independently of local artifact identity;
- add a regression test where practical.

Exit condition: macOS 27 reaches the M2 boot criterion.

## M4: Usability

- Reliable shutdown, reboot, storage, and networking.
- Remote interactive access without an emulated accelerated GPU.
- Stable multi-vCPU operation. Eight-vCPU boot is established in E0005;
  shutdown and longer-duration workload coverage remain.
- Installation or update workflow where legally and technically possible.

## M5: Performance

- Profile before changing translation behavior.
- Measure boot time, translated-code cache behavior, exits, atomics, barriers,
  timers, and device overhead.
- Optimize upstreamable hot paths first.
- Evaluate specialized cross-ISA translation only after TCG bottlenecks are
  demonstrated quantitatively.
