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

Unless the repository uses a specific convention already, adhere to the following:
- Use conventional commit messages. Avoid introducing new "scopes". Only use
  scopes if there's a precedent or if the repository documents (or even
  validates) which scope exist.
- Stick to subject-only commits. It's only appropriate to include a body in
  HIGHLY specific cases. Don't include a body by default and if you think one
  is needed ask the user.
