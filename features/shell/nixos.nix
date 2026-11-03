{ config, pkgs, ... }:
{
  programs.fish.enable = true;

  users.users.${config.carbos.user.login}.shell = pkgs.fish;
}
