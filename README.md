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

Milestones M0 through M2 are complete on the x86-64 Linux development host. The
pinned QEMU baseline builds with native x86-64 TCG, the AArch64 Linux control
boot is repeatable, and VMApple executes repository-owned firmware through
TCG without an accelerator rejection, assertion, or reset loop. A locally
provisioned macOS 13 guest also boots through XNU into a live launchd process
with one vCPU and headless graphics. See:

- [Design](docs/design.md)
- [Roadmap](docs/roadmap.md)
- [Experiment records](docs/experiments/README.md)

## Repository rules

Guest images, firmware, boot artifacts, crash dumps, and other third-party
binary material are local inputs only. They must remain untracked. Persistent
project material records observed interfaces and original conclusions, never
third-party bytes or their provenance.
