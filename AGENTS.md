# AGENTS.md

## Checkpoint commits

Commit the repository at every logical checkpoint. A checkpoint is a coherent,
reviewable unit of completed work that has been verified in proportion to its
risk—for example, documentation scaffolding, a reproducible baseline, one
isolated compatibility fix, or a passing experiment.

- Keep each checkpoint commit focused on one purpose.
- Run the relevant checks before committing.
- Do not combine unrelated user changes with project work.
- Do not commit secrets, local inputs, generated artifacts, or third-party
  binary material.
- If a checkpoint cannot be committed safely, report why instead of silently
  leaving completed work uncommitted.

## Configure and build output

Keep verbose configure and Ninja output out of the conversation context.

- Redirect full configure and Ninja output to ignored log files.
- While a command is running, report only a short live tail when useful.
- On completion, report the exit status and only the diagnostic tail needed to
  explain a failure or confirm success.
- Do not paste complete configure or Ninja transcripts into tool output.

## Static reverse engineering

Static reverse engineering is a legitimate way to determine an unclear API
contract. Local headers, symbols, disassembly, string tables, and structure
layouts may be inspected to infer expected shapes, opcodes, field offsets, and
calling conventions.

Local third-party binaries and material derived from their bytes must remain
local:

- Never commit binaries, copied excerpts, disassembly listings, extracted
  shaders or firmware, or other material derived from third-party bytes.
- Never identify those binaries in persistent repository content, including
  code comments, commit messages, documentation, tests, and logs.
- Record conclusions as API contracts—for example, describe a field as a
  page-shift without recording where that conclusion was learned.
- Original analysis, metadata, hashes, and reproduction procedures may be
  recorded when they do not include third-party bytes or identify local binary
  inputs.
