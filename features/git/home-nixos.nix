{ pkgs, ... }:
{
  home.packages = [ pkgs.git-credential-manager ];

  programs.git.settings.credential = {
    helper = "manager";
    credentialstore = "secretservice";
    "https://forge.stargrid.systems".provider = "generic";
  };
}
