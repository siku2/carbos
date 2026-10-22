# shellcheck shell=bash

read -ra sets <<<"$WALLPAPER_SETS"

# 10# because date pads with zeros, which bash would read as octal.
day=$((10#$(date +%j)))
hour=$((10#$(date +%H)))
set=${sets[day % ${#sets[@]}]}

dms ipc call wallpaper set "$WALLPAPERS/$set/$hour.jpg"
