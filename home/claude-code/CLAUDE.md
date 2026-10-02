# CLAUDE.md

## General conventions

Only use ASCII characters in the code unless it actually makes sense for
clarity. Em-dashes or other special punctuation characters should be avoided.
Don't approximate the em dash with -- either, just avoid them in general.
One example of where it makes sense is when writing units like cubic meters
where the 3 superscript makes a difference in readability.

Write documentation in clear, simple, technical English. Don't add unnecessary
flourishes. The goal is to be easily understandable for an international
audience. Prefer basic easy to read sentences. We're not writing a novel here,
we're writing for a technical audience! Respect the reader's time and
intelligence and keep the length to an absolute minimum.

Strongly avoid adding any sort of "comment header" to the code if the code
can instead be split across multiple files.

## Commit style

There are two commit conventions. Pick the one that fits the repository:
- Conventional Commits (https://www.conventionalcommits.org/) for
  repositories that produce releases, such as libraries and binaries.
- Scoped Commits (https://scopedcommits.com/) for repositories where HEAD
  itself is the state, such as system configuration or deployments.

The repository defines which convention and which scopes apply. Follow the
existing history or documentation and don't introduce new scopes without
precedent. If neither gives a clear answer, ask the user.

Stick to subject-only commits. It's only appropriate to include a body in
HIGHLY specific cases. Don't include a body by default and if you think one
is needed ask the user.
