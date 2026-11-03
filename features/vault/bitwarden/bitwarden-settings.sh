# shellcheck shell=bash

# The app is named "electron", so match on the bundle path instead.
if pgrep -f "/opt/Bitwarden/resources/app.asar" >/dev/null; then
  echo "bitwarden is running, leaving its settings alone" >&2
  exit 0
fi

mkdir -p "$(dirname "$DATA_FILE")"
[ -f "$DATA_FILE" ] || echo '{}' >"$DATA_FILE"

tmp=$(mktemp "$DATA_FILE.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq --argjson managed "$MANAGED" '. * $managed' "$DATA_FILE" >"$tmp"
mv "$tmp" "$DATA_FILE"
trap - EXIT
