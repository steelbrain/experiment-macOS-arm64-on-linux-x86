# 27on86

27on86 is an experimental QEMU effort to run an arm64 macOS VMApple guest on
an x86-64 Mac using software CPU translation.

The project targets the VMApple virtual machine contract. It does **not** aim
to reproduce a physical Apple SoC, provide GPU acceleration, or bypass guest
security policy.

## First milestone

Reach a reproducible macOS 12 boot checkpoint with QEMU's `vmapple` machine
and TCG on an x86-64 host. A serial console, useful boot log, or reachable
network service counts; a graphical desktop does not.

macOS 12 is the initial compatibility target because upstream VMApple support
already establishes it as a known-good guest. Later guest versions, ending in
macOS 27, are separate compatibility milestones.

## Project status

The experiment is in its contract and baseline phase. See:

- [Design](docs/design.md)
- [Roadmap](docs/roadmap.md)
- [Experiment records](docs/experiments/README.md)

## Repository rules

Guest images, firmware, boot artifacts, crash dumps, and other third-party
binary material are local inputs only. They must remain untracked. Persistent
project material records observed interfaces and original conclusions, never
third-party bytes or their provenance.
