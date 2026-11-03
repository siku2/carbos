{
  imports = [ ./packages ];

  flake.modules.nixos.nix.imports = [
    ./nixos.nix
    ./unfree.nix
  ];

  flake.modules.darwin.nix = ./unfree.nix;

  flake.modules.homeManager.nix = ./direnv.nix;
}
