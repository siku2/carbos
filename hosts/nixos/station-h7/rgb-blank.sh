# shellcheck shell=bash

# Names match case-insensitively as substrings and every match is applied.
off_mode=(
  "ENE DRAM"
  "ASUS TUF Radeon RX 7900 XTX Gaming OC"
  "ASUS TUF GAMING X670E-PLUS"
  "Razer Blackwidow Chroma V2"
  "Candy companion chip"
)

# No off mode on this one, so static black is the equivalent.
black_static=(
  "NZXT RGB & Fan Controller"
)

args=()
for dev in "${off_mode[@]}"; do
  args+=(--device "$dev" --mode off)
done
for dev in "${black_static[@]}"; do
  args+=(--device "$dev" --mode static --color 000000)
done

openrgb --config "$OPENRGB_CONFIG" --noautoconnect "${args[@]}"
