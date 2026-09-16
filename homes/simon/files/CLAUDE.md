## General conventions

These rules apply to prose: chat replies, documentation, code comments,
commit messages, and PR descriptions.

### G1

Your target audience is highly educated and intelligent, but they may not be
native English speakers. Keep vocabulary and syntax simple without simplifying
the substance.

Follow the Federal Plain Language Guidelines
(https://www.plainlanguage.gov/guidelines/): active voice, short sentences,
common words, address the reader directly, and no unexplained jargon.

### G2

NEVER use an em-dash or semicolon. Both are a sign that the sentence is too
complex. Break it into multiple sentences instead.

## Coding conventions

### C1

Avoid writing long elaborate comments. Assume the reader is smarter than you
and can understand the code without excessive explanation. A comment is
warranted only if the code is not self-explanatory.

### C2

Stick to ASCII characters in the code. Avoid using any non-ASCII characters
unless it explicitly improves understandability (e.g. using it for SI units).

## Version control conventions

### VC1

Don't write extended commit messages unless absolutely necessary. If necessary,
keep them short and technical. Absolutely no fluff.

### VC2

Only write a PR description if it is not immediately clear what is going on.
Even then, keep it as short as possible.

### VC3

Use conventional commits. Avoid adding a scope unless the project clearly
defines allowed values. Otherwise reuse existing scopes from the git history.

### VC4

Never leave comments on pull requests or issues unless explicitly asked.

### VC5

Don't force push to a PR branch unless explicitly told to do so. We typically
squash-merge, so the commit history on the branch does not matter.

## Rust conventions

### R1

`use` declarations always come before `mod` declarations. This holds even when
importing from a local module. When referring to a local module, use the
explicit `self::` prefix (e.g. `self::board::Foo`).

### R2

Do not define default features for a crate in `Cargo.toml`. Make every feature
opt-in.

### R3

Only use additive features in `Cargo.toml` and document them in the crate-level
documentation.

### R4

Never format errors with `Display` (`%err`) or `Debug` (`?err`) in `tracing`
events. Use tracing's native error support so the full source chain is captured.
For a regular error use `error = &err as &dyn Error`. For an `anyhow::Error` use
`error = &*err`. Name the variable `err` and name the tracing field `error`.

### R5

Every public crate member must have exactly one path. Either keep the submodule
private and re-export the item (`mod foo; pub use self::foo::Bar;`) or make the
submodule public (`pub mod foo;`) and reach it as `crate::foo::Bar`. Never both.

### R6

Follow the [How to write documentation](https://doc.rust-lang.org/rustdoc/how-to-write-documentation.html)
guide when writing documentation.
Particularly important is the structure:

```
[short sentence explaining what it is]

[more detailed explanation]

[at least one code example that users can copy/paste to try it]

[even more advanced explanations if necessary]
```

