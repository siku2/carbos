# shellcheck shell=bash

file=$1

# The production channel of Microsoft AutoUpdate.
feed=https://officecdnmac.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409MSRD10.xml

payload=$(curl -fsSL "$feed" | xmllint --xpath 'string((//key[.="Payload"]/following-sibling::string[1][starts-with(., "Windows_App_")])[1])' -)
version=${payload#Windows_App_}
version=${version%_updater.pkg}
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

url="https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Windows_App_${version}_installer.pkg"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "windows-app: $current -> $version"
