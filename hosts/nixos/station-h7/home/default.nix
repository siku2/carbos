{ pkgs, ... }:
{
  imports = [
    ./easyeffects.nix
    ./niri.nix
    ./steam.nix
  ];

  # Vesktop instead of the official client: it can share audio on Wayland.
  home.packages = [ pkgs.vesktop ];

  carbos.wallpaper = {
    width = 7680;
    height = 2160;
  };
}
