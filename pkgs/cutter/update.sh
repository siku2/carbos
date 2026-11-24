# shellcheck shell=bash

file=$1

version=$(
  curl -fsSL 'https://api.github.com/repos/rizinorg/cutter/releases/latest' |
    jq -r '.tag_name | ltrimstr("v")'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

url="https://github.com/rizinorg/cutter/releases/download/v${version}/Cutter-v${version}-macOS-arm64.dmg"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "cutter: $current -> $version"
