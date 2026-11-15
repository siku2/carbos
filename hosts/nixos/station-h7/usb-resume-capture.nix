{ lib, pkgs, ... }:
let
  # The SSL 2 MkII sits on port 2 of this hub inside the dock.
  hub = "1-1.4.2";

  capture = pkgs.writeShellApplication {
    name = "usb-resume-capture";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      kmod
      systemd
      uhubctl
      usbutils
      zstd
    ];
    text = ''
      root=/var/log/usb-resume
      dir=$root/$(date +%Y%m%d-%H%M%S)
      mkdir -p "$dir"
      find "$root" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} +

      dyndbg=/sys/kernel/debug/dynamic_debug/control
      since=$(date '+%Y-%m-%d %H:%M:%S')

      snapshot() {
        {
          date --iso-8601=ns
          lsusb -t
          uhubctl -l ${hub} || true
          for port in /sys/bus/usb/devices/${hub}:1.0/${hub}-port*; do
            echo "$port over_current_count=$(cat "$port/over_current_count")"
          done
        } >"$dir/$1.txt" 2>&1
      }

      cleanup() {
        kill "$mon" 2>/dev/null || true
        wait "$mon" || true
        echo 'file drivers/usb/core/hub.c -p' >"$dyndbg"
        snapshot after
        journalctl -k --since "$since" >"$dir/kernel.txt"
        zstd -q --rm "$dir/usbmon-bus1.txt"
      }

      modprobe usbmon
      echo 'file drivers/usb/core/hub.c +p' >"$dyndbg"
      head -c 200M /sys/kernel/debug/usb/usbmon/1u >"$dir/usbmon-bus1.txt" &
      mon=$!
      trap cleanup EXIT
      trap 'exit 143' TERM INT
      snapshot before
      systemd-notify --ready

      # Counts awake seconds only, so a suspend that never happens ends the
      # capture after 5 minutes.
      sleeps() {
        echo $(($(cat /sys/power/suspend_stats/success) + $(cat /sys/power/suspend_stats/fail)))
      }
      start=$(sleeps)
      for _ in $(seq 300); do
        [ "$(sleeps)" != "$start" ] && break
        sleep 1
      done
      sleep 60
    '';
  };
in
{
  systemd.services.usb-resume-capture = {
    description = "Capture USB bus 1 across suspend";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = lib.getExe capture;
    };
  };
}
