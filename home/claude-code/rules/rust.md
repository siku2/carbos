---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
---

# Rust conventions

R1: Use `#[expect]` instead of `#[allow]` when possible.
R2: Always run `cargo fmt --all` and `cargo clippy --all-targets --all-features`
    to ensure code quality.
R3: Avoid absolute paths to items. Either `use` the item itself or its module.
R4: Enable clippy::arbitrary_source_item_ordering with
    `source-item-ordering = ["module"]` in clippy.toml, and follow its default
    grouping: `mod` declarations first, then imports, then statics and
    consts, then types and impls, then functions. Declaring a module above
    the `use self::` that imports from it is the point. Use a prefix like
    `self::` or `crate::` when importing from locally declared modules.

    Do not enable the lint's alphabetical half (leave `enum`, `struct`,
    `trait` and `impl` out of `source-item-ordering`). Alphabetising a
    protocol enum destroys the spec order that makes it reviewable, an impl
    stops mirroring its trait, and variant order is the derived `Ord` of a
    data-carrying enum, so a cosmetic lint could change behaviour.
R5: Move items into dedicated files in case a file is getting too big.
R6: Use `cargo nextest` for running tests.
R7: When using `tracing`, make sure to preserve errors by passing them as
    `&dyn Error`. Don't use Display (%) formatting! `anyhow::Error` can be done
    using `&*err`. The benefit of doing it this way is that the visitor can
    access all the error details. Also consistently use "error" as the key.

## Module layout convention

Use `foo.rs` + `foo/bar.rs`, not `foo/mod.rs`.
