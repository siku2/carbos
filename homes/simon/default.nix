{ pkgs, ... }:
{
  imports = [ ./git.nix ];

  home.packages = [ pkgs.git-credential-manager ];
}
