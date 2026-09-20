# shellcheck shell=bash

# A single line of base64. atuin writes a fresh key whenever the file is
# missing, so this has to land before any shell starts a session.
install -d -m 700 "$(dirname "$KEY_PATH")"
umask 077
printf '%s\n' "$ATUIN_KEY" >"$KEY_PATH"
