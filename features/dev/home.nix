{ pkgs, ... }:
{
  home.packages = [
    pkgs.ansifilter
    pkgs.devcontainer
  ];
}
