# shellcheck shell=bash

mkdir -p "$DIR"

while IFS=$'\t' read -r name node option value; do
  file="$DIR/$name"
  [ -f "$file" ] || printf '<?xml version="1.0" encoding="UTF-8"?>\n<Ardour/>\n' >"$file"
  cp "$file" "$file.tmp"

  if [ "$(xmlstarlet sel -t -v "count(/Ardour/$node)" "$file.tmp")" = 0 ]; then
    xmlstarlet ed -L -s /Ardour -t elem -n "$node" "$file.tmp"
  fi

  path="/Ardour/$node/Option[@name='$option']"
  if [ "$(xmlstarlet sel -t -v "count($path)" "$file.tmp")" = 0 ]; then
    xmlstarlet ed -L -s "/Ardour/$node" -t elem -n NewOption \
      -i //NewOption -t attr -n name -v "$option" \
      -i //NewOption -t attr -n value -v "$value" \
      -r //NewOption -v Option "$file.tmp"
  else
    xmlstarlet ed -L -u "$path/@value" -v "$value" "$file.tmp"
  fi

  if cmp -s "$file" "$file.tmp"; then
    rm "$file.tmp"
  else
    mv "$file.tmp" "$file"
  fi
done < <(jq -r 'to_entries[] | .key as $file | .value | to_entries[] | .key as $node
  | .value | to_entries[] | [$file, $node, .key, .value] | @tsv' "$SETTINGS")
