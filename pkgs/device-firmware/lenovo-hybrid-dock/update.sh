# shellcheck shell=bash

file=$1

# The support page embeds its download list as JSON.
read -r version url < <(
  curl -fsSL -A 'Mozilla/5.0' 'https://pcsupport.lenovo.com/us/en/downloads/ds504448' |
    grep -o '"Version":"[^"]*","URL":"https://download.lenovo.com/pccbbs/mobiles/fhybd[^"]*\.exe"' |
    head -1 |
    jq -rR '"{\(.)}" | fromjson | "\(.Version) \(.URL)"'
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *url = \)\".*\";|\1\"$url\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.lenovo-hybrid-dock: $current -> $version"
