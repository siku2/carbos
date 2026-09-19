# shellcheck shell=bash

# The Commander Core only has Direct, a software mode, and OpenRGB's destructor
# hands the device back to firmware on a clean exit, which is what restores the
# rainbow. --server keeps it alive long enough to apply the black frame, then
# SIGKILL skips the destructor and the frame sticks.
openrgb --noautoconnect --server --server-port 6743 \
  --device "Corsair Commander Core" --mode direct --color 000000 &
pid=$!

sleep 5
kill -9 "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
