---
paths:
  - "**/*.rs"
---

# Rust conventions

## R1: prefer-expect-over-allow

Use `#[expect]` instead of `#[allow]` when possible.

## R2: run-fmt-and-clippy

Always run `cargo fmt --all` and `cargo clippy --all-targets --all-features`
to ensure code quality.

## R3: split-large-files

Move items into dedicated files in case a file is getting too big.

## R4: use-nextest

Use `cargo nextest` for running tests.

## R5: log-errors-as-dyn-error

When using `tracing`, preserve errors by passing them as `&dyn Error`. Don't
use Display (`%`) formatting! `anyhow::Error` can be done using `&*err`. The
benefit of doing it this way is that the visitor can access all the error
details. Also consistently use `error` as the key.

## R6: behaviour-belongs-to-a-type

Don't write freestanding helper functions when a local type can own the
behaviour. For example, construct error variants through associated functions
on the error type, not through a free `fn`. Prefer a `From` impl where the
conversion is natural. A freestanding function is only acceptable when the
type comes from an external crate.

## R7: newtype-invariants

Encode invariants (ordering, domain validation, ...) with the newtype pattern,
so that holding a value of the type proves the invariant. Functions then take
the newtype and neither trust the caller nor check again.

The field is private, the only way to construct the type is a fallible
constructor (`TryFrom` or `new` returning `Result`), and no API may break the
invariant after construction.

## R8: structured-errors

Never add a `message: String` field (or similar) that holds a prose
description of the failure. Model each failure as its own variant and keep the
underlying error with `#[source]`. Fields that hold data, such as the
offending key or path, are fine. Don't flatten errors into strings with
`.to_string()` or `format!`.
