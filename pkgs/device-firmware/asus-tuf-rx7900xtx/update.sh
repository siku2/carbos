# shellcheck shell=bash

file=$1

# The tool has no version, but the description lists its SHA256.
read -r sha256 url < <(
  curl -fsSL 'https://www.asus.com/support/api/product.asmx/GetPDBIOS?website=global&model=TUF-RX7900XTX-O24G-GAMING' |
    jq -r '[.Result.Obj[] | select(.Name == "BIOS") | .Files[] | select(.IsRelease == "1")][0] | "\(.Description | capture("SHA256: (?<h>[0-9A-Fa-f]{64})").h) \(.DownloadUrl.Global | sub("\\?.*"; "") | gsub(" "; "%20"))"'
)
hash=$(nix hash convert --hash-algo sha256 --to sri "$sha256")
current=$(sed -n 's/^ *hash = "\(.*\)";$/\1/p' "$file")

if [ "$hash" = "$current" ]; then
  exit 0
fi

zip=$(nix store prefetch-file --json --expected-hash "$hash" "$url" | jq -r .storePath)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -qq "$zip" -d "$tmp"
unrar e -inul "$tmp"/*.exe '*P.rom' "$tmp"/
export FWUPD_LOCALSTATEDIR=$tmp/var CACHE_DIRECTORY=$tmp/cache
version=$(fwupdtool firmware-parse "$tmp"/*P.rom amd-gpu-psp | sed -n 's|^ *<version>\(.*\)</version>$|\1|p' | head -1)
old=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *url = \)\".*\";|\1\"$url\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.asus-tuf-rx7900xtx: $old -> $version"
