{ pkgs, ... }:
{
  imports = [
    ./ardour
    ./git.nix
    ./mic/module.nix
    ./vesktop
  ];

  home.packages = [ pkgs.git-credential-manager ];
}
