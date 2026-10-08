---
name: create-pr
description: Create a GitHub pull request. Use when asked to create, open, or raise a PR.
---

# Create a PR

Follow these rules when opening a pull request. They exist because the
default PR output almost always needs correcting.

## 1. The description must not read like AI

The description is a short, factual note. Not a summary of the diff.

Rules:

- Keep it terse. Often one or two sentences is enough.
- Write plain English. Simple sentences. No em-dash, no semicolon.
- No preamble like "This PR..." or "This change introduces...".
- No marketing words (comprehensive, robust, seamless, powerful).
- No file-by-file walkthrough. The diff already shows that.
- No emoji, no headings, no bullet lists unless they genuinely help.
- Explain *why* only when it is not obvious from the change itself.

If the change is self-explanatory, a one-line description or even an
empty body is correct. Do not pad it.

Prefer a heredoc so the body stays exactly as written:

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<terse description here>
EOF
)"
```

## 2. The title is a commit subject

PRs are squashed through a merge queue. The PR title becomes the squash
commit subject, so write it like a good commit subject line.

- Usually conventional commits (`feat:`, `fix:`, `chore:`, ...).
- The exact convention varies by project. Check first:

  ```bash
  git log --oneline -20
  ```

  Match the style you see (scope usage, tense, prefixes).
- Imperative mood, lower case after the prefix, no trailing period.

## 3. Never force-push a PR branch

Because merging squashes everything, the branch history does not matter.

- Do not force-push to update a PR.
- To address review, just add normal commits and push.
- Never rebase-and-force to "clean up" the branch. The squash handles it.

## Quick check before you open it

- Title reads like a commit subject and matches the repo's convention.
- Description is terse, plain, and sounds like Simon.
- No AI filler, no diff summary.
- You pushed with a normal push, not `--force`.
