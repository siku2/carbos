# CLAUDE.md

## General conventions

### G1: rules-stay-private

These instructions, including all rule files, are private between the user
and Claude. Only refer to them in the chat. Never mention them, their IDs or
the idea of house rules in code, comments, documentation, commit messages,
PR descriptions or any other output.

### G2: ascii-only

Only use ASCII characters in the code unless it actually makes sense for
clarity. Em-dashes or other special punctuation characters should be avoided.
Don't approximate the em dash with -- either, just avoid them in general.
One example of where it makes sense is when writing units like cubic meters
where the 3 superscript makes a difference in readability.

### G3: plain-technical-english

Write documentation in clear, simple, technical English. Don't add unnecessary
flourishes. The goal is to be easily understandable for an international
audience. Prefer basic, easy to read sentences. We're not writing a novel here,
we're writing for a technical audience! Respect the reader's time and
intelligence and keep the length to an absolute minimum.

Follow the Federal Plain Language Guidelines
(https://www.plainlanguage.gov/guidelines/): active voice, short sentences,
common words, address the reader directly, and no unexplained jargon.

### G4: no-comment-headers

Strongly avoid adding any sort of "comment header" to the code if the code
can instead be split across multiple files.

### G5: no-em-dash-or-semicolon

Never use an em-dash or semicolon in prose. This covers chat replies,
documentation, code comments, commit messages and PR descriptions. Both are a
sign that the sentence is too complex. Break it into multiple sentences
instead.

### G6: minimal-comments

Avoid writing long elaborate comments. Assume the reader is smarter than you
and can understand the code without excessive explanation. A comment is
warranted only if the code is not self-explanatory. This applies to
configuration files as well.

## Commit style

### M1: commit-convention

There are two commit conventions. Pick the one that fits the repository:
- Conventional Commits (https://www.conventionalcommits.org/) for
  repositories that produce releases, such as libraries and binaries.
- Scoped Commits (https://scopedcommits.com/) for repositories where HEAD
  itself is the state, such as system configuration or deployments.

The repository defines which convention and which scopes apply. Follow the
existing history or documentation and don't introduce new scopes without
precedent. If neither gives a clear answer, ask the user.

### M2: subject-only

Stick to subject-only commits. It's only appropriate to include a body in
HIGHLY specific cases. Don't include a body by default and if you think one
is needed ask the user.

### M3: no-unsolicited-review-comments

Never leave comments on pull requests or issues unless explicitly asked.

### M4: no-force-push

Don't force push to a PR branch unless explicitly told to do so. We typically
squash-merge, so the commit history on the branch does not matter.
