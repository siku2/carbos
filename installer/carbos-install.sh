# shellcheck shell=bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo carbos-install "$@"
fi

say() { printf "\n==> %s\n" "$1"; }
die() {
  printf "ERROR: %s\n" "$1" >&2
  exit 1
}
yes_default() {
  local answer
  read -rp "$1 [Yn] " answer
  [ -z "$answer" ] || [ "$answer" = y ] || [ "$answer" = Y ]
}
online() { curl -fsS --max-time 5 -o /dev/null https://github.com; }
settle() {
  partprobe "$1" || :
  udevadm settle --timeout 120
}

# Keeps the single btrfs partition on the disk and moves its top-level
# contents to /old/<timestamp>. Every other partition is replaced by an ESP
# in front of it, so disko's non-destructive format only adds what is missing.
keep_existing() {
  local disk=$1 part=$2 num first sector_size esp top old
  num=$(lsblk -nrpo NAME,PARTN "$disk" | awk -v p="$part" '$1 == p { print $2 }')
  first=$(sgdisk -i "$num" "$disk" | awk '/^First sector:/ { print $3 }')
  sector_size=$(blockdev --getss "$disk")
  [ $((first * sector_size)) -ge $((512 * 1024 * 1024)) ] ||
    die "less than 512M in front of $part, no room for the ESP"

  say "moving the old subvolumes to /old"
  top=$(mktemp -d)
  mount -o subvolid=5 "$part" "$top"
  old="old/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$top/$old"
  find "$top" -mindepth 1 -maxdepth 1 ! -name old -exec mv -t "$top/$old" {} +
  umount "$top"
  rmdir "$top"

  say "replacing the other partitions with an ESP"
  for n in $(lsblk -nrpo PARTN "$disk" | grep .); do
    [ "$n" = "$num" ] || sgdisk --delete="$n" "$disk"
  done
  [ "$num" = 2 ] || sgdisk --transpose="$num:2" "$disk"
  sgdisk --new=1:0:$((first - 1)) "$disk"
  settle "$disk"
  esp=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 1 { print $1 }')
  wipefs -a "$esp"
  settle "$disk"
}

say "carbos installer"

say "bringing up network"
modprobe iwlwifi 2>/dev/null || true
rfkill unblock all 2>/dev/null || true

if ! online; then
  if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
    echo "wifi device present but offline"
    if yes_default "Open nmtui to configure wifi?"; then
      nmtui
    fi
  else
    echo "no wifi device (on carbon-x1 this is the CNVi quirk after kexec)"
    read -rp "Connect ethernet or USB tethering, then press Enter..." _
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

mapfile -t hosts < <(ls /root/carbos/hosts)
host=${1:-}
if [ -z "$host" ]; then
  echo "hosts: ${hosts[*]}"
  read -rp "Host to install: " host
fi
printf '%s\n' "${hosts[@]}" | grep -qx "$host" || die "unknown host $host"
flake="/root/carbos#$host"

disk=$(realpath "$(nix eval --raw "/root/carbos#nixosConfigurations.$host.config.disko.devices.disk.main.device")")
[ -b "$disk" ] || die "disk $disk not found"
say "target disk is $disk"
lsblk -o NAME,FSTYPE,LABEL,SIZE "$disk"

part=$(lsblk -nrpo NAME,TYPE,FSTYPE "$disk" | awk '$2 == "part" && $3 == "btrfs" { print $1 }')
mode=wipe
if [ "$(printf '%s' "$part" | grep -c .)" -eq 1 ]; then
  echo
  echo "$part holds a btrfs filesystem."
  if yes_default "Keep its data under /old instead of wiping the disk?"; then
    mode=keep
  fi
fi

echo
if [ "$mode" = keep ]; then
  echo "About to move everything on $part to /old and ERASE all other partitions."
  read -rp "Type KEEP to continue: " answer
  [ "$answer" = KEEP ] || die "aborted"
  keep_existing "$disk" "$part"
  say "partitioning (disko, keeping data)"
  disko --mode format,mount --flake "$flake"
else
  echo "About to DESTROY $disk and install carbos."
  read -rp "Type WIPE to continue: " answer
  [ "$answer" = WIPE ] || die "aborted"
  say "partitioning (disko)"
  disko --mode destroy,format,mount --flake "$flake"
fi

say "installing carbos"
nixos-install --flake "$flake" --no-root-passwd

say "install complete"
if [ "$mode" = keep ]; then
  echo "Old data is in /old on the btrfs top level. Mount it with -o subvolid=5."
fi
if yes_default "Reboot into carbos?"; then
  reboot
fi
