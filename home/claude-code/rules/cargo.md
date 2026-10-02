---
paths:
  - "**/Cargo.toml"
---

# Cargo workspace conventions

## C1: workspace-declares-all

Declare ALL dependencies (normal, dev, build and target-specific) in
`[workspace.dependencies]` with a version. External dependencies also set
`default-features = false`.

## C2: members-only-inherit

Members only inherit dependencies with `workspace = true`. They never set
their own version or path. This includes workspace-local packages.

## C3: look-up-latest-version

When adding a dependency, look up its latest version first (for example with
`cargo info <name>`). Don't go off memory.

## C4: workspace-enables-no-features

The workspace level NEVER enables features. Members enable the features they
need, including ones that would otherwise be defaults.

## C5: no-default-features

Don't define default features for our own packages.

## C6: opt-in-runtime-behaviour

Never use features for configuration or implicit runtime changes. A feature
only makes functionality available. The binary must still opt in to it
explicitly at runtime.

For example, a `stdout` feature of a logging library gates an
`enable_stdout()` method instead of turning on stdout logging by itself. The
runtime behaviour stays explicit, and the compiler guarantees that the feature
is enabled.

## C7: inline-workspace-tables

Write `x = { workspace = true }`, not `x.workspace = true`.

## C8: sorted-member-dependencies

A member's dependency table is a single list sorted alphabetically. It only
contains single-line entries. An entry that doesn't fit within 80 columns gets
its own subtable (`[dependencies.x]`) after the list.

## C9: sorted-features

Feature lists are sorted alphabetically. A list that doesn't fit within 80
columns has one feature per line.

## C10: local-dependencies-first

`[workspace.dependencies]` has two lists separated by an empty line: local
(path) dependencies first, then external dependencies sorted alphabetically.

## C11: packages-not-crates

Cargo defines packages. Crates are the compilation units within a package.
Use the term "package" for workspace members and put them in `packages/`, not
`crates/`.
