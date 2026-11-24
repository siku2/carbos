{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    protontricks.enable = true;
    extraCompatPackages = [ pkgs.proton-cachyos-bin_edge ];
  };

  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  environment.systemPackages = [ pkgs.mangohud ];
}
