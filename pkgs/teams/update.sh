# shellcheck shell=bash

file=$1

# The production channel of Microsoft AutoUpdate.
feed=https://officecdnmac.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409TEAMS21.xml

version=$(curl -fsSL "$feed" | xmllint --xpath 'string(//key[.="Update Version"]/following-sibling::string[1])' -)
current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")

if [ "$version" = "$current" ]; then
  exit 0
fi

url="https://statics.teams.cdn.office.net/production-osx/$version/MicrosoftTeams.pkg"
hash=$(nix store prefetch-file --json "$url" | jq -r .hash)

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "teams: $current -> $version"
