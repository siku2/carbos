# shellcheck shell=bash

# The server only looks for Proton in <root>/steamapps/common/Proton* and
# takes a steam file in PATH as a last resort root. Put Steam's extra compat
# tools into such a root so the Proton picked for Rocket League is found.
root=${XDG_RUNTIME_DIR:-/tmp}/rlbot/steam
rm -rf "$root"
mkdir -p "$root/bin" "$root/steamapps/common"
touch "$root/bin/steam"

steamapps=${XDG_DATA_HOME:-$HOME/.local/share}/Steam/steamapps

# The Steam runtime a compat tool asks for, if it is installed.
runtime_for() {
  local appid manifest
  appid=$(awk -F'"' '$2 == "require_tool_appid" { print $4 }' "$1/toolmanifest.vdf")
  manifest=$steamapps/appmanifest_$appid.acf
  [[ -n $appid && -f $manifest ]] || return 0
  echo "$steamapps/common/$(awk -F'"' '$2 == "installdir" { print $4 }' "$manifest")"
}

IFS=: read -ra tools <<<"${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}"
for tool in "${tools[@]}"; do
  vdf=$tool/compatibilitytool.vdf
  [[ -f $vdf ]] || continue
  name=$(awk -F'"' '/"compat_tools"/ { found = 1; next } found && NF > 2 { print $2; exit }' "$vdf")
  [[ -n $name ]] || continue

  runtime=$(runtime_for "$tool")
  if [[ ! -x $runtime/_v2-entry-point ]]; then
    ln -s "$tool" "$root/steamapps/common/$name"
    continue
  fi

  # The server runs proton directly. Wrap it in the runtime like Steam does,
  # since Wine only finds controllers through the runtime's SDL. The runtime
  # only sees the library if it is mounted explicitly.
  mkdir "$root/steamapps/common/$name"
  cat >"$root/steamapps/common/$name/proton" <<EOF
#!/bin/sh
export STEAM_COMPAT_TOOL_PATHS="$tool:$runtime"
export STEAM_COMPAT_MOUNTS="$(realpath "$steamapps")\${STEAM_COMPAT_MOUNTS:+:\$STEAM_COMPAT_MOUNTS}"
exec "$runtime/_v2-entry-point" --verb="\$1" -- "$tool/proton" "\$@"
EOF
  chmod +x "$root/steamapps/common/$name/proton"
done

rlbotgui "$@" &
gui=$!
server=
trap 'kill "$gui" ${server:+"$server"} 2>/dev/null || true' EXIT

# The server exits with the game, so keep one around while the GUI is open.
# Quick exits in a row mean it cannot start at all.
failures=0
while kill -0 "$gui" 2>/dev/null; do
  started=$SECONDS
  PATH=$PATH:$root/bin RLBotServer ${RLBOT_SERVER_PORT:+"$RLBOT_SERVER_PORT"} &
  server=$!
  wait -n "$gui" "$server" || true
  kill -0 "$gui" 2>/dev/null || break

  if ((SECONDS - started < 5)); then
    failures=$((failures + 1))
  else
    failures=0
  fi
  if ((failures >= 3)); then
    echo "RLBotServer keeps exiting right away, not restarting it" >&2
    server=
    wait "$gui" || true
    break
  fi
  sleep 1
done
