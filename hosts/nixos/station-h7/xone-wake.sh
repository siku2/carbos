# shellcheck shell=bash

iface=$1
dev=${iface%%:*}

shopt -s nullglob

for _ in $(seq 50); do
  clients=("/sys/bus/usb/devices/$iface"/gip*/gip*.*)
  if ((${#clients[@]})); then
    exit 0
  fi
  sleep 0.1
done

[[ -e /sys/bus/usb/devices/$iface ]] || exit 0

# 1-1.4.4 is port 4 on hub 1-1.4, 1-4 is port 4 on root hub 1.
if [[ $dev == *.* ]]; then
  hub=${dev%.*}
  port=${dev##*.}
else
  hub=${dev%%-*}
  port=${dev#*-}
fi

echo "no controller announced on $dev, power cycling hub $hub port $port"
# The USB3 twin port shares VBUS, so it has to go off as well.
uhubctl --location "$hub" --ports "$port" --nodesc --action cycle --delay 2
