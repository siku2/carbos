{ pkgs, ... }:
{
  imports = [
    ./easyeffects.nix
    ./niri.nix
  ];

  # Only for gaming, which only happens on this machine. Vesktop rather than
  # the official client because it is the one that can share audio on Wayland.
  home.packages = [ pkgs.vesktop ];
}
