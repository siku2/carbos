{ pkgs, ... }:
{
  # No tray and no background mode, so notifications only arrive while a
  # window is open.
  home.packages = [ pkgs.fractal ];
}
