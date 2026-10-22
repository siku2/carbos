# shellcheck shell=bash

mkdir -p "$DIR"

for name in $(jq -r 'keys[]' "$SETTINGS"); do
  file="$DIR/$name.json"
  [ -f "$file" ] || echo '{}' >"$file"
  jq --slurpfile settings "$SETTINGS" --arg name "$name" \
    '. * $settings[0][$name]' "$file" >"$file.tmp"
  if cmp -s "$file" "$file.tmp"; then
    rm "$file.tmp"
  else
    mv "$file.tmp" "$file"
  fi
done
