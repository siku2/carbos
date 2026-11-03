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
use Display (`%`) or Debug (`?`) formatting! For a regular error use
`error = &err as &dyn Error`. For an `anyhow::Error` use `error = &*err`. The
benefit of doing it this way is that the visitor can access all the error
details. Name the variable `err` and consistently use `error` as the key.

## R6: behaviour-belongs-to-a-type

A function that works on a type's data, or produces a value of that type,
belongs to that type: a method, an associated function, or a trait impl
(`From`, `TryFrom`, `FromStr`, ...). For example, construct error variants
through associated functions on the error type, not through a free `fn`.

A function with no owning type, such as a stateless decoder or a group of
test helpers, belongs in a module.

A unit struct is only justified when it implements a trait, is used as a
type parameter or marker, or is a meaningful value in its own right.

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

## R9: code-structure

- A module with submodules lives in `foo.rs` next to a `foo/` directory, never
  in `foo/mod.rs`.
- Items in modules and traits follow a fixed order: 1. modules 2. "use" 3. everything else
- The visibility on a definition is its real visibility. An item that isn't
  reachable from outside the crate is `pub(crate)`, not `pub`.

Enforce this with lints in `Cargo.toml`. The full set varies per project, but
these usually belong in it:

```toml
[workspace.lints.rust]
unreachable_pub = "warn"

[workspace.lints.clippy]
arbitrary_source_item_ordering = "warn"
mod_module_files = "warn"
```

Limit the item ordering to modules and traits in `clippy.toml`:

```toml
source-item-ordering = ["module", "trait"]
```

## R10: one-public-path

Every public crate member must have exactly one path. Either keep the submodule
private and re-export the item (`mod foo; pub use self::foo::Bar;`) or make the
submodule public (`pub mod foo;`) and reach it as `crate::foo::Bar`. Never both.

## R11: rustdoc-structure

Follow the [How to write documentation](https://doc.rust-lang.org/rustdoc/how-to-write-documentation.html)
guide when writing documentation.
Particularly important is the structure:

```
[short sentence explaining what it is]

[more detailed explanation]

[at least one code example that users can copy/paste to try it]

[even more advanced explanations if necessary]
```

## R12: no-async-trait

Never use the `async_trait` crate. Use native async fn in traits. When dyn
dispatch is required, define a second "boxed" trait whose methods return
`Box::pin`'d futures and give it a blanket impl for all implementors of the
base trait. Only the boxed trait is used as a trait object.

## R13: pinned-toolchain

Pin the toolchain with a committed `rust-toolchain.toml`. Use the
[cellguard rustfmt.toml](https://github.com/stargrid-systems/cellguard/blob/main/rustfmt.toml)
as the formatting style. It needs nightly rustfmt. Compilation stays on the
pinned stable toolchain.

## R14: data-shape

Store data in the shape its consumers need: ordered, unique or keyed. A
`collect()`, `sort` or `dedup` at the place of use means the producer has the
wrong shape. Fix the producer instead. Sort only at an output boundary whose
format dictates the order.

## R15: lazy-flow

Data that only passes through stays lazy. Take `impl IntoIterator`, return
`impl Iterator`, and borrow inputs that are only read. Don't `collect()` to
iterate again, count or pass the result on. A function that returns
`impl Iterator` is lazy in its body too. Output that must be materialized
goes into a buffer or writer owned by whoever can reuse it. Judge by what
allocates and copies, not by the signature.

## R16: no-stack-buffers

Don't replace a heap allocation with a fixed-size stack buffer. A stack array
is fine only when a hard bound sets its size, never a guess.

## R17: single-owner

Every value has one owner. Others borrow it or hold a typed id. Don't key a
map with a clone of the stored value, and don't build derived data before
someone asks for it. Names of entities, such as nets or pins, live in the
table of their owner and are referred to by id. Messages and reports are
structured data that is rendered to text at the output boundary.

## R18: fallible-sequences

Use `Item = Result` when items fail independently or when the first error
ends the sequence. When the result is all or nothing, check first and then
iterate plain values.
