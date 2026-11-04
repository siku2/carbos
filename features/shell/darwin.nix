{ pkgs, ... }:
{
  # chsh only accepts shells listed in /etc/shells.
  environment.shells = [ pkgs.fish ];
}
