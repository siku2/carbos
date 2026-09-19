{ pkgs, ... }:
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
