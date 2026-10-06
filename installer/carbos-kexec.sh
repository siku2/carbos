#!/bin/sh
# Loads the carbos installer and reboots into it after a clean shutdown.
set -eu

dir=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

"$dir/bin/kexec" --load "$dir/kernel" --initrd="$dir/initrd" \
  --command-line="$(cat "$dir/cmdline")"

printf 'The carbos installer is loaded. Shut down and boot into it now? [y/N] '
read -r answer
case $answer in
y | Y) ;;
*)
  "$dir/bin/kexec" --unload
  echo "Unloaded, nothing changed."
  exit 1
  ;;
esac

if command -v systemctl >/dev/null; then
  systemctl kexec
else
  sync
  "$dir/bin/kexec" --exec
fi
