# shellcheck shell=bash

file=$1
dir=$(dirname "$file")

version=$(curl -fsSL https://registry.npmjs.org/@z_ai/mcp-server/latest | jq -r .version)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

url="https://registry.npmjs.org/@z_ai/mcp-server/-/mcp-server-$version.tgz"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL "$url" | tar xz -C "$work"
(cd "$work/package" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund)
cp "$work/package/package-lock.json" "$dir/package-lock.json"
npmDepsHash=$(prefetch-npm-deps "$dir/package-lock.json")

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  -e "s|^\( *npmDepsHash = \)\".*\";|\1\"$npmDepsHash\";|" \
  "$file"

echo "zai-mcp-server: $current -> $version"
