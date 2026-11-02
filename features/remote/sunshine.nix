{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Clients kick Sunshine more often than this while they stream.
  idleTimeout = "15min";
  kickInterval = "10min";

  ssh = lib.getExe pkgs.openssh;
  systemctl = lib.getExe' pkgs.systemd "systemctl";

  waitForSunshine = pkgs.writeShellApplication {
    name = "sunshine-wait";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.iproute2
    ];
    # Moonlight contacts the HTTP port first.
    text = ''
      until ss -Htln "sport = :${toString config.services.sunshine.settings.port}" | grep -q .; do
        sleep 0.2
      done
    '';
  };

  kick = pkgs.writeShellApplication {
    name = "sunshine-kick";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      systemctl --user start sunshine.service
      systemctl --user restart sunshine-idle.timer
    '';
  };
in
{
  services.sunshine = {
    enable = true;
    autoStart = false;
    # For KMS capture, which niri needs.
    capSysAdmin = true;
    openFirewall = true;
    # Otherwise anyone on the LAN can set the first credentials.
    settings.origin_web_ui_allowed = "pc";
  };

  systemd.user = {
    services.sunshine = {
      wants = [ "sunshine-idle.timer" ];
      # Start returns once Moonlight can connect.
      serviceConfig.ExecStartPost = lib.getExe waitForSunshine;
    };

    timers.sunshine-idle = {
      partOf = [ "sunshine.service" ];
      wantedBy = lib.mkForce [ ];
      timerConfig.OnActiveSec = idleTimeout;
    };

    services.sunshine-idle.serviceConfig = {
      Type = "oneshot";
      ExecStart = "${systemctl} --user stop sunshine.service";
    };

    services."moonlight@" = {
      description = "Moonlight stream to %i";
      wants = [ "sunshine-keepalive@%i.timer" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStartPre = "${ssh} %i sunshine-kick";
        ExecStart = "${lib.getExe pkgs.moonlight-qt} stream %i Desktop";
      };
    };

    timers."sunshine-keepalive@" = {
      bindsTo = [ "moonlight@%i.service" ];
      after = [ "moonlight@%i.service" ];
      wantedBy = lib.mkForce [ ];
      # Belongs to the stream, not to timers.target.
      unitConfig.DefaultDependencies = false;
      timerConfig = {
        OnActiveSec = kickInterval;
        OnUnitActiveSec = kickInterval;
      };
    };

    services."sunshine-keepalive@".serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ssh} %i sunshine-kick";
    };
  };

  environment.systemPackages = [
    pkgs.moonlight-qt
    kick
  ];
}
