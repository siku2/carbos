# shellcheck shell=bash
# Single-quoted snippets run in child shells or nix and expand there.
# shellcheck disable=SC2016
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo carbos-install "$@"
fi

export LOG=/tmp/carbos-install.log
: >"$LOG"
rev=$(cat /etc/carbos/rev)
started=$SECONDS
steps=(Host Network "Disk plan" "Verify store" Partition Install Done)
current=0
target=""

header() {
  local i
  clear
  gum style --border double --border-foreground 6 --padding "0 3" --margin "1 0" \
    --bold "carbos installer" "$(gum style --foreground 8 "rev $rev$target")"
  for i in "${!steps[@]}"; do
    if [ "$i" -lt "$current" ]; then
      gum style --foreground 2 "  [x] ${steps[$i]}"
    elif [ "$i" -eq "$current" ]; then
      gum style --foreground 6 --bold "  [>] ${steps[$i]}"
    else
      gum style --foreground 8 "  [ ] ${steps[$i]}"
    fi
  done
  echo
}
step() {
  current=$1
  header
}
info() { gum style --foreground 8 "$*"; }
die() {
  echo
  gum style --border normal --border-foreground 1 --foreground 1 --padding "0 1" \
    "ERROR" "$1" "" "Log: $LOG" "Run carbos-install to start over."
  exit 1
}
# Runs a command or exported function behind a spinner, output goes to $LOG.
run() {
  local title=$1
  shift
  gum spin --spinner line --title "$title" -- bash -c '"$@" >>"$LOG" 2>&1' _ "$@" ||
    die "$title failed"
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
  local disk=$1 part=$2 old=$3 num first esp top
  num=$(lsblk -nrpo NAME,PARTN "$disk" | awk -v p="$part" '$1 == p { print $2 }')
  first=$(sgdisk -i "$num" "$disk" | awk '/^First sector:/ { print $3 }')

  top=$(mktemp -d)
  mount -o subvolid=5 "$part" "$top"
  mkdir -p "$top/$old"
  find "$top" -mindepth 1 -maxdepth 1 ! -name old -exec mv -t "$top/$old" {} +
  umount "$top"
  rmdir "$top"

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
export -f keep_existing settle

# Host

step 0
mapfile -t hosts < <(jq -r 'keys[]' /etc/carbos/hosts.json)
host=${1:-}
if [ -z "$host" ]; then
  found=()
  for h in "${hosts[@]}"; do
    [ -e "$(jq -r --arg h "$h" '.[$h]' /etc/carbos/hosts.json)" ] && found+=("$h")
  done
  case ${#found[@]} in
  1) host=${found[0]} ;;
  0) host=$(gum choose --header "No known disk found. Pick a host:" "${hosts[@]}") ;;
  *) host=$(gum choose --header "Several known disks found. Pick a host:" "${found[@]}") ;;
  esac
fi
jq -e --arg h "$host" 'has($h)' /etc/carbos/hosts.json >/dev/null || die "unknown host $host"
disk=$(realpath "$(jq -r --arg h "$host" '.[$h]' /etc/carbos/hosts.json)")
[ -b "$disk" ] || die "disk $disk for $host not found"
target="  $host on $disk"

rm -rf /root/carbos
cp -r --no-preserve=mode "$(readlink -f /etc/carbos/source)" /root/carbos
flake="/root/carbos#nixosConfigurations.$host"

# Network

step 1
modprobe iwlwifi 2>/dev/null || true
rfkill unblock all 2>/dev/null || true
if ! online; then
  if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
    if gum confirm "Offline. Open nmtui to configure wifi?"; then
      nmtui
    fi
  else
    info "No wifi device (on carbon-x1 this is the CNVi quirk after kexec)."
    gum confirm --affirmative Continue --negative Abort \
      "Connect ethernet or USB tethering, then continue." || die "aborted"
  fi
  gum spin --spinner line --title "Waiting for the network" -- bash -c \
    'for _ in $(seq 20); do curl -fsS --max-time 5 -o /dev/null https://github.com && exit 0; sleep 3; done; exit 1' ||
    die "no network"
fi

# Disk plan

step 2
part=$(lsblk -nrpo NAME,TYPE,FSTYPE "$disk" | awk '$2 == "part" && $3 == "btrfs" { print $1 }')
mode=wipe
if [ "$(printf '%s' "$part" | grep -c .)" -eq 1 ]; then
  choice=$(gum choose --header "$part holds a btrfs filesystem. What should happen to it?" \
    "Keep its data under /old" "Wipe the whole disk")
  [ "$choice" = "Wipe the whole disk" ] || mode=keep
