---
name: create-pr
description: Use when asked to create a PR.
---

# Create a PR

## Title

PRs are often squash-merged, so the title becomes the commit subject. Write
it as one, following the repository's commit convention.

## Description

Write a short note, not a summary of the diff. One or two sentences is often
enough. If the change explains itself, leave the body empty.

- No preamble like "This PR...".
- No file-by-file walkthrough.
- No emoji or headings. Use lists only when they help.
- Explain why only when the change doesn't make it obvious.

Pass the body through a heredoc so it stays exactly as written:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<description>
EOF
)"
```
