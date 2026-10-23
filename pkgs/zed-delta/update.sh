# shellcheck shell=bash

file=$1

read -r version url < <(
  curl -fsSL 'https://delta.dev/api/releases/stable/latest/asset?asset=delta&os=macos&arch=aarch64' |
    jq -r '"\(.version) \(.url)"'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "zed-delta: $current -> $version"
