# shellcheck shell=bash
# Read access to the bundle that installer/bundle.nix builds at $CARBOS_BUNDLE.

bundle_get() { jq -r "$1 // empty" "$CARBOS_BUNDLE"; }

bundle_hosts() { jq -r '.hosts | keys[]' "$CARBOS_BUNDLE"; }

# host_get HOST FIELD
host_get() { jq -r --arg h "$1" ".hosts[\$h].$2 // empty" "$CARBOS_BUNDLE"; }

# Prints one line per partition: number, name, filesystem, size, subvolumes.
host_layout() {
  jq -r --arg h "$1" '
    .hosts[$h].partitions | to_entries[]
    | [.key + 1, .value.name, .value.fs, .value.size, (.value.subvolumes | join(" "))]
    | @tsv' "$CARBOS_BUNDLE"
}

# Prints the hosts whose disk is attached to this machine.
bundle_detect_hosts() {
  local host
  for host in $(bundle_hosts); do
    [ ! -e "$(host_get "$host" disk)" ] || echo "$host"
  done
}
