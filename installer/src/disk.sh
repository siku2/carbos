# shellcheck shell=bash
# Disk inspection reads sysfs and lsblk only, so a dry run needs no root.

# Prints the btrfs partitions of DISK.
disk_btrfs_parts() {
  lsblk -nrpo NAME,TYPE,FSTYPE "$1" | awk '$2 == "part" && $3 == "btrfs" { print $1 }'
}

part_number() { cat "/sys/class/block/${1##*/}/partition"; }

# Sysfs counts in 512-byte sectors, whatever the logical sector size.
part_start_bytes() { echo $(($(cat "/sys/class/block/${1##*/}/start") * 512)); }

disk_sector_size() { cat "/sys/class/block/${1##*/}/queue/logical_block_size"; }

disk_settle() {
  partprobe "$1" || :
  udevadm settle --timeout 120
}

# disk_keep_existing DISK PART OLD
#
# Moves the top-level contents of the btrfs PART into OLD on the same
# filesystem, then replaces every other partition with a blank one in front of
# PART. The disko format script afterwards only labels, formats and adds what
# is missing.
disk_keep_existing() {
  local disk=$1 part=$2 old=$3 num end top n
  num=$(part_number "$part")
  end=$(($(part_start_bytes "$part") / $(disk_sector_size "$disk") - 1))

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
  sgdisk --new="1:0:$end" "$disk"
  disk_settle "$disk"
  wipefs -a "$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 1 { print $1 }')"
  disk_settle "$disk"
}
