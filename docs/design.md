# Design

## Objective

Execute an arm64 VMApple macOS guest on an x86-64 host by combining QEMU's
VMApple device model with QEMU's Tiny Code Generator (TCG).

The core path is:

```text
arm64 macOS guest
        |
VMApple virtual platform
        |
QEMU AArch64 system emulation
        |
TCG translation to x86-64
```

## Scope

The initial system provides:

- AArch64 CPU execution through TCG.
- The virtual CPU feature set expected by a VMApple guest.
- VMApple interrupt, timer, configuration, storage, and networking contracts.
- Headless diagnostics and operation.
- Reproducible builds and experiments.

The initial system does not provide:

- Physical Apple SoC emulation.
- GPU or display acceleration.
- Same-architecture hardware virtualization.
- Guest modification as a substitute for a correct virtual platform.

## Working hypotheses

1. The VMApple guest kernel targets a virtual platform rather than a physical
   M-series SoC, keeping the required device surface tractable.
2. QEMU TCG implements enough of the required AArch64 architecture to enter
   the guest boot environment on x86-64.
3. Remaining failures can be separated into CPU-contract, platform-contract,
   boot-contract, and performance problems.
4. A known-good older guest is necessary to distinguish cross-architecture
   failures from changes in later VMApple generations.

Each hypothesis remains provisional until an experiment supplies evidence.

## Host and accelerator model

Cross-architecture execution uses TCG. Host virtualization facilities cannot
execute arm64 guest instructions on an x86-64 processor. Consequently, the
first goal is correctness and observability; performance work begins only
after a repeatable boot path exists.

## Source strategy

Development should preserve QEMU's upstream history and keep the change set
reviewable as ordinary commits. The preferred layout is a QEMU fork with:

- a documented upstream revision;
- a development branch for VMApple-on-TCG changes;
- small commits divided by discovered contract or subsystem;
- experiment records outside generated build directories.

The current repository should be attached to upstream QEMU history rather
than embedding an independently cloned source tree or copying QEMU sources
into an unrelated history.

## Evidence and artifact policy

Static inspection may be used to infer an interface when its contract is
unclear. Repository content may contain original analysis, abstract layouts,
field meanings, state transitions, and reproduction procedures.

The repository must not contain third-party binary inputs, extracted bytes,
disassembly listings, generated disk state, or persistent references that
identify local binary inputs. Experiment records should refer to inputs by an
opaque local identifier chosen by the operator.
