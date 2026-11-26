{
  config,
  lib,
  pkgs,
  ...
}:
{
  virtualisation.waydroid = {
    enable = true;
    # The kernel has no legacy ip_tables, so the default network script fails.
    package = pkgs.waydroid-nftables;
  };

  services.cage = {
    enable = true;
    user = config.carbos.user.login;
    program = "${lib.getExe' config.virtualisation.waydroid.package "waydroid"} show-full-ui";
  };

  # A switch starts the getty, which conflicts with cage and stops it.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # waydroid show-full-ui ignores SIGTERM.
  systemd.services.cage-tty1.serviceConfig.TimeoutStopSec = 5;

  # Waydroid's health HAL reports a fixed battery, so the real one is pushed in.
  systemd.services.waydroid-battery = {
    description = "Pass the battery state to Waydroid";
    after = [ "waydroid-container.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.virtualisation.waydroid.package ];
    script = ''
      declare -A codes=([Charging]=2 [Discharging]=3 ["Not charging"]=4 [Full]=5)
      last=""
      ticks=0
      while true; do
        status=$(</sys/class/power_supply/BAT1/status)
        state="$(</sys/class/power_supply/BAT1/capacity) $(</sys/class/power_supply/AC/online) ''${codes[$status]:-1}"
        # Android forgets the override when the container restarts.
        if [[ $state != "$last" || $ticks -ge 30 ]]; then
          read -r level ac code <<<"$state"
          # waydroid shell exits 0 even when the container is stopped.
          out=$(waydroid shell -- sh -c "dumpsys battery set level $level; dumpsys battery set ac $ac; dumpsys battery set usb 0; dumpsys battery set status $code; echo pushed" 2>/dev/null || true)
          if [[ $out == *pushed* ]]; then
            last=$state
            ticks=0
          fi
        fi
        ticks=$((ticks + 1))
        sleep 10
      done
    '';
  };

  # Android plays sound through the session's PulseAudio socket.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
}
