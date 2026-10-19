# shellcheck shell=bash

file=$1

# The tag feed is full of dev builds, so ask for the latest release instead.
tag=$(curl -fsSL https://api.github.com/repos/Vector35/binaryninja-api/releases/latest | jq -r .tag_name)
version=${tag#stable/}
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

url="https://github.com/Vector35/binaryninja-api/releases/download/stable/$version/binaryninja_free_macosx.dmg"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "binaryninja-free: $current -> $version"
