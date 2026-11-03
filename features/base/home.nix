{ osConfig, ... }:
{
  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";
  };

  # Generating it pulls in an options.json derivation that nix warns about.
  manual.manpages.enable = false;

  programs.home-manager.enable = true;
}
