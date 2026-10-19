# shellcheck shell=bash

dir=$(dirname "$1")

latest() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name
}

current() {
  sed -n 's/^ *version = "\(.*\)";$/\1/p' "$1"
}

prefetch() {
  nix store prefetch-file --json "$@" | jq -r .hash
}

file=$dir/server.nix
tag=$(latest RLBot/core)
version=${tag#v}
old=$(current "$file")
if [ "$version" != "$old" ]; then
  hash=$(prefetch --executable "https://github.com/RLBot/core/releases/download/$tag/RLBotServer")
  sed -i \
    -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
    -e "s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
    "$file"
  echo "rlbot-server: $old -> $version"
fi

file=$dir/gui.nix
version=$(latest RLBot/gui)
old=$(current "$file")
if [ "$version" != "$old" ]; then
  hash=$(prefetch --executable "https://github.com/RLBot/gui/releases/download/$version/rlbotgui")
  icon=$(prefetch "https://raw.githubusercontent.com/RLBot/gui/$version/build/appicon.png")
  sed -i \
    -e "s|^\( *version = \)\".*\";|\1\"$version\";|" \
    -e "/src = fetchurl/,/};/s|^\( *hash = \)\".*\";|\1\"$hash\";|" \
    -e "/icon = fetchurl/,/};/s|^\( *hash = \)\".*\";|\1\"$icon\";|" \
    "$file"
  echo "rlbot-gui: $old -> $version"
fi
