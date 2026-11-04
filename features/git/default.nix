{
  # Credentials through the keyring.
  flake.modules.nixos.git.home-manager.sharedModules = [ ./home-nixos.nix ];

  flake.modules.darwin.git.home-manager.sharedModules = [ ./home-darwin.nix ];

  flake.modules.homeManager.git.imports = [
    ./fj.nix
    ./gh.nix
    ./git.nix
    ./signing.nix
  ];
}
