{
  imports = [ ./packages ];

  flake.modules.nixos.nix.imports = [
    ./nixos.nix
    ./settings.nix
    ./unfree.nix
  ];

  flake.modules.darwin.nix.imports = [
    ./darwin.nix
    ./settings.nix
    ./unfree.nix
  ];

  flake.modules.homeManager.nix = ./direnv.nix;
}
