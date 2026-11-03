{
  # Signing and credentials through rbw and the keyring.
  flake.modules.nixos.git.home-manager.sharedModules = [ ./nixos-home.nix ];

  flake.modules.homeManager.git.imports = [
    ./fj.nix
    ./gh.nix
    ./git.nix
  ];
}
