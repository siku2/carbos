# shellcheck shell=bash
# Applies $SETUP and $APPS once per Android boot and mirrors the battery.

android() {
  waydroid shell -- "$@" 2>/dev/null || true
}

supply() {
  local dir
  for dir in /sys/class/power_supply/*; do
    if [[ $(<"$dir/type") == "$1" ]]; then
      echo "$dir"
      return
    fi
  done
}

battery=$(supply Battery)
mains=$(supply Mains)
declare -A codes=([Charging]=2 [Discharging]=3 ["Not charging"]=4 [Full]=5)

setup() {
  local name version apk installed size
  android sh <"$SETUP"
  while read -r name version apk; do
    installed=$(android pm list packages --show-versioncode "$name" |
      awk -v p="package:$name" '$1 == p { sub("versionCode:", "", $2); print $2 }')
    if ((${installed:-0} < version)); then
      size=$(stat -c %s "$apk")
      android pm install -r -S "$size" <"$apk"
    fi
  done <"$APPS"
}

battery_state() {
  [[ -n $battery ]] || return 0
  local online=0
  [[ -z $mains ]] || online=$(<"$mains/online")
  echo "$(<"$battery/capacity") $online ${codes[$(<"$battery/status")]:-1}"
}

# system_server gets a new pid whenever Android boots, and a fresh boot
# forgets the setprops and battery overrides.
server=""
last=""
while true; do
  # shellcheck disable=SC2016 # expanded inside Android
  read -r booted pid <<<"$(android sh -c 'echo "$(getprop sys.boot_completed) $(pidof system_server)"')"
  if [[ $booted == 1 && -n $pid ]]; then
    if [[ $pid != "$server" ]]; then
      setup
      server=$pid
      last=""
    fi
    state=$(battery_state)
    if [[ -n $state && $state != "$last" ]]; then
      read -r level ac code <<<"$state"
      android sh -c "dumpsys battery set level $level; dumpsys battery set ac $ac; dumpsys battery set usb 0; dumpsys battery set status $code"
      last=$state
    fi
  else
    server=""
  fi
  sleep 10
done
