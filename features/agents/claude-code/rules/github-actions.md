---
paths:
  - "**/.github/**"
---

# GitHub Actions conventions

## A1: workflow-permissions

Set minimal `permissions` at the workflow level, usually `contents: read`.
Grant higher permissions only on the jobs that need them.

## A2: pinned-actions

Use the latest release of each action. Pin it to the full commit SHA and add
the exact version as a comment: `uses: actions/checkout@<sha> # v5.0.1`.
Look up the version and SHA with `gh`, never from memory. Use the commit SHA,
not the SHA of an annotated tag object.

## A3: step-names

Give every step a `name` that says what it does.

## A4: pinned-runners

Use versioned runner labels like `ubuntu-26.04`, never `*-latest`. Pick the
newest generally available version.

## A5: no-inline-scripts

Keep `run:` blocks to a few lines. Put longer logic in a script next to the
workflow so it can be linted and formatted. Pass values to scripts through
`env:` instead of `${{ }}` expressions in the script body.

## A6: yaml-extension

Use `.yaml`, not `.yml`, unless a tool requires `.yml`.
