# shellcheck shell=bash

# The server only looks for Proton in <root>/steamapps/common/Proton* and
# takes a steam file in PATH as a last resort root. Link Steam's extra compat
# tools into such a root so the Proton picked for Rocket League is found.
root=${XDG_RUNTIME_DIR:-/tmp}/rlbot/steam
rm -rf "$root"
mkdir -p "$root/bin" "$root/steamapps/common"
touch "$root/bin/steam"

IFS=: read -ra tools <<<"${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}"
for tool in "${tools[@]}"; do
  vdf=$tool/compatibilitytool.vdf
  [[ -f $vdf ]] || continue
  name=$(awk -F'"' '/"compat_tools"/ { found = 1; next } found && NF > 2 { print $2; exit }' "$vdf")
  [[ -n $name ]] && ln -s "$tool" "$root/steamapps/common/$name"
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
