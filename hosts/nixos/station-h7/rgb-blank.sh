# shellcheck shell=bash

# Names match case-insensitively as substrings and every match is applied, so
# one "ENE DRAM" entry covers both sticks.
off_mode=(
  "ENE DRAM"
  "ASUS TUF Radeon RX 7900 XTX Gaming OC"
  "ASUS TUF GAMING X670E-PLUS"
  "Razer Blackwidow Chroma V2"
  "Logitech G903 Wired/Wireless Gaming Mouse"
  "Candy companion chip"
)

# No off mode on this one, so static black is the equivalent.
black_static=(
  "NZXT RGB & Fan Controller"
)

blank() {
  local dev=$1
  shift
  openrgb --noautoconnect --device "$dev" "$@" || echo "could not blank $dev" >&2
}

for dev in "${off_mode[@]}"; do
  blank "$dev" --mode off
done

for dev in "${black_static[@]}"; do
  blank "$dev" --mode static --color 000000
done
