{
  home.stateVersion = "26.05";

  # Generating it pulls in an options.json derivation that nix warns about.
  manual.manpages.enable = false;

  programs.home-manager.enable = true;
}
