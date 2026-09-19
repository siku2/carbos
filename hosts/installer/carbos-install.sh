# shellcheck shell=bash
if [ "$(id -u)" -ne 0 ]; then
  exec sudo carbos-install "$@"
fi

say() { printf "\n==> %s\n" "$1"; }
die() {
  printf "ERROR: %s\n" "$1" >&2
  exit 1
}
online() { curl -fsS --max-time 5 -o /dev/null https://github.com; }

say "carbos installer for carbon-x1"
echo "This will wipe the internal NVMe and install NixOS."

say "bringing up network"
modprobe iwlwifi 2>/dev/null || true
rfkill unblock all 2>/dev/null || true

if ! online; then
  if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
    echo "wifi device present but offline"
    read -rp "Open nmtui to configure wifi? [Yn] " answer
    if [ -z "$answer" ] || [ "$answer" = y ] || [ "$answer" = Y ]; then
      nmtui
    fi
  else
    echo "no wifi device, likely the CNVi quirk after kexec"
    read -rp "Connect USB tethering, then press Enter..." _
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    online && break
    sleep 3
  done
  online || die "no network, fix it and run carbos-install again"
fi
say "network is up"

say "fetching carbos"
rm -rf /root/carbos
git clone https://github.com/siku2/carbos.git /root/carbos

echo
echo "About to DESTROY the disk and install carbos."
read -rp "Type WIPE to continue: " answer
[ "$answer" = WIPE ] || die "aborted"

say "partitioning (disko)"
disko --mode destroy,format,mount --flake /root/carbos#carbon-x1

say "installing carbos"
nixos-install --flake /root/carbos#carbon-x1 --no-root-passwd

say "install complete"
read -rp "Reboot into carbos? [Yn] " answer
if [ -z "$answer" ] || [ "$answer" = y ] || [ "$answer" = Y ]; then
  reboot
fi
