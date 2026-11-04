{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Steam and Proton on the gaming host, Plexamp everywhere.
  nixpkgs.config.allowUnfree = true;
}
