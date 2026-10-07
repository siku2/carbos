{ config, pkgs, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-cachyos ];
  };

  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  programs.gamemode.enable = true;

  # xpad has no reset_resume, so a pad reset across suspend stays dead until
  # replugged. xone's wired driver has no pm hooks, so usb reprobes it.
  hardware.xone.enable = true;

  systemd.tmpfiles.rules = [
    "d /games/steamapps 0755 ${config.carbos.user.login} users -"
  ];

  # niri is sRGB only, so HDR runs only in the gamescope session. Without
  # the specialisation it is one more greeter entry, env vars and all.
  chaotic.hdr = {
    enable = true;
    specialisation.enable = false;
  };

  services.lact.enable = true;

  carbos.rlbot.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    prismlauncher
  ];
}
