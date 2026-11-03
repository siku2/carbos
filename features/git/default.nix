{
  # Credentials through the keyring.
  flake.modules.nixos.git.home-manager.sharedModules = [ ./nixos-home.nix ];

  flake.modules.darwin.git.home-manager.sharedModules = [ ./darwin-home.nix ];

  flake.modules.homeManager.git.imports = [
    ./fj.nix
    ./gh.nix
    ./git.nix
    ./signing.nix
  ];
}
