# shellcheck shell=bash

# Replacing a key orphans every record encrypted with it, so never overwrite.
if [[ -e $KEY_PATH ]]; then
  if [[ $(<"$KEY_PATH") == "$ATUIN_KEY" ]]; then
    exit 0
  fi
  echo "$KEY_PATH does not match ATUIN_KEY, refusing to overwrite it" >&2
  exit 2
fi

# Single line of base64. Must land before any shell starts a session.
install -d -m 700 "$(dirname "$KEY_PATH")"
umask 077
printf '%s\n' "$ATUIN_KEY" >"$KEY_PATH"
