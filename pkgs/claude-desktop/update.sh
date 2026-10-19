# shellcheck shell=bash

file=$1

read -r version url < <(
  curl -fsSL https://downloads.claude.ai/releases/darwin/universal/RELEASES.json |
    jq -r '.currentRelease as $v | .releases[] | select(.version == $v) | "\(.version) \(.updateTo.url)"'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

commit=${url##*/Claude-}
commit=${commit%.zip}
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *commit = \)\".*\";|\1\"$commit\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "claude-desktop: $current -> $version"
