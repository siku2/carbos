# shellcheck shell=bash

file=$1

version=$(
  curl -fsSL -A 'Mozilla/5.0' 'https://semiconductor.samsung.com/consumer-storage/support/tools/' |
    grep -o 'Samsung_SSD_990_PRO_[A-Z0-9]*\.iso' |
    head -1 |
    sed 's/^Samsung_SSD_990_PRO_\(.*\)\.iso$/\1/'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ -z "$version" ] || [ "$version" = "$current" ]; then
  exit 0
fi

url="https://download.semiconductor.samsung.com/resources/software-resources/Samsung_SSD_990_PRO_$version.iso"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.samsung-990-pro: $current -> $version"
