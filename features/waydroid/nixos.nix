{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.waydroid;
  waydroid = config.virtualisation.waydroid.package;
  images = pkgs.waydroid-images;

  setup = pkgs.writeText "android-setup.sh" (
    lib.concatLines (
      lib.optional (
        config.time.timeZone != null
      ) "setprop persist.sys.timezone ${lib.escapeShellArg config.time.timeZone}"
      ++ map (
        overlay: "cmd overlay enable-exclusive --category ${lib.escapeShellArg overlay}"
      ) cfg.overlays
    )
  );

  apps = pkgs.writeText "android-apps" (
    lib.concatLines (map (apk: "${apk.packageName} ${toString apk.versionCode} ${apk}") cfg.apps)
  );

  bridge = pkgs.writeShellApplication {
    name = "waydroid-bridge";
    runtimeInputs = [
      waydroid
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./bridge.sh;
  };
in
{
  imports = [ ./module.nix ];

  virtualisation.waydroid = {
    enable = true;
    # The default network script needs the legacy ip_tables module.
    package = pkgs.waydroid-nftables;
  };

  environment.etc."waydroid-extra/images".source = images;

  systemd.services.waydroid-init = {
    description = "Initialize Waydroid with the pinned images";
    before = [ "waydroid-container.service" ];
    requiredBy = [ "waydroid-container.service" ];
    path = [ waydroid ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      stamp=/var/lib/waydroid/carbos-images
      if [[ $(cat "$stamp" 2>/dev/null) != ${images} ]]; then
        waydroid init -f
        echo ${images} >"$stamp"
      fi
    '';
  };

  systemd.services.waydroid-bridge = {
    description = "Keep Android in sync with the host";
    after = [ "waydroid-container.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      SETUP = setup;
      APPS = apps;
    };
    serviceConfig.ExecStart = lib.getExe bridge;
  };

  services.cage = {
    enable = true;
    inherit (cfg) user;
    program = "${lib.getExe' waydroid "waydroid"} show-full-ui";
  };

  # waydroid show-full-ui ignores SIGTERM.
  systemd.services.cage-tty1.serviceConfig.TimeoutStopSec = 5;

  # A switch starts the getty, which conflicts with cage and stops it.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Android plays sound through the session's PulseAudio socket.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
}
