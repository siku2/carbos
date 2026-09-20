# shellcheck shell=bash

# Single line of base64. Must land before any shell starts a session.
install -d -m 700 "$(dirname "$KEY_PATH")"
umask 077
printf '%s\n' "$ATUIN_KEY" >"$KEY_PATH"
