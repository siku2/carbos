# shellcheck shell=bash

# DMS rewrites these fragments at runtime, so they are seeded once and then
# left alone.
dms_dir="$HOME/.config/niri/dms"
mkdir -p "$dms_dir"

for f in "$FRAGMENT_DIR"/*.kdl; do
  name=$(basename "$f")
  [ -e "$dms_dir/$name" ] || install -m 644 "$f" "$dms_dir/$name"
done
