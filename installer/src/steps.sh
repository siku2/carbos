# shellcheck shell=bash
# One function per installer step. The steps up to step_plan only fill PLAN,
# the ones after it carry it out.

step_host() {
  local found hosts disk
  if [ -n "$OPT_HOST" ]; then
    PLAN[host]=$OPT_HOST
  else
    mapfile -t found < <(bundle_detect_hosts)
    mapfile -t hosts < <(bundle_hosts)
    case ${#found[@]} in
    1) PLAN[host]=${found[0]} ;;
    0) PLAN[host]=$(ui_choose "No known disk found. Pick a host:" "${hosts[@]}") ;;
    *) PLAN[host]=$(ui_choose "Several known disks found. Pick a host:" "${found[@]}") ;;
    esac
  fi
  disk=$(host_get "${PLAN[host]}" disk)
  [ -n "$disk" ] || ui_die "unknown host ${PLAN[host]}"
  [ -b "$disk" ] || ui_die "disk $disk of ${PLAN[host]} not found"
  PLAN[disk]=$(realpath "$disk")
}

online() { curl -fsS --max-time 5 -o /dev/null https://github.com; }

wait_online() {
  for _ in $(seq 20); do
    online && return
    sleep 3
  done
  return 1
}

step_network() {
  if [ -n "$(host_get "${PLAN[host]}" system)" ]; then
    ui_info "The system is bundled, nothing to download."
    return
  fi
  modprobe iwlwifi 2>/dev/null || :
  rfkill unblock all 2>/dev/null || :
  online && return
  if nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
    ui_confirm "Offline. Open nmtui to configure wifi?" && nmtui
  elif ui_interactive; then
    ui_info "No wifi device (on carbon-x1 this is the CNVi quirk after kexec)."
    ui_confirm --affirmative Continue --negative Abort \
      "Connect ethernet or USB tethering, then continue." || ui_die "aborted"
  fi
  ui_spin "Waiting for the network" wait_online
}

plan_show() {
  local now after=() num name fs size subvols
  now=$(lsblk -o NAME,FSTYPE,LABEL,SIZE "${PLAN[disk]}")
  while IFS=$'\t' read -r num name fs size subvols; do
    if [ "${PLAN[mode]}" = keep ] && [ "$fs" = btrfs ]; then
      size="$(lsblk -dnro SIZE "${PLAN[part]}") kept"
    elif [ "${PLAN[mode]}" = keep ]; then
      size="$(numfmt --to=iec "${PLAN[esp_bytes]}") new"
    fi
    after+=("$(printf 'p%-3s%-8s%-7s%s' "$num" "$name" "$fs" "$size")")
    [ -z "$subvols" ] || after+=("    $subvols")
  done < <(host_layout "${PLAN[host]}")
  after+=("")
  if [ "${PLAN[mode]}" = keep ]; then
    after+=("old data -> /${PLAN[old]}")
  else
    after+=("everything else is erased")
  fi
  gum join --horizontal "$(ui_box 7 Now "$now")" "  " \
    "$(ui_box 6 "After (${PLAN[mode]})" "${after[@]}")"
  echo
}

step_plan() {
  local parts mode=$OPT_MODE choice word
  mapfile -t parts < <(disk_btrfs_parts "${PLAN[disk]}")
  if [ -z "$mode" ] && [ ${#parts[@]} -eq 1 ]; then
    choice=$(ui_choose "${parts[0]} holds a btrfs filesystem. What should happen to it?" \
      "Keep its data under /old" "Wipe the whole disk")
    case $choice in
    Keep*) mode=keep ;;
    Wipe*) mode=wipe ;;
    esac
  fi
  PLAN[mode]=${mode:-wipe}

  if [ "${PLAN[mode]}" = keep ]; then
    [ ${#parts[@]} -eq 1 ] ||
      ui_die "keeping data needs exactly one btrfs partition on ${PLAN[disk]}"
    PLAN[part]=${parts[0]}
    PLAN[esp_bytes]=$(part_start_bytes "${PLAN[part]}")
    [ "${PLAN[esp_bytes]}" -ge $((512 * 1024 * 1024)) ] ||
      ui_die "less than 512M in front of ${PLAN[part]}, no room for the ESP"
    PLAN[old]="old/$(date +%Y%m%d-%H%M%S)"
  fi

  plan_show
  [ -z "$OPT_DRY_RUN$OPT_UNATTENDED" ] || return 0
  word=${PLAN[mode]^^}
  ui_confirm_word "$word" "Type $word to install ${PLAN[host]} on ${PLAN[disk]}" ||
    ui_die "aborted"
}

verify_wait() {
  while :; do
    case $(systemctl show -P ActiveState carbos-verify) in
    active | failed) return ;;
    esac
    sleep 1
  done
}

step_verify() {
  if [ "$(systemctl show -P LoadState carbos-verify)" != loaded ]; then
    ui_info "Not running from the installer image, nothing to verify."
    return
  fi
  ui_spin "Hashing every path of the bundled store" verify_wait
  [ "$(systemctl show -P ActiveState carbos-verify)" = active ] ||
    ui_die "the bundled store is corrupt, see journalctl -u carbos-verify"
}

step_partition() {
  local host=${PLAN[host]}
  if [ "${PLAN[mode]}" = keep ]; then
    ui_spin "Moving old data to /${PLAN[old]}" \
      disk_keep_existing "${PLAN[disk]}" "${PLAN[part]}" "${PLAN[old]}"
    ui_spin "Partitioning with disko" "$(host_get "$host" formatMount)"
  else
    ui_spin "Partitioning with disko" \
      "$(host_get "$host" destroyFormatMount)" --yes-wipe-all-disks
  fi
}

# cache_check OUT FLAKE NIX_FLAG...
#
# Writes the packages that no cache provides to OUT, one name per line.
# Config glue has no pname and downloads have an outputHash, so both are
# left out. The dry run also puts every derivation into the installer store.
cache_check() {
  local out=$1 drvs
  shift
  mapfile -t drvs < <(nix build --dry-run "$@" 2>&1 | tee -a "$LOG" |
    awk '/will be built:/ { f = 1; next } /^  / { if (f) print $1; next } { f = 0 }')
  : >"$out"
  [ ${#drvs[@]} -gt 0 ] || return 0
  nix derivation show "${drvs[@]}" | jq -r '
    (.derivations // .) | to_entries[]
    | ((.value.structuredAttrs // {}) + .value.env) as $attrs
    | select($attrs.pname != null and $attrs.outputHash == null)
    | .key' | sed 's/^[a-z0-9]\{32\}-//; s/\.drv$//' | sort -u >"$out"
}

step_install() {
  local host=${PLAN[host]} system flake subs keys missing pkgs
  system=$(host_get "$host" system)
  if [ -z "$system" ]; then
    flake="path:$(bundle_get .source)#nixosConfigurations.$host.config.system.build.toplevel"
    subs=$(host_get "$host" 'substituters | join(" ")')
    keys=$(host_get "$host" 'trustedPublicKeys | join(" ")')
    missing=$(mktemp)
    ui_spin "Asking the caches of $host what is missing" cache_check "$missing" "$flake" \
      --extra-substituters "$subs" --extra-trusted-public-keys "$keys"
    if [ -s "$missing" ]; then
      mapfile -t pkgs <"$missing"
      ui_box 3 "${#pkgs[@]} packages are in no cache and will be compiled" "${pkgs[@]}"
      echo
      if ui_interactive; then
        ui_confirm "Compile them?" || ui_die "aborted"
      fi
    fi
    # The derivations stay in the installer store, where nix-output-monitor
    # reads them. Only the outputs go to /mnt.
    ui_nix_build --store /mnt --eval-store auto --out-link /tmp/carbos-system \
      --extra-substituters "auto?trusted=1 $subs" --extra-trusted-public-keys "$keys" "$flake" ||
      ui_die "building $host failed"
    system=$(readlink /tmp/carbos-system)
  fi
  ui_spin "Installing the system" \
    nixos-install --system "$system" --no-root-passwd --no-channel-copy
}

repo_fetch() {
  local repo dest=/mnt/etc/nixos
  repo=$(bundle_get .repo)
  rm -rf "$dest"
  if [ -n "$repo" ] && online && git clone "$repo" "$dest"; then
    return
  fi
  echo "cloning failed, copying the bundled source instead"
  cp -r "$(bundle_get .source)" "$dest"
  chmod -R u+w "$dest"
}

step_repo() {
  local login id
  ui_spin "Cloning the repository to /etc/nixos" repo_fetch
  login=$(host_get "${PLAN[host]}" login)
  id=$(awk -F: -v u="$login" '$1 == u { print $3 ":" $4 }' /mnt/etc/passwd)
  [ -z "$id" ] || chown -R "$id" /mnt/etc/nixos
}

step_finish() {
  local elapsed=$((SECONDS - STARTED)) lines label
  lines=("Host: ${PLAN[host]}" "Disk: ${PLAN[disk]}" "Mode: ${PLAN[mode]}"
    "Rev:  $(bundle_get .rev)" "Time: $((elapsed / 60))m $((elapsed % 60))s")
  if [ "${PLAN[mode]}" = keep ]; then
    label=$(host_get "${PLAN[host]}" 'partitions[] | select(.fs == "btrfs") | .label')
    lines+=("" "Old data is in /${PLAN[old]} on the btrfs top level:"
      "  mount -o subvolid=5 /dev/disk/by-partlabel/$label /mnt")
  fi
  ui_box 2 "carbos is installed" "${lines[@]}"
  echo
  if ui_confirm "Reboot into carbos?"; then
    reboot
  fi
}
