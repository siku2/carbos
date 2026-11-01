# shellcheck shell=bash

file=$1

url=$(
  curl -fsSL 'https://support.solidstatelogic.com/api/v2/help_center/en-gb/articles/9645515893533.json' |
    jq -r .article.body |
    grep -o 'https://[^"]*/SSLAudioFirmwareUpdater_V[0-9-]*\.zip' |
    sort -V -t V -k 2 |
    tail -1
)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")
current_url=$(sed -n 's/^ *url = "\(.*\)";$/\1/p' "$file")

if [ "$url" = "$current_url" ]; then
  exit 0
fi

read -r hash path < <(nix store prefetch-file --json "$url" | jq -r '"\(.hash) \(.storePath)"')
entry='//Device[@VID="0x31E9" and @PID="0x0008"]/Firmware'
xml=$(unzip -p "$path" '*/Windows/x64/SslUsbAudioDfu.xml')
version=$(xmllint --xpath "concat(string($entry/@MajorVersion), '.', string($entry/@MinorVersion))" - <<<"$xml")

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *url = \)\".*\";|\1\"$url\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "device-firmware.ssl-2-mk2: $current -> $version"