fi

old="old/$(date +%Y%m%d-%H%M%S)"
if [ "$mode" = keep ]; then
  num=$(lsblk -nrpo NAME,PARTN "$disk" | awk -v p="$part" '$1 == p { print $2 }')
  first=$(sgdisk -i "$num" "$disk" | awk '/^First sector:/ { print $3 }')
  esp_bytes=$((first * $(blockdev --getss "$disk")))
  [ "$esp_bytes" -ge $((512 * 1024 * 1024)) ] ||
    die "less than 512M in front of $part, no room for the ESP"
fi

layout=$(gum spin --spinner line --show-output --title "Reading the $host disk layout" -- \
  nix eval --raw "$flake.config.disko.devices.disk.main.content.partitions" --apply '
    ps: builtins.concatStringsSep "\n" (map (p:
      "${p.name}|${p.size}|${p.content.format or p.content.type}|"
      + builtins.concatStringsSep " " (map (s: s.mountpoint)
        (builtins.attrValues (p.content.subvolumes or { }))))
      (builtins.sort (a: b: a.priority < b.priority) (builtins.attrValues ps)))') ||
  die "could not evaluate the disk layout of $host"

now=$(lsblk -o NAME,FSTYPE,LABEL,SIZE "$disk")
after=""
n=0
while IFS='|' read -r name size fs subvols; do
  n=$((n + 1))
  if [ "$mode" = keep ] && [ "$fs" = btrfs ]; then
    size="$(lsblk -dno SIZE "$part" | tr -d ' ') kept"
  elif [ "$mode" = keep ]; then
    size="$(numfmt --to=iec "$esp_bytes") new"
  fi
  after+=$(printf "p%-3s%-8s%-7s%s" "$n" "$name" "$fs" "$size")$'\n'
  [ -z "$subvols" ] || after+="    $subvols"$'\n'
done <<<"$layout"
if [ "$mode" = keep ]; then
  after+=$'\n'"old data -> /$old"
else
  after+=$'\n'"everything else is erased"
fi

gum join --horizontal \
  "$(gum style --border normal --padding "0 1" --margin "0 2 0 0" "$(gum style --bold Now)" "" "$now")" \
  "$(gum style --border normal --border-foreground 6 --padding "0 1" "$(gum style --bold "After ($mode)")" "" "${after%$'\n'}")"
echo

word=$([ "$mode" = keep ] && echo KEEP || echo WIPE)
answer=$(gum input --placeholder "Type $word to install $host on $disk")
[ "$answer" = "$word" ] || die "aborted"

# Verify store

step 3
gum spin --spinner line --title "Hashing every path of the bundled store" -- bash -c '
  while :; do
    case $(systemctl show -P ActiveState carbos-verify) in
    active | failed) exit 0 ;;
    esac
    sleep 1
  done'
[ "$(systemctl show -P ActiveState carbos-verify)" = active ] ||
  die "the bundled store is corrupt in memory, see journalctl -u carbos-verify"

# Partition

step 4
if [ "$mode" = keep ]; then
  run "Moving old data to /$old" keep_existing "$disk" "$part" "$old"
  run "Partitioning with disko" disko --mode format,mount --flake "/root/carbos#$host"
else
  run "Partitioning with disko" disko --mode destroy,format,mount --yes-wipe-all-disks \
    --flake "/root/carbos#$host"
fi

# Install

step 5
nix build --store /mnt --out-link /tmp/system --log-format internal-json -v \
  "$flake.config.system.build.toplevel" |& nom --json || die "building $host failed"
run "Installing the bootloader" \
  nixos-install --system "$(readlink /tmp/system)" --no-root-passwd --no-channel-copy

# Done

step 6
elapsed=$((SECONDS - started))
summary=("Host: $host" "Disk: $disk" "Mode: $mode" "Rev:  $rev"
  "Time: $((elapsed / 60))m $((elapsed % 60))s")
if [ "$mode" = keep ]; then
  summary+=("" "Old data is in /$old on the btrfs top level:"
    "  mount -o subvolid=5 /dev/disk/by-partlabel/disk-main-carbos /mnt")
fi
gum style --border double --border-foreground 2 --padding "0 2" \
  "$(gum style --bold --foreground 2 "carbos is installed")" "" "${summary[@]}"
echo
if gum confirm "Reboot into carbos?"; then
  reboot
fi
