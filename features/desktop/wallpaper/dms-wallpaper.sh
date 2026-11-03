# shellcheck shell=bash

# DMS owns session.json and watches it, so merging in place is enough.
mkdir -p "$(dirname "$SESSION_FILE")"
[ -f "$SESSION_FILE" ] || echo '{}' >"$SESSION_FILE"

tmp=$(mktemp "$SESSION_FILE.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --argjson managed "$MANAGED" '. * $managed' "$SESSION_FILE" >"$tmp"
mv "$tmp" "$SESSION_FILE"
trap - EXIT
