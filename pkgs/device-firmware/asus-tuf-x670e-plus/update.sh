# shellcheck shell=bash

file=$1

# Files are newest first. IsRelease is 0 for betas.
read -r version url < <(
  curl -fsSL 'https://www.asus.com/support/api/product.asmx/GetPDBIOS?website=global&model=TUF%20GAMING%20X670E-PLUS' |
    jq -r '[.Result.Obj[] | select(.Name == "BIOS") | .Files[] | select(.IsRelease == "1")][0] | "\(.Version) \(.DownloadUrl.Global | sub("\\?.*"; ""))"'
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

echo "device-firmware.asus-tuf-x670e-plus: $current -> $version"
