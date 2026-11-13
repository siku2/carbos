{ config, pkgs, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-cachyos ];
  };

  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  carbos.kernel.drivers.xone.enable = true;

  # xone turns on remote wakeup at probe, which can abort a suspend.
  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="xone-wired", ATTR{bInterfaceNumber}=="00", ATTR{../power/wakeup}="disabled"
  '';

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
