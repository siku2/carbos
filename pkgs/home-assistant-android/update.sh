# shellcheck shell=bash

file=$1
name=$(sed -n 's/^ *packageName = "\(.*\)";$/\1/p' "$file")
current=$(sed -n 's/^ *versionCode = \([0-9]*\);$/\1/p' "$file")

read -r code version < <(
  curl -fsSL "https://f-droid.org/api/v1/packages/$name" |
    jq -r '.suggestedVersionCode as $c | .packages[] | select(.versionCode == $c) | "\(.versionCode) \(.versionName)"'
)

if [ "$code" = "$current" ]; then
  exit 0
fi

hash=$(nix store prefetch-file --json "https://f-droid.org/repo/${name}_$code.apk" | jq -r .hash)
version=${version%-minimal}

sed -i \
  -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
  -e "s|^\( *versionCode = \)[0-9]*;|\1$code;|" \
  -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
  "$file"

echo "home-assistant-android: $current -> $code ($version)"
