# 27on86

27on86 is an experimental QEMU effort to run an arm64 macOS VMApple guest on
an x86-64 Mac using software CPU translation.

The project targets the VMApple virtual machine contract. It does **not** aim
to reproduce a physical Apple SoC, provide GPU acceleration, or bypass guest
security policy.

## Boot milestone

Reach a reproducible arm64 macOS boot checkpoint with QEMU's `vmapple` machine
and TCG on an x86-64 host. A serial console, useful boot log, or reachable
network service counts; a graphical desktop does not.

The first completed guest milestone is macOS 13. Later guest versions, ending
in macOS 27, are separate compatibility milestones.

## Project status

Milestones M0 through M2 are complete on the x86-64 Linux development host.
The macOS 13 VMApple guest now boots repeatably with eight vCPUs, exposes a
headless SSH service, passes CPU, memory, storage, networking, and timer
workloads, and shuts down cleanly. The one-vCPU configuration remains a
passing regression target. See:

- [Design](docs/design.md)
- [Roadmap](docs/roadmap.md)
- [Experiment records](docs/experiments/README.md)

The complete fresh-clone validation is:

```sh
scripts/27on86/validate-headless.py --runs 2 --cpus 8
```

It requires the local input environment documented by the experiment records.
The runner validates auxiliary NVRAM geometry before starting QEMU and leaves
all writable clones, generated keys, and logs under the ignored output tree.

## Repository rules

Guest images, firmware, boot artifacts, crash dumps, and other third-party
binary material are local inputs only. They must remain untracked. Persistent
project material records observed interfaces and original conclusions, never
third-party bytes or their provenance.
