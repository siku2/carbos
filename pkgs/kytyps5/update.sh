# shellcheck shell=bash

file=$1
api=https://api.github.com/repos/KytyPS5/KytyPS5
block='/owner = "KytyPS5"/,/hash = /'

read -r rev date < <(curl -fsSL "$api/commits/main" | jq -r '"\(.sha) \(.commit.committer.date[:10])"')
current=$(sed -n "$block"'s/^ *rev = "\(.*\)";$/\1/p' "$file")

if [ "$rev" = "$current" ]; then
  exit 0
fi

base=$(
  curl -fsSL "https://raw.githubusercontent.com/KytyPS5/KytyPS5/$rev/CMakeLists.txt" |
    sed -n 's/^project(.* VERSION \([0-9.]*\))$/\1/p'
)
version="$base-unstable-$date"
hash=$(nix-prefetch-github KytyPS5 KytyPS5 --rev "$rev" --fetch-submodules | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "$block"'s|^\( *rev = \)".*";|\1"'"$rev"'";|' \
  -e "$block"'s|^\( *hash = \)".*";|\1"'"$hash"'";|' \
  "$file"

echo "kytyps5: $current -> $rev ($version)"
