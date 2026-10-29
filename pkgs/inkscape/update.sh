# shellcheck shell=bash

file=$1

version=$(
  curl -fsSL 'https://gitlab.com/api/v4/projects/inkscape%2Finkscape/repository/tags?search=%5EINKSCAPE_&per_page=100' |
    jq -r '.[].name' |
    sed -n 's/^INKSCAPE_\([0-9]*_[0-9]*\(_[0-9]*\)\{0,1\}\)$/\1/p' |
    tr _ . |
    sort -V |
    tail -n 1
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

# Tags land before the macOS builds are published.
url="https://media.inkscape.org/dl/resources/file/Inkscape-${version}_arm64.dmg"
if ! curl -fsIL "$url" >/dev/null; then
  echo "inkscape: $version has no arm64 dmg yet"
  exit 0
fi

hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "inkscape: $current -> $version"
