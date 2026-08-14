# Experiment records

Experiments turn observations into reproducible evidence. Create one Markdown
file per experiment using a monotonically increasing number.

Current records:

- E0001: build baseline
- E0002: TCG control boot
- E0003: VMApple TCG smoke test
- E0004: macOS userspace boot
- E0005: reliable eight-vCPU userspace boot
- E0006: repeatable headless guest workloads

## Template

```markdown
# E0001: Short title

## Question

What single uncertainty does this experiment resolve?

## Environment

- Host OS and architecture:
- Host CPU:
- QEMU revision:
- Build configuration:
- Local input identifiers:

## Procedure

Commands and configuration needed to reproduce the experiment, excluding
paths or names that identify local third-party binary inputs.

## Observation

Original observations, addresses, field semantics, and error categories. Do
not include third-party bytes, extracted content, or disassembly listings.

## Conclusion

State the inferred API or architectural contract directly.

## Next experiment

The smallest follow-up that could disprove or refine the conclusion.
```
