# shellcheck shell=bash

file=$1

for channel in system/lineage/waydroid_x86_64/VANILLA vendor/waydroid_x86_64/MAINLINE; do
  kind=${channel%%/*}
  block="/kind = \"$kind\"/,/hash = /"
  current=$(sed -n "$block"'s/^ *file = "\(.*\)";$/\1/p' "$file")
  read -r latest id < <(curl -fsSL "https://ota.waydro.id/$channel.json" | jq -r '.response[0] | "\(.filename) \(.id)"')

  if [ "$latest" = "$current" ]; then
    continue
  fi

  hash=$(nix hash convert --hash-algo sha256 --to sri "$id")
  sed -i \
    -e "$block"'s|^\( *file = \)".*";|\1"'"$latest"'";|' \
    -e "$block"'s|^\( *hash = \)".*";|\1"'"$hash"'";|' \
    "$file"

  echo "waydroid-images: $current -> $latest"
done
