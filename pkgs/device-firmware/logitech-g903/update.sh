# shellcheck shell=bash

file=$1

url=https://updates.ghub.logitechg.com$(
  curl -fsSL 'https://updates.ghub.logitechg.com/pipeline/v2/update/ghub13/win/public/details.json' |
    jq -r '.depots[] | select(.name == "g903_dfu") | .url'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")
current_url=$(sed -n 's/^ *url = "\(.*\)";$/\1/p' "$file")

if [ "$url" = "$current_url" ]; then
  exit 0
fi

read -r hash path < <(nix store prefetch-file --json "$url" | jq -r '"\(.hash) \(.storePath)"')
depot=$(mktemp -d)
trap 'rm -rf "$depot"' EXIT
node "$(dirname "$file")/depot.ts" "$path" "$depot"
version=$(jq -r '.contents[0].version' "$depot/dfu.json")

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *url = \)\".*\";|\1\"$url\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.logitech-g903: $current -> $version"
