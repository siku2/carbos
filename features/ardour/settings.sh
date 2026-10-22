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

[ -n "${ENGINE:-}" ] || exit 0

file="$DIR/config"
states=/Ardour/Extra/AudioMIDISetup/EngineStates
backend=$(jq -r .backend "$ENGINE")
active="count($states/State[@backend='$backend' and @active='1'])"
[ "$(xmlstarlet sel -t -v "$active" "$file")" = 0 ] || exit 0

xmlstarlet ed -L -d /Ardour/Extra/AudioMIDISetup "$file"
if [ "$(xmlstarlet sel -t -v "count(/Ardour/Extra)" "$file")" = 0 ]; then
  xmlstarlet ed -L -s /Ardour -t elem -n Extra "$file"
fi
xmlstarlet ed -L \
  -s /Ardour/Extra -t elem -n AudioMIDISetup \
  -s /Ardour/Extra/AudioMIDISetup -t elem -n EngineStates \
  -s $states -t elem -n State \
  -s $states/State -t elem -n MIDIDevices "$file"
while IFS=$'\t' read -r name value; do
  xmlstarlet ed -L -i $states/State -t attr -n "$name" -v "$value" "$file"
done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$ENGINE")
