{
  config,
  lib,
  pkgs,
  ...
}:
let
  xoneWake = pkgs.writeShellApplication {
    name = "xone-wake";
    runtimeInputs = [ pkgs.uhubctl ];
    text = builtins.readFile ./xone-wake.sh;
  };
in
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-cachyos ];
  };

  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  hardware.xone.enable = true;

  # A wired pad only announces itself after power-up. When nothing answers,
  # at boot or across suspend, it shuts off and ignores USB resets and GIP
  # packets. Cutting port power is the only thing that brings it back.
  #
  # xone also turns on remote wakeup at probe, which can abort a suspend.
  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="xone-wired", ATTR{bInterfaceNumber}=="00", ATTR{../power/wakeup}="disabled", RUN+="${config.systemd.package}/bin/systemctl --no-block start xone-wake@%k.service"
  '';

  systemd.services."xone-wake@" = {
    description = "Power cycle %i if no Xbox controller announces itself";
    # The cycle rebinds the driver, so a pad that stays dead would loop.
    startLimitIntervalSec = 60;
    startLimitBurst = 3;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe xoneWake} %i";
    };
  };

  systemd.tmpfiles.rules = [
    "d /games/steamapps 0755 ${config.carbos.user.login} users -"
  ];

  # niri is sRGB only, so HDR runs only in the gamescope session. Without
  # the specialisation it is one more greeter entry, env vars and all.
  chaotic.hdr = {
    enable = true;
    specialisation.enable = false;
  };

  services.lact = {
    enable = true;
    settings = {
      version = 5;
      daemon = {
        log_level = "info";
        admin_group = "wheel";
        disable_clocks_cleanup = false;
      };
      apply_settings_timer = 5;
      # The stock 55 C is below the idle hotspot, so the fans never stop.
      gpus."1002:744C-1043:0506-0000:03:00.0".pmfw_options.zero_rpm_threshold = 65;
    };
  };

  environment.systemPackages = with pkgs; [
    mangohud
    prismlauncher
  ];
}
