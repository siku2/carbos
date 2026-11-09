# shellcheck shell=bash

file=$1

# Razer's support page links the current updater through this short link.
url=$(curl -fsSI 'https://rzr.to/axKmO' | sed -n 's/^location: *\([^\r]*\)\r*$/\1/Ip')
version=$(sed -n 's/.*_FirmwareUpdater_v\([0-9.]*\)_r[0-9]*\.exe$/\1/p' <<<"$url")
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")
current_url=$(sed -n 's/^ *url = "\(.*\)";$/\1/p' "$file")

if [ -z "$version" ]; then
  echo "device-firmware.razer-blackwidow-chroma-v2: no updater behind $url" >&2
  exit 1
fi
# A new revision of the same version has a new URL too.
if [ "$url" = "$current_url" ]; then
  exit 0
fi

hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *url = \)\".*\";|\1\"$url\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.razer-blackwidow-chroma-v2: $current -> $version"
