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

  # xpad declares no reset_resume, so a pad that gets reset across suspend
  # comes back dead until it is replugged. xone's wired driver declares no pm
  # hooks at all, which makes the usb core reprobe it on every resume.
  hardware.xone.enable = true;

  # The symlinked steam library needs a real directory to point at.
  systemd.tmpfiles.rules = [
    "d /games/steamapps 0755 ${config.carbos.user.login} users -"
  ];

  # niri is sRGB only, so HDR lives in the gamescope session instead of the
  # desktop. Without the specialisation it is just another entry at the
  # greeter, and the env vars it sets stay on the gamescope wrapper.
  chaotic.hdr = {
    enable = true;
    specialisation.enable = false;
  };

  services.lact.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
    prismlauncher
  ];
}
