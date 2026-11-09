# shellcheck shell=bash

sources="$(dirname "$1")/sources.json"

# The stable channel that 1Password for Mac checks itself.
darwin=$(
  curl -fsSL https://app-updates.agilebits.com/check/2/99/aarch64/OPM8/en/0/A1/N |
    jq -r 'select(.available == "1") | .version'
)
# The APT repository only lists amd64, both architectures release together.
linux=$(
  curl -fsSL https://downloads.1password.com/linux/debian/amd64/dists/stable/main/binary-amd64/Packages |
    awk '/^Package: 1password$/ { found = 1 } /^Version/ && found { print $2; exit }'
)

url() {
  case $1/$2 in
  darwin/*) echo "https://downloads.1password.com/mac/1Password-$3-$2.zip" ;;
  linux/x86_64) echo "https://downloads.1password.com/linux/tar/stable/x86_64/1password-$3.x64.tar.gz" ;;
  linux/aarch64) echo "https://downloads.1password.com/linux/tar/stable/aarch64/1password-$3.arm64.tar.gz" ;;
  esac
}

update() {
  local os=$1 version=$2 current arch hash
  current=$(jq -r --arg os "$os" '.[$os].version' "$sources")

  if [ -z "$version" ] || [ "$version" = "$current" ]; then
    return
  fi

  for arch in $(jq -r --arg os "$os" '.[$os].hashes | keys[]' "$sources"); do
    hash=$(nix store prefetch-file --json "$(url "$os" "$arch" "$version")" | jq -r .hash)
    jq --arg os "$os" --arg arch "$arch" --arg hash "$hash" \
      '.[$os].hashes[$arch] = $hash' "$sources" >"$sources.tmp"
    mv "$sources.tmp" "$sources"
  done

  jq --arg os "$os" --arg version "$version" '.[$os].version = $version' "$sources" >"$sources.tmp"
  mv "$sources.tmp" "$sources"

  echo "1password-gui ($os): $current -> $version"
}

update darwin "$darwin"
update linux "$linux"
