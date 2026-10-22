# shellcheck shell=bash

# Restarts DMS after a switch that changed its configuration. Plugins keep
# their paths across versions, and every file in the Nix store has the same
# timestamp, so Quickshell would keep running stale compiled QML from its cache.

if [[ "$(cat "$STAMP" 2>/dev/null)" == "$CONFIG" ]]; then
  exit 0
fi

rm -rf "$QML_CACHE"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
  systemctl --user try-restart dms.service
fi

mkdir -p "$(dirname "$STAMP")"
printf '%s\n' "$CONFIG" >"$STAMP"
